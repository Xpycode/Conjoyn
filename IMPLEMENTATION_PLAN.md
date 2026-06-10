# DJIjoiner — Implementation Plan

> Generated 2026-06-07 from `specs/dji-auto-stitcher.md`, the two briefs in `docs/`, the
> P2toMXF port inventory, and four research sweeps (DJI domain, Apple APIs, FFmpeg/exiftool/
> notarization). Plans are disposable — regenerate if trajectory diverges.

## Goal
A native macOS app (SwiftUI/Swift 6, macOS 14+, arm64, direct-distribution + notarized) that
auto-groups split DJI MP4 segments, joins them losslessly (FFmpeg concat demuxer `-c copy`),
fixes date/timecode metadata natively, stitches the per-segment `.SRT` telemetry with
cumulative-offset correction, and automates ingest via a watch-folder.

## Strategy
**Port ~70% of P2toMXF unchanged** (queue, subprocess, verify, ETA, sleep, bookmarks, disk
preflight, thumbnails) and build a new **DJI front-end** (metadata reader, filename parser,
grouping, SRT stitcher, watch-folder), **dropping the BMX stage** (DJI MP4s are self-contained).
Reference source: `_reference/P2toMXF/01_Project/P2toMXF/`. Keep `DJIFolderReader`'s
`validate/discover/parse` interface identical to `P2CardParser` so the ViewModel ports by rename.

## Backpressure (every task)
- **Compiles:** `xcodebuild -scheme DJIjoiner -destination 'platform=macOS' build` is green.
- **Engine tasks:** a focused unit test (XCTest) passes against fixture data.
- **Lint:** `swiftlint` clean (if adopted).
- Never mark a task done on "build succeeded" alone where a behavioral test is specified.

## Test assets needed (gating Wave 2+ validation)
Real split recordings from the target drones (Mavic/Air/Mini), ideally one **legacy-naming**
set and one **timestamped-naming** set, each with `.SRT` (and `.LRF`) sidecars, plus one
multi-camera set (`_W`/`_Z` or `_T`/`_V`) to prove the variant guard. **Action: user to supply.**

---

## Wave 0 — Scaffold & toolchain (no deps)

| # | Task | Target | Success criteria | Backpressure |
|---|------|--------|------------------|--------------|
| 0.1 | Create Xcode macOS app project | `01_Project/DJIjoiner.xcodeproj` | SwiftUI lifecycle, Swift 6 language mode, deploy target macOS 14.0, arm64, bundle id `com.<you>.djijoiner`, team set | builds & runs empty window |
| 0.2 | Build settings for subprocess + notarization | project/target build settings | App Sandbox **OFF**, Hardened Runtime **ON**, `ENABLE_USER_SCRIPT_SANDBOXING=NO`, single deploy target (no 14/15.6 split) | builds |
| 0.3 | Entitlements file | `01_Project/DJIjoiner/DJIjoiner.entitlements` | 3 keys: `cs.disable-library-validation`, `cs.allow-unsigned-executable-memory`, `cs.allow-jit` | builds signed |
| 0.4 | Acquire/build static arm64 **LGPL** FFmpeg + ffprobe | `01_Project/DJIjoiner/Resources/Helpers/{ffmpeg,ffprobe}` | `file ffmpeg` = arm64 Mach-O; `ffmpeg -version` runs; LGPL (no `--enable-gpl`). Interim: OSXExperts 8.1 + GPL notice if needed | `./ffmpeg -version`, `./ffprobe -version` exit 0 |
| 0.5 | Bundle helpers into app + sign script | Copy Files build phase; `sign-bundled-binaries.sh` (trimmed to ffmpeg/ffprobe) | helpers land in `…app/Contents/Resources/Helpers/`, signed `--options runtime --timestamp` | `codesign -dv` on helper OK |
| 0.6 | Git branch | — | `feature/wave0-scaffold` off `main`; first commit of scaffold | `git status` clean on branch |

> Note 0.4 is the critical-path external. If building LGPL FFmpeg stalls, ship OSXExperts 8.1
> (GPL) as interim with license text + source offer, and swap to LGPL before release (Wave 6).

---

