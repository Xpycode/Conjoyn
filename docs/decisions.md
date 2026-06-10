# Decisions Log

This file tracks the WHY behind technical and design decisions for DJIjoiner.

---

### 2026-06-10 - Help window: defer (but adopt the reusable `AppHelp` package when built); no Settings scene
**Context:** User asked whether a **Help menu/window** and a **Settings window** had ever been
scoped for Conjoyn. Audit found **neither was ever discussed** — no session log, decision, spec, or
`ideas.md` entry. Current `ConjoynApp.swift` is a bare `WindowGroup`: **no `Settings` scene, no
`.commands { }`, no Help wiring**, so the app ships only the stock macOS menu bar (default
About/Quit + an empty Help search field; ⌘, is a no-op). User maintains a separate standalone Swift
package at `/1-macOS/AppHelp/` — a drop-in `HelpMenu` library (sidebar + markdown-detail
`HelpWindowController`/`HelpWindowView`, `HelpTopic`/`HelpContent` models, swift-markdown-ui
rendering, **both** `SwiftUIHelpCommands` and `AppKitHelpMenu` integration shims).
**Decision:** (1) **No Settings scene** — Conjoyn has no persistent cross-launch preference to house.
Every tunable is already in-context (output-bar switches + the gear popover for engine knobs; rename
& date-override are deliberately session-only on the ViewModel, kept off the `Codable`
`ConversionSettings`). A Settings window would be hollow today. Revisit only if a persisted default
(output folder, default container) or **watch-folder config** (still unbuilt) lands. (2) **Help —
deferred backlog item, not now.** When done, vendor the existing `AppHelp` package rather than
hand-rolling (it's turnkey; `33_app-minimums.md` lists a Help menu as a baseline for notarized
direct-distribution apps). The real cost is *content*, not wiring: topics for continuity-grouping,
the camera-variant guard, the date/timecode model, SRT stitching, watch-folder.
**Why:** Don't add empty chrome. Settings scenes exist to persist app-global prefs; Conjoyn has
none, and forcing one now contradicts the deliberate "rename/override state is per-run" decision.
Help is genuinely valuable but lower-priority than the owed items (single-file export, DMG, UI-state
eyeballing), and the heavy lifting is writing topic content — so park it with the component already
identified.

---

### 2026-06-10 - Reframe "Preserve timecode" as "Timecode from recording time" + surface it per job
**Context:** The 2026-06-10 design handoff bar still labeled the TC toggle **"Preserve timecode."**
That's misleading: DJI's source `tmcd` is almost always `00:00:00:00`, and the engine has (since the
2026-06-09 "date+timecode stamp model" decision) **derived** the output start TC from a resolved
recording-start wall-clock — it preserves nothing. User flagged the wording and asked to (a) call it
"TC from creation time" and (b) make the source-vs-applied difference visible, with a slow-mo
explanation.
**Decision:** Relabel the toggle **"Timecode from recording time"** (behavior unchanged; internal
`preserveTimecode` symbol kept). Surface the transformation **per job in the queue row** (user's
pick over a toggle popover or always-inline caption): **Source TC** (`00:00:00:00`, inert) vs
**Applied TC** (`HH:MM:SS:FF`) with an **origin tag** (from SRT cue / filename / file date / manual)
and the frame rate, **behind a disclosure caret on the row** (row stays single-line; caret expands
an inline panel — keeps the queue compact, detail on demand). When a group has a slow-mo clip, add a one-line note: TC **starts** at the real
recording instant and **advances at the file's playback fps** — the start is unaffected by slow-mo;
only the frame-rate tag follows the container. **No engine/export change** — expose values the
resolver already computes. See `specs/rename-and-tc-disclosure.md`.
**Why:** Honesty over magic. "Preserve" implied a fidelity we don't (and can't) provide; showing
source→applied with provenance lets the user trust and, if needed, override the stamp.

---

### 2026-06-10 - Rename Joined Files: counter restarts per batch; collisions auto-suffix
**Context:** The rename-popover handoff (`02_Design/design_handoff_rename_popover/`) left two product
questions open: (1) does the `{###}` counter restart or continue across Add-to-Queue batches, and (2)
what happens when two outputs resolve to the same name.
**Decision:** (1) The counter **restarts at "Start at" for each batch** (simple, predictable; matches
the handoff default). (2) Name collisions — within a batch, against the existing queue, or against a
file already in the destination — **auto-suffix** `_2`, `_3`, … until unique (never lose a file;
stays close to the pattern); the `.SRT` sidecar follows the suffixed stem. The output name is decided
**once at Add-to-Queue** and frozen onto the job. Rename bypasses the default namer, so it also
side-steps the doubled camera-variant-suffix bug (tracked separately). See
`specs/rename-and-tc-disclosure.md`.
**Why:** Per-batch restart keeps numbers meaningful per ingest action; auto-suffix favors
no-data-loss over strict pattern purity, consistent with the app's "never destroy footage" posture.