## Wave 1 — Port the format-agnostic scaffold (depends on W0; tasks parallelizable)

Mechanical copy + rename from `_reference/P2toMXF`. Rename app-support dir `"P2toMXF"`→`"DJIjoiner"`.

| # | Task | Source → Target | Changes | Backpressure |
|---|------|-----------------|---------|--------------|
| 1.1 | Port `Timecode` struct **byte-for-byte** | `Models/P2Clip.swift` → `Models/Timecode.swift` | none (keep rounded-fps `totalFrames`, `frameGap`) | unit test: `frameGap` continuity cases |
| 1.2 | Port core data models | `Models/{ConversionJob,ProgressModels,VerificationModels}.swift` | field renames only | builds |
| 1.3 | New DJI models | `Models/{DJIClip,DJIFolder,RecordGroup,ConversionSettings}.swift` | from `P2Clip`/`P2Card`; add `cameraModel`, `fileIndex`, `srtFile:URL?`, `lrfFile:URL?`; `OutputContainer{.mp4,.mov}` | builds |
| 1.4 | Port `BundledToolResolver` | `Services/BundledToolResolver.swift` | ffmpeg + **ffprobe** only; drop all BMX cases/`bmxEnvironment`/`bmxLibPath` | unit: resolves both tool URLs from bundle |
| 1.5 | Port `TempDirectoryManager`, `DiskSpace` | same names | rename defaults key | builds |
| 1.6 | Port `FFmpegWrapper` (process core) | `Services/FFmpegWrapper.swift` | remove `bmxWrapper`, `.bmxNotFound`; keep `runFFmpeg`, `OutputCollector`, progress regex, SIGTERM-single-process cancel | unit: parses a sample ffmpeg progress line |
| 1.7 | Port `QueueManager` (+Operations/Processing/Verification) | `Services/QueueManager*.swift` | rename app-support dir; keep JSON persistence, conflict auto-rename, `IOPMAssertion`, security-scoped bookmarks, disk preflight | unit: enqueue→persist→reload round-trips |
| 1.8 | Port `SpeedTracker` | `Services/SpeedTracker.swift` | rename dir | unit: ETA from seeded records |
| 1.9 | Port `VerificationService` | `Services/VerificationService.swift` | none (already ffprobe + decode-to-null + VideoToolbox) | builds; smoke-verify a known-good mp4 |
| 1.10 | Port `ThumbnailManager` + `FFmpegWrapper+Thumbnails` | same | extract directly from MP4 (drop proxy/icon fallback chain) | unit: extracts a frame from fixture mp4 |
| 1.11 | Port `Theme` | `Theme.swift` | none | builds |

---

## Wave 2 — DJI front-end engine (depends on W1)

The genuinely new work. **This is where 80% of the design risk lives.**

| # | Task | Target | Success criteria | Backpressure |
|---|------|--------|------------------|--------------|
| 2.1 | `DJIFilenameParser` | `Services/DJIFilenameParser.swift` | Parse legacy `DJI_NNNN` and `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>`; extract base id, index, timestamp, **variant suffix**; classify `.MP4`/`.SRT`/`.LRF` | unit: table of real filenames → parsed fields, incl. `_W/_Z/_T/_V/_D` |
| 2.2 | `DJIMetadataReader` | `Services/DJIMetadataReader.swift` | AVFoundation async (`load(.duration)` exact CMTime, `.creationDate`, nominal/min frame-rate, codec/res/audio via `CMFormatDescription`); ffprobe JSON fallback; read `tmcd` via AVAssetReader (expect 00:00:00:00) | unit: reads duration/fps/codec from fixture; flags VFR |
| 2.3 | `DJIFolderReader` (replaces P2CardParser) | `Services/DJIFolderReader.swift` | **Same interface**: `validateFolder(at:)->Bool`, `discoverFolders(in:)->[URL]`, `parseFolder(at:) throws -> DJIFolder`; scans DCIM/`100MEDIA` for `*.MP4`/`*.MOV`, pairs `.SRT`/`.LRF` | unit: parses a fixture folder → DJIFolder with clips+sidecars |
| 2.4 | Grouping rewrite | `ConversionViewModel+RecordGroups.swift` | Group by **variant suffix first** (never merge across), then filename order; continuity via SRT wall-clock / decoded-duration adjacency (NOT creation_time/tmcd); **stream-param equality gate**; block + report on discontinuity (`timecodeIssues` analogue) | unit: mixed-folder fixture → correct groups; variant clips never merged; gap → split |
| 2.5 | Simplify `FFmpegWrapper+Conversion` | `Services/FFmpegWrapper+Conversion.swift` | Drop BMX Phase-1; `mergeClips` writes concat list + runs `-f concat -safe 0 -i list -map 0:v -map 0:a? -map -0:d -c copy -fflags +genpts -movflags +faststart -metadata creation_time=… -timecode …` | unit: builds correct arg array + list.txt for a group |
| 2.6 | Pre-join param guard | in 2.5 path | ffprobe each segment; refuse `-c copy` if codec/res/fps/timebase/pix_fmt differ, with clear message | unit: mismatched fixtures → refusal |
| 2.7 | TS-remux fallback | `Services/FFmpegWrapper+Conversion.swift` | On `Non-monotonous DTS` failure, remux each to mpegts (`h264/hevc_mp4toannexb`) → concat protocol → `aac_adtstoasc` back to mp4 | integration: stubborn set joins via fallback |
| 2.8 | ✅ **DONE (2026-06-09)** Date + start-TC stamp on join | `Services/RecordingStartResolver.swift`, `QueueManager+Processing.swift` | Resolve one recording-start wall-clock (manual override → SRT first-cue → filename → sane `creation_time` → filesystem) → derive **both** `creation_time` (ISO-8601Z) and the `tmcd` start TC during the `-c copy` mux; toggle-gated + `dateOverride`. `mvhd`/`tkhd`/`mdhd` 1904-epoch writer (`QuickTimeAtomWriter`) stays the existing-file corrector; the size-changing Apple `Keys:com.apple.quicktime.creationdate` atom is deferred to **6.3**. | 16 unit + 2 real-ffmpeg integration; footage-validated on `DJI_001` (`0008+0009`) |

---

## Wave 3 — SRT telemetry stitcher (depends on 2.2, 2.5) — **the differentiator**

| # | Task | Target | Success criteria | Backpressure |
|---|------|--------|------------------|--------------|
| 3.1 | Tolerant SRT parser | `Services/SRTParser.swift` | Parse 3 variants: modern bracketed `[k: v]`, `FrameCnt/DiffTime`+wall-clock, legacy `<font>`/`GPS()`/`HOME()`; tolerate UTF-8/BOM/CRLF; preserve payload verbatim | unit: each variant fixture → cues with start/end ms + raw payload + wall-clock |
| 3.2 | Offset stitcher | `Services/SRTStitcher.swift` | Cumulative offset = Σ ffprobe `format=duration` of preceding segments (NOT cue math); renumber indices globally; missing-SRT segment still advances offset | unit: 3-segment fixture → continuous, correctly-timed, sequential SRT |
| 3.3 | Wire SRT into join pipeline | `FFmpegWrapper+Conversion` / QueueManager | After video join, emit `<output>.SRT` alongside; exclude `.LRF` from concat | integration: joined group yields aligned `.SRT`; LRF ignored |

---

## Wave 4 — GUI (depends on W1 ViewModel + W2 engine)

| # | Task | Target | Success criteria | Backpressure |
|---|------|--------|------------------|--------------|
| 4.1 | App entry + ViewModel port | `DJIjoinerApp.swift`, `ConversionViewModel*.swift` | `@MainActor` VM ported; File menu (Open Folder), watch-folder menu stub; security-scope tracking | builds & launches |
| 4.2 | `ContentView` 3-pane | `ContentView.swift` | Folders │ Clips/Groups │ Queue + console drawer; `.fileImporter` + drag-drop feed `DJIFolderReader` | manual: drop a folder → groups appear |
| 4.3 | Port generic views | `Views/{Console,Estimate,Footer,ProgressControlPanel,QueueList,JobRow}.swift` | relabel P2 wording | builds |
| 4.4 | Group/clip views + continuity report | `Views/{GroupListView,ClipRowView,HeaderView}.swift` | show per-boundary gap report, TC/creation-date diff, **confirm-before-fix** (default TC authoritative); preserve thumbnail/status subview split (perf) | manual: discontinuity shown; fix confirm works |