---

### 2026-06-09 - Free-space preflight must not trust `volumeAvailableCapacityForImportantUsageKey` off the boot volume
**Context:** Driving the full GUI pipeline on the real card, every join to the external `2CULL` drive
failed the pre-join disk-space preflight with **"Zero KB free"** — despite 822 GB actually free
(`df`). `DiskSpace.availableCapacity` queried `volumeAvailableCapacityForImportantUsageKey` first and
only fell back to the legacy `volumeAvailableCapacityKey` when the former was **nil**. That key is an
Apple **boot-volume** convenience (it accounts for purgeable space): on external/secondary APFS
volumes it returns **`0`, not `nil`**, so the code accepted `0` as the answer. Confirmed with a Swift
probe — on `2CULL`: importantUsage `= 0`, legacy `= 882 GB`; on the boot volume: importantUsage
`59.8 GB` > legacy `45 GB`. **Impact:** the app could not join to *any* SD card / external SSD — the
overwhelmingly common real-world destination — even though it's where DJI footage lives. Engine-level
tests never caught it because they write to temp dirs on the boot volume.
**Decision:** Keep `importantUsage` as the preferred signal (it's the more accurate "what you can
actually write" figure *on the boot volume*), but treat a **non-positive** value as a miss and fall
back to the legacy raw capacity. Extracted a pure `DiskSpace.usableCapacity(importantUsage:legacy:)`
for that selection so it's unit-tested directly (incl. the exact `0 → 882 GB` external-volume case).
**Lesson:** validate I/O-bound features against the *real* destination medium (external/removable),
not just boot-volume temp dirs. (Fix: `fix/diskspace-external-volume` → `main`, +4 tests.)

---

### 2026-06-09 - Resolved-wall-clock is authoritative for the date+TC stamp; manual override (supersedes "TC authoritative")
**Context:** Two earlier decisions quietly conflict. *"Timecode is authoritative for the metadata
fix"* (2026-06-07) said treat the source start-timecode as ground truth and rewrite the date to
match. But the later research-revised grouping decision (same day) established that DJI's embedded
`tmcd` start timecode is **almost always `00:00:00:00`** and its `creation_time` is **frequently
wrong** (the QuickTime 1904/1951-epoch bug + timezone shifts). So "trust the source TC" has, in
practice, nothing real to trust — there is usually no meaningful source timecode to be authoritative
about. This blocked wiring task 2.8 (`JoinMetadata` stamping), which currently stamps nothing.
**Decision:** Invert the model. The authoritative value is a **resolved recording-start wall-clock**,
derived from a source-priority chain; **both** the date atoms **and** the output `tmcd` start-timecode
track are *derived from that one resolved value*, never read from the (empty) source `tmcd`. Plus a
**manual override** so the user can set the date/time when every automatic signal is missing or wrong.
Resolution order (best DJI signal first):
1. **SRT telemetry first-cue wall-clock** — DJI writes a real timestamp into the `.SRT`; most reliable.
2. **Filename-embedded datetime** — the new scheme `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>` carries it.
3. **Embedded `creation_time`** — corroborating only; used when sane (reject the 1904/1951 epoch + TZ outliers).
4. **Filesystem `creationDate`** — reliable only on a fresh SD-card read (resets on Finder copies).
5. **Manual override** — always available; wins when set. Surfaces as the resolved value otherwise.
Source `tmcd` is honored **only if non-zero** (rare). The resolved wall-clock + frame rate produces
the `-timecode HH:MM:SS:FF` argument; the same date produces ISO-8601 `creation_time` +
`com.apple.quicktime.creationdate`; the native atom writer then patches the header atoms post-mux.
**Rationale:** Uses the signals DJI actually writes correctly, matches the brand-agnostic roadmap
(SRT/filename generalize; a zeroed `tmcd` does not), and keeps one source of truth so the date the
user sees, the date in Finder/Photos, and the start of the TC track can never disagree. Manual entry
covers the genuine "no usable signal" tail without the app guessing.
**Port source — Penumbra (`~/ProgrammingProjects/1-macOS/Penumbra`), proven & shipped:**
- `Utils/DateCorrectionResolver.swift` — the source-priority `Resolution{date, provenance, mismatchDetected}`
  pattern (Penumbra's chain is filename→filesystem; we extend the front with SRT + sane-`creation_time`).
- `Utils/TimecodeFormatter.swift` — `wallClockTimecode(for:frameRate:isDropFrame:)` derives the
  `-timecode` string from a Date; `ISO8601Z.format` for the `creation_time`/`creationdate` values.
- `Utils/SourceTimecodeReader.swift` — TN2310 `tmcd` reader (to detect a non-zero source TC).
- Manual override: Penumbra's per-item `dateOverride: Date?` with `effectiveDate = dateOverride ?? resolvedDate.date`
  (`Models/ExportDialogModel.swift`) + the "Override…" popover (`Views/ExportDialogView.swift`).
- `ExportManager.swift` — the assembly + **critical FFmpeg gotcha**: when emitting `-timecode` you
  MUST drop the source data/`tmcd` track (our join already does `-map -0:d`), else `-c copy` passes
  the old `tmcd` through and FFmpeg silently ignores `-timecode`.
**Consequences:**
- Task 2.8 wiring is now specified: populate `JoinMetadata.timecode` + `.creationTime` from the
  resolver, not from segment-1 `tmcd`. Keep the param guard + `-c copy` lossless path untouched.
- New unit-testable piece: a `DateCorrectionResolver` adapted for DJI (SRT-first), + a "mismatch
  detected" surfacing when sources disagree beyond a threshold (port Penumbra's comparator).
- UI gains a per-group resolved date/TC readout with provenance + an override control (Wave 6).
- Reframes, does not delete, the 2026-06-07 "TC authoritative" entry — "authoritative" now means the
  *resolved wall-clock*, with the TC track derived from it rather than dictating it.

**Implemented 2026-06-09 (s7).** `Services/RecordingStartResolver.swift` (chain: manual override →
SRT first-cue → filename → sane embedded `creation_time` → filesystem, with a 2010-floor/now+1d
sanity gate and a timezone-safe SRT↔filename mismatch flag) + `QueueManager.resolveJoinMetadata`
deriving both `creation_time` (ISO-8601Z) and the `tmcd` start TC (`HH:MM:SS:FF`) from the one `Date`,
gated by `fixCreationDate`/`preserveTimecode` + the new `ConversionSettings.dateOverride`.
`TimecodeFormatter.wallClockTimecode`/`ISO8601Z` ported from Penumbra. Two pragmatic extensions to the
spec: the mismatch comparator is **wall-clock-only** (the absolute embedded/filesystem dates are
excluded so a legitimate UTC offset can't masquerade as a mismatch), and zone-free signals are
interpreted in `Calendar.current` (correct when the editing machine shares the capture zone — the
unambiguous, TZ-carrying Apple `Keys` `creationdate` atom that removes that assumption stays Wave-6 /
task 6.3). **Validated on real footage** (card `DJI_001`, split `0008+0009`): stamped
`creation_time=2026-05-21T17:53:03Z` + `timecode 19:53:03:11` from the SRT first cue at 25 fps, with
DJI's `djmd`/`dbgi` data + `mjpeg` preview tracks dropped and a fresh `tmcd` written (`-map -0:d`
gotcha confirmed handled). UI readout/override control remain Wave 6.

### 2026-06-09 - Chose "Conjoyn" as the product name (rebrand off "DJIjoiner")
**Context:** "DJIjoiner" is a placeholder with two problems: (a) shipping a notarized, directly-
distributed app with "DJI" in the name is a trademark risk independent of the roadmap, and (b) the
join engine is brand-agnostic and the product will add GoPro / DJI Osmo / multi-brand support —
the "DJI" name locks in the one brand we've proven we'll outgrow. Rebrand cost only rises per
release (bundle id, signing, docs), so do it pre-1.0.
**Options Considered (camera-agnostic, coined/evocative; vetted by web/App-Store/domain search):**
1. **Conjoyn** (coined: conjoin+join) — zero collisions found; trademark-strong (coined); clear
   meaning; con of needing to be spelled aloud.
2. Unsplit — crystal-clear to users, `.app` likely free, but *descriptive* → weak/​hard to defend.
3. Reelm (reel+realm) — evocative, brand-clean, but `reelm.app` likely already registered.
4. Seamr — diluted: active "Seamr Labs" data co + taken `seamr.com`/GitHub handle.
   Killed in vetting: Weldr (weldr.dev), Onecut (App Store video apps), Splyce (≈Splice/esports),
   Mendr (photo app), Continua (≈Continuum/Boris FX + Continua Group), Spool (Mac App Store app).
**Decision:** **Conjoyn.** Bundle id `com.lucesumbrarum.conjoyn`. Working tagline: "Split
recordings, made whole."
**Rationale:** Coined → most ownable/trademarkable of the set; transparent "join" meaning; truly
brand-agnostic (fits multi-camera future); no software/App-Store/domain collisions surfaced.
**Consequences:** Rebrand is a deliberate step touching app name, bundle id, signing, scheme,
icon, copy. The Xcode project is **confirmed xcodegen-driven** (`01_Project/project.yml` is the
source of truth, `.xcodeproj` gitignored, sources are directory globs), so the rename is mostly
edit-`project.yml`-then-`xcodegen generate`, not hand-patching the pbxproj.
**EXECUTED 2026-06-09.** Renamed project/targets/module/bundle to `Conjoyn`; source folders
`git mv`'d to `01_Project/Conjoyn` + `ConjoynTests`; 19 test imports, `ConjoynApp`, entitlements,
runtime storage paths, and build scripts updated; `Conjoyn.xcodeproj` regenerated. **Visible brand
is lowercase `conjoyn`** (`CFBundleDisplayName`); binary/module/.app stay PascalCase `Conjoyn` so
`TEST_HOST` + `import Conjoyn` resolve cleanly (a lowercase `PRODUCT_NAME` broke the test host).
**The repo root folder + git were intentionally left `DJIjoiner`** — renaming them would break the
working directory, derived data, and `~/.claude` memory paths for little gain; revisit only if the
project moves. Clean build + full suite green (195/195).
**Clearance — sufficient for a free app, DONE.** USPTO exact-match search returned **no results** for
"Conjoyn" (2026-06-09); web + Mac App Store + the user's own Kagi/Google passes were also clean. For a
free, non-commercial app the realistic exposure is a rename-demand, not damages, so a coined name that
no software product already uses is adequate clearance — no paid search, EUIPO filing, or self-
registration needed. (The famous-mark dilution risk that *did* matter — "DJI" — is exactly what this
rename removes.)

---

### 2026-06-09 - Swapped interim GPL FFmpeg for a from-source static LGPL build (task 6.1)
**Context:** The bundled helpers were OSXExperts 8.1 — a full `--enable-gpl` build (x264/x265/…),
a release blocker (GPL source-distribution burden, MAS-incompatible). A copy-only joiner needs
none of the GPL encoders.
**Decision:** Build `ffmpeg` + `ffprobe` from unmodified FFmpeg 8.1 source via
`01_Project/scripts/build-ffmpeg-lgpl.sh`: `--enable-static --disable-shared`, **no**
`--enable-gpl`/`--enable-nonfree`, `--disable-network --disable-autodetect` (hermetic — won't link
stray Homebrew GPL libs). License defaults to LGPL v2.1+. Kept the full built-in codec/demuxer/
muxer set (no `--disable-everything`) so no DJI container quirk can break a join.
**Rationale:** LGPL = lighter legal burden, smaller app (20 MB vs 52 MB each), self-contained
(only system frameworks linked). Reproducible recipe in-repo, as decisions.md (2026-06-07) required.
**Validation:** `ffmpeg -L` reports LGPL; `otool -L` shows only `/usr/lib` + `/System` frameworks;
real-footage test (card `DJI_001`) — ffprobe JSON read OK, concat `-c copy` join exact-lossless
(426.44 s = 112.28 + 314.16), mjpeg preview dropped, creation_time + timecode stamped.
**Consequences:** `fetch-ffmpeg.sh` (GPL prebuilt) demoted to a dev-only fast-path fallback; the
release path is the LGPL build script. Build needs Xcode CLT only (no nasm on arm64).

---

## Template

### [Date] - [Decision Title]
**Context:** [What situation prompted this decision?]
**Options Considered:**
1. [Option A] - [pros/cons]
2. [Option B] - [pros/cons]

**Decision:** [What we chose]
**Rationale:** [Why we chose it]
**Consequences:** [What this means going forward]

---

## Decisions

### 2026-06-07 - Group segments by metadata continuity, not filenames
**Context:** DJI splits recordings at the FAT32/exFAT 4 GB boundary (~16.8 GB on newer
models). Filenames reset to `DJI_0001` on in-drone format and collide across drones.
**Options Considered:**
1. Filename sequence (`DJI_0001→0002`) — simple but unreliable; resets/collides.
2. Embedded-metadata chaining (`creation_time` + duration adjacency, stream-param match) —
   robust, separates independent recordings, matches Telestream/P2 timecode-first practice.
**Decision:** Metadata-continuity chaining is primary; filename order is a corroborating
secondary signal and tie-breaker only.
**Rationale:** Splits are written back-to-back, so `creation_time[N]+duration[N] ≈
creation_time[N+1]` is a true continuity test; filenames are not.
**Consequences:** Need a reliable AVFoundation/ffprobe metadata reader; must handle DJI's
wrong/zeroed timecode and timezone/epoch bugs defensively.

### 2026-06-07 - FFmpeg concat demuxer with `-c copy` as the join engine
**Context:** Need lossless, fast joining of already-muxed MP4 segments.
**Options Considered:**
1. concat *protocol* — doesn't work for MP4/MOV (MPEG-TS only).
2. concat *filter* — re-encodes (lossy, slow).
3. concat *demuxer* `-c copy` — lossless stream copy, I/O-bound, handles thousands of files.
**Decision:** concat demuxer with `-c copy -fflags +genpts -movflags +faststart`.
**Rationale:** Same-recording DJI splits share identical codec/params (the demuxer
precondition); stream copy is bit-identical and fast. No BMX stage needed (unlike P2/MXF).
**Consequences:** Must re-apply `tmcd`/creation_time on output (concat doesn't preserve
them); refuse joins across mismatched codec/res/fps; handle benign "Non-monotonous DTS".

### 2026-06-07 - Timecode is authoritative for the metadata fix
**Context:** DJI `tmcd` start TC and `mvhd`/creationdate calendar timestamp often disagree.
**Decision:** Treat start timecode as ground truth; rewrite creation-date atoms to match,
not the reverse. Surface the discrepancy in the UI; user confirms (default = TC).
**Rationale:** Broadcast convention; camera clock is the more likely-wrong source.
**Consequences:** Need exiftool/atom write-back to keep all QuickTime date atoms consistent.

### 2026-06-07 - Port architecture from P2toMXF, drop the BMX stage
**Context:** User's own app P2toMXF (Swift 6/SwiftUI, MIT, github.com/Xpycode/P2toMXF)
already implements the subprocess/queue/verify/ETA scaffold and a timecode-continuity grouper.
**Decision:** Clone & port `FFmpegWrapper`, `QueueManager`, `SpeedTracker`,
`VerificationService`, `BundledToolResolver`, `TempDirectoryManager`, `Timecode`,
`ConversionViewModel`+RecordGroups, signing script. Drop `BMXWrapper`, `P2CardParser`,
and bundled `bmxtranswrap`/`mxf2raw` + dylibs. Clone lives at `_reference/P2toMXF/`.
**Rationale:** DJI MP4s are self-contained, so the P2 stage-1 rewrap is unnecessary; the
reusable core is P2toMXF's stage-2 concat engine + grouping brain. Fastest credible path.
**Consequences:** Replace P2CardParser CLIP-XML with ffprobe/AVFoundation DJI reader;
replace `discoverP2Cards` with `discoverDJIMedia` over DCIM folders.

### 2026-06-07 - Direct distribution + notarization (not Mac App Store)
**Context:** FFmpeg is GPL; bundling it makes MAS distribution legally fraught.
**Decision:** Developer ID signing + notarization, App Sandbox **disabled**, Hardened
Runtime **enabled** (with library-validation/JIT entitlements for subprocess exec).
**Rationale:** Matches P2toMXF's proven, shipped configuration; avoids GPL/MAS conflict;
sandbox-disable is required to exec bundled FFmpeg.
**Consequences:** MAS out of scope; need the dylib-path-fix + re-sign packaging dance.

### 2026-06-07 - [research-revised] Grouping key is filename+SRT-wallclock, NOT creation_time
**Context:** Research verified DJI MP4 `creation_time` is frequently wrong (QuickTime 1904
epoch bug → files read as 1951; plus timezone shifts), and the embedded `tmcd` start timecode
is almost always `00:00:00:00`. The original "chain by `creation_time + duration`" plan rested
on metadata DJI doesn't write reliably.
**Decision:** Layered ordering key — (1) filename scheme + index (`DJI_NNNN`, or
`DJI_YYYYMMDDHHMMSS_NNNN_<suffix>`), (2) SRT embedded wall-clock continuity, (3) decoded
segment-duration adjacency. `creation_time`/`tmcd` are corroborating-only. Stream-param
equality (codec/res/fps/timebase/color) is a hard gate. **Never** merge across camera-variant
suffixes (`_W`/`_Z`/`_T`/`_V`/`_D`). Exclude `.LRF` proxies from the concat set.
**Rationale:** Use the signals DJI actually writes correctly; refuse joins that would corrupt.
**Consequences:** DJIFilenameParser + variant guard are first-class; the ported `Timecode`
continuity tier feeds on decoded duration/wall-clock, not tmcd frame math.
**Sources:** SANS ISC DJI metadata; exiftool QuickTime-epoch patch; Pertsev "DJI 1951 bug";
MavicPilots suffix threads; Crear12/Merge_DJI_Video_SRT.

### 2026-06-07 - [research-revised] Native atom writer for the date fix, NOT bundled exiftool
**Context:** exiftool is Perl — bundling means tens of MB, an extra nested binary to
codesign+notarize, and an extra license. The fix only needs a handful of QuickTime atoms.
**Decision:** FFmpeg sets `-metadata creation_time=…` + `-timecode` during the join; a small
(~150-line) native Swift atom writer then patches `mvhd`/`tkhd`/`mdhd` create+modify (1904
epoch) and `Keys:com.apple.quicktime.creationdate` so Finder/Photos AND QuickTime Player's
Movie Inspector agree. No exiftool bundled.
**Rationale:** Lightest path; no Perl runtime, no extra notarized binary, no extra license.
**Consequences:** Must implement + unit-test the 1904-epoch atom patcher; read the
authoritative date/timecode from segment 1 via ffprobe.

### 2026-06-07 - [research-revised] Bundle a static arm64 LGPL FFmpeg + ffprobe
**Context:** GPL FFmpeg (e.g. OSXExperts `--enable-gpl`) imposes full-source-distribution
obligations and is MAS-incompatible. A copy-only joiner needs no GPL encoders (x264/x265).
**Decision:** Bundle a **static arm64** build of `ffmpeg` + `ffprobe`, built **LGPL**
(`--enable-static --disable-shared`, omit `--enable-gpl`/`--enable-nonfree`, only the
demuxers/muxers/bitstream-filters we use). Static = single Mach-O each, no `install_name_tool`
dylib dance. If a GPL prebuilt is used as a stopgap, ship GPL text + same-server source offer.
**Rationale:** Lighter legal burden, simpler bundling/signing, smaller app.
**Consequences:** Need a reproducible FFmpeg build recipe (or vet OSXExperts 8.1 as interim);
sign both helpers inside-out before the app; notarytool + stapler.

### 2026-06-07 - [research-revised] SRT stitch offsets come from decoded duration, not cue math
**Context:** DJI per-segment `.SRT` cue timestamps RESTART at 00:00:00 each segment; cue
cadence (~33 ms at 30 fps) accumulates rounding drift, and the last cue ends before the true
video end. Verified prior art (Crear12) recalculates timestamps.
**Decision:** Stitch in-app: add a cumulative offset = Σ ffprobe `format=duration` of preceding
segments to each cue, renumber indices globally, advance the offset even when a segment's SRT
is missing. Prefer the SRT embedded wall-clock line for ordering/validation. Parse defensively
(modern bracketed, FrameCnt+wallclock, legacy `<font>`/`GPS()` variants).
**Rationale:** Decoded duration is the only drift-free offset; cue arithmetic drifts.
**Consequences:** SRTStitcher needs a tolerant multi-format parser + duration from ffprobe,
not from the SRT itself. This is the app's key differentiator (prior art is sparse).

### 2026-06-07 - v1 scope = full app incl. watch-folder AND SRT stitching
**Context:** Interview offered a staged MVP; user chose the comprehensive first release.
**Decision:** v1 = engine + GUI + watch-folder automation + `.SRT` telemetry stitching
(with cumulative per-segment time-offset correction).
**Rationale:** User's explicit choice; SRT stitching is the community differentiator.
**Consequences:** **Scope-creep risk flagged.** SRT offset-correction is the
highest-uncertainty piece (brief calls it "a known unsolved pain point"); planning must
still stage internally (engine → GUI → watch-folder → SRT) even though all ship in v1.

### 2026-06-07 - Define the DJIClip model layer now (ahead of footage), to unblock the queue ports
**Context:** Wave 1's queue ports (SpeedTracker, QueueManager via ConversionJob) reference the
clip/settings model layer. The plan deferred `DJIClip`/`ConversionSettings`/`ConversionJob`
(1.2/1.3) until Wave 2's grouping (2.4) and folder reader (2.3) "locked the shape" — but those
are blocked on real DJI footage, which isn't in hand. So the queue can't be ported without the
model layer.
**Decision:** Design `DJIClip` / `ConversionSettings` / `ConversionJob` **now from the spec +
CLAUDE.md guidance** (`srtFile:URL?`, `lrfFile:URL?`, `fileIndex`, `timestamp?`, `variantSuffix?`,
`cameraModel?`, exact `CMTime` duration, codec/res/fps/audio stream params, `creationDate?`;
`OutputContainer {.mp4, .mov}`). The footage gates *grouping/validation logic*, not the data
shape, which the spec already determines.
**Rationale:** Keeps the queue ports moving; the shape is spec-derived and stable enough.
**Consequences:** Accept some churn risk when 2.3/2.4 land on real footage. Port order:
1.2/1.3 models → 1.8 SpeedTracker → 1.9 VerificationService → 1.10 ThumbnailManager → 1.7
QueueManager (processing/verification orchestration adapts to drive the ported `mergeClips`,
not BMX). 1.5 (TempDirectoryManager + DiskSpace) already ported.

### 2026-06-08 - DJIClip duration: Int64 value + Int32 timescale backing → computed CMTime
**Context:** The spec wants frame-exact segment durations (continuity math + SRT offsets depend
on them), but `CMTime` isn't `Codable`/`Sendable` and the queue must persist `[DJIClip]` to JSON.
P2toMXF sidestepped this by storing durations as `String` frame counts — lossy and stringly-typed.
**Options Considered:**
1. Store `Double` seconds — loses exactness on NTSC fractions (30000/1001 ≈ 29.97).
2. Store a `CMTime` with a custom Codable shim — works but scatters CoreMedia at the boundary.
3. Store `durationValue: Int64` + `durationTimescale: Int32` backing, expose computed `CMTime`.
**Decision:** Option 3. The clip stores the two integers; `var duration: CMTime` rebuilds the
exact value only at the boundary. Mirrors the existing URL→String storage idiom.
**Rationale:** Trivially `Codable`/`Sendable`, frame-exact (a round-trip test asserts 30000/1001
survives byte-for-byte), and keeps CoreMedia out of the persisted representation.
**Consequences:** Callers read `clip.duration`/`durationInSeconds`, never the backing fields.
The metadata reader (2.2) must supply a real `CMTime` (AVAsset duration or ffprobe rational).

### 2026-06-08 - Embed StreamParameterGuard.SegmentStreamInfo on DJIClip (one source of truth)
**Context:** Both the join's pre-flight param guard (2.6) and the grouping engine (2.4) need each
segment's codec/res/pix_fmt/fps/timebase/audio. Duplicating those fields on `DJIClip` would risk
the two paths disagreeing.
**Decision:** Make `StreamParameterGuard.{Video,Audio}StreamParams`/`SegmentStreamInfo`
`Hashable, Codable, Sendable` (additive change) and embed `SegmentStreamInfo?` directly on
`DJIClip` — no duplicated stream fields.
**Rationale:** Single source of truth: grouping and the join guard read identical data; the param
gate's own structs become the persisted record. `Hashable` keeps `DJIClip` `Hashable` for SwiftUI.
**Consequences:** `StreamParameterGuard` (a Wave 2 service) now carries conformances a model depends
on; that coupling is intentional. `streamInfo` is optional (nil until a segment is probed).

### 2026-06-08 - Lean ConversionSettings; one ConversionJob = one record group
**Context:** Porting P2toMXF's `ConversionSettings`/`ConversionJob` verbatim would import P2-isms
(`processingMode`, `audioMapping`, `generateReport`, `includeChecksum`) and a whole-card job model.
DJIjoiner has no shipped `queue.json`, so backward compatibility doesn't constrain the shape.
**Decision:** Keep `ConversionSettings` **lean** — only `outputDirectory`, `outputFilename`,
`useFolderNameAsFilename`, `outputContainer{.mp4,.mov}`, `preserveTimecode`, `fixCreationDate`,
`stitchSRT`, `reEncodeOnMismatch=false`, `deleteOriginalsAfterVerify=false`. Make **one
`ConversionJob` = one `RecordGroup`** (not a whole folder), and rename P2 fields freely
(`cardName→folderName`, `cardPath→sourceFolderURL`, `cardBookmark→sourceBookmark`).
**Rationale:** One job = one group matches the concat join (one group → one output) and the
watch-folder "join when the group is complete" state machine. Lean settings = add knobs as features
land, not speculatively. Free renames remove P2 vocabulary before the 1.7 QueueManager port.
**Consequences:** UI/ViewModel build jobs per group, not per card. New knobs (re-encode UI, SRT
toggle wiring) get added to `ConversionSettings` as their features land.

### 2026-06-09 - SRT stitching is non-fatal to the join (task 3.3)
**Context:** Task 3.3 wires the per-segment `.SRT` stitch into `processConcatenateJob`, *after* the
lossless concat `-c copy` join has already produced the output video. The brief flags SRT
offset-correction as the **highest-uncertainty v1 item** ("known unsolved pain point"); ffprobe
duration probes or sidecar parsing can fail on odd real-world files.
**Decision:** Treat the `.SRT` stitch as a **best-effort sidecar step that never fails the job.** Any
error (ffprobe failure, unreadable sidecar, write error) is logged and swallowed; the job still
completes on the strength of the verified video join. Run the stitch **off the main actor**
(`Task.detached`) because `stitchSRT` probes each segment's duration synchronously, and emit nothing
when no segment carries a sidecar. The stitched `.SRT` is written next to the output
(`<output-stem>.SRT`) but is **not** added to `actualOutputURLs` (verification targets the video).
**Rationale:** The user's footage is irreplaceable; a flawless lossless join must not be discarded
because telemetry — a secondary convenience track — hit a snag. Decoupling the two also lets SRT
robustness improve against real footage (Wave 6) without risking the core join.
**Consequences:** A telemetry failure surfaces only in the log, not as a job failure — Wave 6 footage
calibration should add a visible per-job "SRT: written / skipped (reason)" indicator so silent
skips are noticeable. Seam-aware SRT/video alignment checks remain a Wave 6 item.

### 2026-06-09 - Group by file-size split-cap + real wall-clock, not playback duration (task 2.4)
**Context:** The first real DJI card (`DJI_001`, 110 clips, 7 days) exposed that **slow-motion clips
report a container/playback duration ~4× their real wall-clock capture time** (e.g. a 100 fps
segment: container 794.84 s, real ~199 s). The spec's planned continuity rule —
`creation_time[N] + duration[N] ≈ creation_time[N+1]` — silently mis-groups slow-mo because
`duration` is playback time, not elapsed. Filename indices also reset on format and collide across a
card, and photos taken mid-flight bump the counter.
**Options Considered:**
1. `creation_time + container duration` adjacency (the spec) — breaks on slow-mo.
2. Real elapsed via `nb_frames / capture_fps` — capture fps isn't in basic ffprobe (`r_frame_rate`
   is the *playback* rate); only derivable from the SRT, which isn't always present.
3. **File-size split-cap + real wall-clock start** — a segment at the ~4 GB byte ceiling continues
   into the next file; the first segment under the cap ends the recording; `creation_time` (real
   wall-clock, confirmed via AVFoundation and ffprobe) confirms adjacency within the prev segment's
   playback length + slack.
**Decision:** Option 3. A clip is "capped" when size ≥ `0.93 × maxSegmentSize` (floor 3 GB);
grouping buckets by variant suffix first (hard no-merge boundary), then within each bucket sorts by
`creation_time` and chains capped→next when params match (`StreamParameterGuard.check`) and the gap
is `0 < gap ≤ prevContainerSeconds + 12 s`. Missing `creation_time` or mismatched params breaks a
chain (defensive). The SRT stitcher's offset stays Σ playback duration — correct for the joined
video even in slow-mo — and is deliberately NOT changed.
**Rationale:** The byte-cap is speed-independent and DJI-specific (it's *why* the next file exists);
`creation_time` is reliable real time. Together they're robust to slow-mo, filename resets, and
photo-interleaving — every trap the real card contained. Hand-traced over all 110 clips → correct
recordings.
**Consequences:** Cap fraction/floor + slack are footage-tuned defaults (`GroupingTolerances`) flagged
for Wave 6 calibration across more drones (exFAT caps differ). Pure file-free core (`groupMetas`) is
unit-tested with real-card fixtures. A pathological false-merge (a capped *final* segment followed by
an unrelated same-params recording within its playback length) is possible but essentially never
occurs; documented.

### 2026-06-09 - Drop DJI's embedded mjpeg preview track from joins (-map 0:v:0)
**Context:** Validating a real join (`0104–0106`) revealed DJI MP4s carry a **second, low-res
1280×720 mjpeg *preview* video stream** (`v:1`) alongside the main HEVC. The concat recipe's
`-map 0:v` mapped *all* video streams, so `-c copy` carried the preview into the output, where it was
mangled into a malformed 3-frame / 0.00003 s stream (the source of `timescale not set` warnings).
**Decision:** Map only the **primary** video stream (`-map 0:v:0`) plus optional audio (`-map 0:a?`);
keep dropping data/telemetry tracks (`-map -0:d`).
**Rationale:** The preview is an internal DJI convenience track, not part of the master; carrying it
produces a phantom, malformed second video track that some players/NLEs mishandle. Re-verified: the
fixed recipe yields a single clean HEVC stream, 933.400 s / 23 335 frames = exact lossless sum.
**Consequences:** Joined masters contain only the real video (+audio when present). If a future need
arises to retain the preview, it would be a separate, explicit output — not the default.

### 2026-06-10 - Notarized direct-distribution signing pipeline (task 6.2)
**Context:** Signing was set up (Developer ID identity present, inside-out helper-signing build
phase) but never exercised end-to-end. The app needs to launch on other Macs without a Gatekeeper
"unidentified developer" block, which requires Apple notarization.
**Decision:** A Release build signed with **Developer ID Application** (Team `FDMSRXXN73`), hardened
runtime + secure timestamp on the app wrapper *and* both bundled helpers (ffmpeg/ffprobe), then
notarized via **App Store Connect API key** (keychain profile `conjoyn-notary`) and **stapled**.
Codified in `01_Project/scripts/notarize.sh` (build → verify → zip → `notarytool submit --wait` →
`stapler staple` → `spctl` verify). Distribution artifact: a stapled zip in `04_Exports/`.
**Rationale:** API key over app-specific password — doesn't expire yearly, no 2FA prompts,
non-interactive. Stapling makes the notarization ticket work offline. Manual signing identity
(not Automatic) because Automatic selects the Apple Development cert, which cannot be notarized.
**Consequences:** First real notarization **Accepted**; `spctl` reports `source=Notarized
Developer ID`. Credentials live only in the keychain (the `.p8` stays outside the repo). A DMG
wrapper (drag-to-Applications, background art) is deferred to the design/icon session — the zip is
sufficient for now. Note: the helper-hardening check originally used `grep -q`, which under
`set -o pipefail` SIGPIPE'd codesign and falsely failed; rewritten to capture-then-match.