---

## Wave 5 — Watch-folder automation (depends on W2 engine + W1 queue)

| # | Task | Target | Success criteria | Backpressure |
|---|------|--------|------------------|--------------|
| 5.1 | `WatchFolder` monitor | `Services/WatchFolder.swift` | FSEvents recursive (DCIM trees, `kFSEventStreamCreateFlagFileEvents`, dispatch-queue, Unmanaged context); DispatchSource (`O_EVTONLY`) option for flat folder | unit/manual: file drop fires callback |
| 5.2 | Stability/debounce gate | in 5.1 | size+mtime unchanged for N polls (~3×0.75s) before "settled"; ignore partial copies | manual: large copy not processed until complete |
| 5.3 | Complete-set + state machine | `Services/WatchFolder.swift` + VM | quiet-window (30–60s) after last settled member; per-group state `Discovered→Settling→Grouped→Ready→Joining→Verifying→Done/Failed`, **persisted**; relaunch resumes; bounded concurrency 1–2 | manual: staged drop auto-joins once complete; relaunch resumes |

---

## Wave 6 — Packaging, notarization, real-footage validation (final)

| # | Task | Target | Success criteria | Backpressure |
|---|------|--------|------------------|--------------|
| 6.1 | ✅ **DONE (2026-06-09)** Verify LGPL FFmpeg (swap if interim GPL) | Resources/Helpers | LGPL static confirmed — built from source via `build-ffmpeg-lgpl.sh`, `ffmpeg -L` = LGPL, no `--enable-gpl`/`--enable-nonfree`, no homebrew/x264/x265 links | `ffmpeg -L` license check |
| 6.2 | ✅ **DONE (2026-06-10)** Signing inside-out + notarize | `sign-bundled-binaries.sh`, `scripts/notarize.sh` | helpers → app signed (Developer ID, hardened runtime + timestamp); `notarytool submit --wait` **Accepted**; `stapler staple` worked; `spctl -a -vvv` = `Notarized Developer ID`. One-command `notarize.sh`; API-key keychain profile `conjoyn-notary` | gatekeeper accepts ✅ |
| 6.3 | End-to-end real-footage test | — | Legacy + timestamped sets join losslessly; output verified (ffprobe + decode-to-null); A/V sync at every seam; metadata correct in Finder + QuickTime Inspector | all green on real footage |
| 6.4 | SRT alignment validation | — | Stitched `.SRT` cues align with joined video across all seams; telemetry continuous; multi-segment drift < 1 cue | manual review in player |
| 6.5 | Variant-guard + edge cases | — | `_W/_Z/_T` never merged; missing-middle splits; mixed-codec refused; trailing tiny segment included; VFR fallback | matrix of fixtures passes |

---

## Risk register
- **SRT stitch (W3)** — highest uncertainty; prior art sparse (only Crear12 does offset
  correction). Mitigate: build the tolerant parser + offset math test-first against real SRTs.
- **FFmpeg LGPL build (0.4)** — external/toolchain risk on the critical path. Mitigate: GPL
  interim, swap before release.
- **Grouping correctness (2.4)** — DJI metadata is messy; depends on real fixtures. Mitigate:
  get test footage early; tolerances are defaults to tune, not constants.
- **Native atom writer (2.8)** — 1904-epoch correctness is fiddly. Mitigate: round-trip unit test.

## Sequencing notes
- W1 tasks fan out in parallel (independent ports). W2 is the serial spine. W3/W4/W5 can
  proceed in parallel once W2's engine + ViewModel exist. W6 is the gate.
- Recommend a thin **vertical slice first**: 0.1–0.4 → 1.1/1.4/1.6 → 2.1/2.2/2.3/2.5 → join a
  real 2-segment set from CLI/test before building GUI/watch-folder. Validates the core lossless
  join end-to-end at minimum cost, derisking everything downstream.

---
*Next: `/execute` to run Wave 0, or start the vertical slice. Update PROJECT_STATE.md as waves land.*
