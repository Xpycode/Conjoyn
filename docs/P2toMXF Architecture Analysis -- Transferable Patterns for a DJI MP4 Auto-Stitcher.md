# P2toMXF Architecture Analysis → Transferable Patterns for a DJI MP4 Auto-Stitcher

## TL;DR
- **P2toMXF is a native macOS SwiftUI app (Swift 6, ~88% Swift) that joins Panasonic P2 spanned clips with a two-stage, no-re-encode pipeline: BMX (`bmxtranswrap -t op1a`) rewraps each OP-Atom clip's 5 files into one OP1a MXF, then FFmpeg's concat demuxer (`-f concat -safe 0 -c copy`) stitches those into the final MXF/MOV.** For a DJI MP4 stitcher, stage 1 (BMX) is unnecessary — DJI files are already self-contained MP4s — so the DJI app collapses to *just the FFmpeg concat-demuxer engine plus the grouping/continuity logic*, which is the directly reusable core.
- **The most transferable code is the grouping + timecode-continuity architecture**: P2toMXF groups segments into "record groups" (`ConversionViewModel+RecordGroups.swift`), validates that consecutive segments are gap-free via a `Timecode` struct with a `frameGap()` check, and blocks merges when discontinuous. The same pattern maps cleanly onto DJI's `creation_time`/duration adjacency test.
- **The whole subprocess-orchestration scaffold transfers wholesale**: bundled binaries in `Resources/`, sandbox disabled + hardened runtime, `install_name_tool` dylib path fixing, a `QueueManager` singleton with Codable JSON persistence, security-scoped bookmarks, `IOPMAssertion` sleep prevention, and historical speed-based ETA estimation.

## Key Findings

### 1. Concatenation approach
P2toMXF does **not** do direct byte-level MXF manipulation and does **not** use mxflib/raw byte surgery for the join. It uses a **two-tool shell-out pipeline**:

1. **BMX rewrap (per clip):** `bmxtranswrap -t op1a -o output.mxf VIDEO/0234LZ.MXF AUDIO/0234LZ00.MXF AUDIO/0234LZ01.MXF AUDIO/0234LZ02.MXF AUDIO/0234LZ03.MXF` — converts the 1 video + 4 audio OP-Atom files into a single self-contained OP1a MXF. BMX is required because **FFmpeg's MXF muxer fails on P2 AVC-Intra** with `track 0: frame size does not match index unit size, 568320 != 568832` — Panasonic uses a proprietary 512-byte frame-padding scheme, and BMX has the manufacturer-specific lookup tables to handle it.
2. **FFmpeg concat (across clips):** writes a concat list file and runs `ffmpeg -f concat -safe 0 -i concat.txt -c copy -map 0:v -map 0:a -timecode 18:09:34:24 -f mxf -y output.mxf`. The concat demuxer with `-c copy` is a pure stream copy — bit-for-bit identical video/audio, only the container changes. (Per FFmpeg's official docs the concat demuxer requires matching streams — same height, width, pixel format, and codecs — and with `-c copy` "ensures no re-encoding takes place, resulting in a faster and lossless process"; mismatched inputs require the concat *filter*, which re-encodes.)

For MOV single-clip output it can skip BMX and use FFmpeg directly with explicit stream mapping: `ffmpeg -i VIDEO/x.MXF -i AUDIO/x00.MXF … -map 0:v:0 -map 1:a:0 … -c:v copy -c:a copy -timecode … -f mov -y output.mov` (MOV works in FFmpeg because it records sizes after writing rather than predicting them).

The MXF header/index/footer structure is therefore handled entirely by BMX (rewrap) and FFmpeg's muxer (concat) — the app itself never parses MXF KLV packets.

**Documented throughput:** BMX rewrap ~30× realtime, FFmpeg concat ~60× realtime, 16 clips merged in ~1–2 minutes. Bundled tool versions: FFmpeg 8.0.1, bmxtranswrap 1.2, mxf2raw 1.2. (FFmpeg 8.0 "Huffman" was released Aug 23, 2025, with point release 8.0.1 following in November 2025 — so the bundled binary is current as of the app's v1.2 release.)

### 2. Spanned-clip grouping logic
Grouping lives in `ConversionViewModel+RecordGroups.swift` and is surfaced in the UI as clips "grouped by recording span." Metadata is parsed by `Services/P2CardParser.swift`, which reads the P2 `CLIP/{ClipName}.XML` files. The grouping is driven by **timecode continuity** — the app computes a `timecodeIssues` array of `(clip1, clip2, gapFrames)` tuples and treats consecutive clips as one logical recording when there is no gap/overlap:

```
var timecodeIssues: [(clip1: P2Clip, clip2: P2Clip, gapFrames: Int)]
// non-empty if gaps/overlaps detected between consecutive clips
// gap > 0: missing frames, gap < 0: overlapping frames
```

When the timecode is discontinuous, the merge is **blocked** in the UI and the user is told to switch to Individual mode or deselect the problem clip. The clip filename's 6-char hex prefix (e.g. `0234LZ`) is used for file-relationship mapping (video `VIDEO/0234LZ.MXF` ↔ audio `AUDIO/0234LZ00–03.MXF`), and `discoverP2Cards(in:)` validates/walks folder structure to find cards:

```
func discoverP2Cards(in url: URL) -> [URL] {
    if validateP2Structure(at: url) { return [url] }   // url itself is a card
    let contents = try fm.contentsOfDirectory(at: url, ...)
    return contents.filter { validateP2Structure(at: $0) }
                   .sorted { $0.lastPathComponent < $1.lastPathComponent }
}
```

So the algorithm is: discover/validate card folders → parse each clip's XML → sort → group consecutive clips whose start-timecode + duration chain is contiguous → require full-group selection before a concat job is allowed.

### 3. Timecode handling
`P2CardParser.swift` reads `<StartTimecode>HH:MM:SS:FF</StartTimecode>` from the CLIP XML, plus `<Duration>` (in edit units) and `<EditUnit>` (e.g. `1/50`). Two documented critical fixes:
- **EditUnit conversion:** duration is in edit units not TC frames; `duration_tc_frames = edit_units × (tc_rate / edit_rate)` (e.g. 6432 × 25/50 = 3216).
- **Frame-rate priority:** the TC rate comes from the `<Codec>` string (`AVC-I_1080/25p` → 25 fps), and a `frameRateFromCodec` flag prevents the sensor `<FrameRate>50p` element from overwriting it.

A `Timecode` struct encapsulates this:
```
struct Timecode {
    let hours, minutes, seconds, frames: Int
    let frameRate: Double
    init?(string: String, frameRate: Double)   // parse "HH:MM:SS:FF"
    var totalFrames: Int                         // absolute frames
    static func frameGap(...) -> Int             // continuity check
}
```
On output, timecode is **preserved** — the original P2 start TC is passed through with FFmpeg's `-timecode HH:MM:SS:FF` flag (`preserveTimecode: Bool = true` in settings). It is rewritten only insofar as the output container's start-TC is set to the first clip's value.

### 4. Metadata handling
`P2CardParser.swift` parses the CLIP XML for codec (`AVC-I_1080/25p`), start timecode, duration, frame rate, and audio-channel count (`<Audio>` element count = number of channels; `ValidAudioFlag="false"` on `<Video>` signals the audio in the video MXF is unusable). Output metadata is essentially what the BMX/FFmpeg muxers write plus the carried-through start timecode; copying the source XML alongside the output was a listed *future* enhancement ("XML metadata copy"), i.e. not yet implemented as of the documentation. The app also extracts thumbnails via FFmpeg (`FFmpegWrapper+Thumbnails.swift`).

### 5. Language / architecture
- **Language/UI:** Swift 6 / SwiftUI, macOS 14.0+ (Sonoma), Apple Silicon arm64, Xcode 16+. MIT license. v1.2 released Apr 13, 2026.
- **Structure:** MVVM. Project under `01_Project/P2toMXF.xcodeproj`. Key files:
  - `ConversionViewModel.swift` + extensions (`+CardManagement`, `+Conversion`, `+RecordGroups`) — state + orchestration.
  - `Models/P2Clip.swift` — all data models + enums (`OutputContainer{.mov,.mxf}`, `ProcessingMode{.individual,.concatenate}`, `AudioMapping`, `JobStatus`, `VerificationStatus`), `ConversionSettings`, `ConversionJob`, `Timecode`, and estimation models. All `Codable`, with URLs stored as String paths internally.
  - `Services/`: `P2CardParser` (XML), `FFmpegWrapper` (+`Conversion`, +`Thumbnails`), `BMXWrapper`, `QueueManager` (+`Processing`, +`Operations`, +`Verification`), `VerificationService`, `SpeedTracker`, `ThumbnailManager`.
  - `Resources/`: bundled `ffmpeg`, `bmxtranswrap`, `mxf2raw` + `lib/` dylibs (libbmx, libMXF++, libMXF, libexpat, liburiparser).
- **Build/signing specifics that matter:** Sandbox **disabled** (needed for subprocess exec), Hardened Runtime **enabled** (for notarization), `ENABLE_USER_SCRIPT_SANDBOXING = NO`, entitlements `com.apple.security.cs.disable-library-validation`, `allow-unsigned-executable-memory`, `allow-jit`. dylib paths rewritten with `install_name_tool -change @rpath/… @executable_path/lib/…` and re-signed. A Run Script phase `ditto`s `lib/` into the bundle; the `lib/` folder is deliberately NOT in the Xcode navigator (adding it caused SIGABRT from dylib linking).
- **Queue/UX systems:** `QueueManager` singleton (sequential jobs, Codable JSON persistence to `~/Library/Application Support/P2toMXF/queue.json`, filename-conflict auto-rename `Output.mxf`→`Output (1).mxf`, `IOPMAssertion` sleep prevention, security-scoped bookmark handling); `SpeedTracker` historical ETA (last 50 records to `speed_records.json`, confidence levels); `VerificationService` (ffprobe container check + FFmpeg decode-to-null quick/full, VideoToolbox HW accel).

### 6. Transferable patterns for the DJI app
**Directly reusable (high value):**
- **The FFmpeg concat-demuxer engine** is the exact engine the DJI app needs, essentially unchanged: build a temp list file of `file '…'` lines in recording order, then `ffmpeg -f concat -safe 0 -i list.txt -c copy -movflags +faststart -y output.mp4`. DJI segments from one continuous recording share identical codec/resolution/frame-rate (same camera, same session) — exactly the concat-demuxer precondition — so no BMX stage is needed. (DJI splits because "the FAT32/exFAT file system can't store a single file larger than 4GB. So, once your video size reaches 4GB, the file system will end the current segment and immediately start a new one"; some newer models instead cap segments near 16.8 GB / ~20–21 min.)
- **The grouping + continuity architecture** (`RecordGroups` + `Timecode.frameGap` + `timecodeIssues` blocking) ports directly. For DJI, the continuity signal becomes the MP4 container `creation_time` + duration adjacency (read via ffprobe), since DJI splits are written back-to-back at the boundary.
- **`discoverP2Cards(in:)`'s validate-or-walk pattern** maps to scanning a DCIM/`100MEDIA` folder for DJI MP4s.
- **The entire subprocess scaffold**: `FFmpegWrapper` (Process management, progress parsing), bundled-binary signing (`sign-bundled-binaries.sh`), sandbox/entitlement config, `QueueManager` (persistence, conflict resolution, sleep prevention), `SpeedTracker` ETAs, `VerificationService`, `ThumbnailManager`. None of this is P2-specific.
- **Data-model shape**: `ConversionSettings`/`ConversionJob`/`JobStatus`/`Timecode`/Codable-with-String-URLs is a clean template.

**Must change / drop for DJI:**
- Drop BMX entirely (`BMXWrapper.swift`, bundled `bmxtranswrap`/`mxf2raw` + their dylibs) — DJI MP4 needs no rewrap.
- Replace `P2CardParser`'s CLIP-XML parsing with **ffprobe-based metadata extraction** (DJI has no sidecar XML; metadata lives in the MP4 `creation_time`/`timecode` plus optional `.SRT`/`.LRF` sidecars). Note the well-known DJI quirks to handle: MP4 `creation_time` is frequently wrong/timezone-shifted (the "1904/1951" QuickTime-epoch bug; some models write modified-date in GMT), and DJI MP4 start timecode is often `00:00:00:00`, so grouping should lean on filename order + `creation_time` + duration rather than embedded TC alone.
- DJI grouping signals differ: legacy naming is sequential `DJI_0001.MP4`, `DJI_0002.MP4`, `DJI_0003.MP4` (one recording → consecutive indices). Newer naming embeds a timestamp + index + suffix — e.g. the DJI Mini 4 Pro emits `DJI_20231028130043_0002_D.MP4` (plus matching `.SRT`/`.LRF`). Enterprise/multi-sensor models append camera-variant suffixes that must **never** be merged together: on the Mavic 3 Enterprise / M300 H20T, `_T` = thermal, `_W` = wide-angle lens, `_Z` = zoom lens (and `_V`/`_S` for standard/screen variants).

## Details

**Why the pipeline is split in two for P2 but one for DJI.** P2's problem is *containerization* (5 separate OP-Atom essence files per clip that FFmpeg can't mux for AVC-Intra) *plus* spanning. DJI's problem is *only* spanning of already-muxed MP4s. So P2toMXF's BMX stage solves a problem the DJI app doesn't have; the DJI app keeps only P2toMXF's second stage and its grouping brain.

**The continuity-check design is the crown jewel to copy.** P2toMXF refuses to silently concatenate clips that aren't truly contiguous — it computes per-boundary gap frames and surfaces them, preventing the classic "frame missing at the join" defect that DJI itself acknowledges. (DJI Support, quoted on the PhantomPilots forum: "I do understand that at a certain point, there is a skipped frame when you are attempting to record a video. The reason for having it set on this file saving orientation is because it is for file safety and security … it is segmented every 4GB.") For DJI, replicate the P2toMXF approach by computing, for each adjacent pair, whether `creation_time[n+1] ≈ creation_time[n] + duration[n]` within a small tolerance; if not, warn/split into separate output groups. This is the same shape as `timecodeIssues`.

**Concat boundary correctness for MP4.** Unlike MXF, MP4 needs `-movflags +faststart` to relocate the `moov` atom to the front for smooth playback/streaming, and if any segment unexpectedly lacks an audio track the concat demuxer will fail — both are DJI-specific guards to add. The demuxer (not the filter) is correct here because all segments share codec/params, giving instant lossless joins.

**Packaging lessons that will save days.** The CLAUDE.md "Common Issues" are reusable verbatim: keep bundled binaries out of the Xcode navigator and copy via a Run Script `ditto` phase; set `ENABLE_USER_SCRIPT_SANDBOXING = NO`; disable App Sandbox (or use sandbox-inheritance for a helper if targeting the Mac App Store — note FFmpeg's GPL licensing makes MAS distribution legally fraught, so direct-distribution + notarization, as P2toMXF does, is the pragmatic path); rewrite dylib load paths with `install_name_tool` to `@executable_path/lib/` and re-sign.

**Source-access caveat.** The verbatim Swift source files could not be retrieved — GitHub's `tree`/`blob`/`raw` pages were robots-blocked to the fetcher and the jsDelivr CDN served `.swift` as binary. All function names, struct definitions, command strings, and design decisions above are taken from the repository's `README.md` and the unusually detailed `CLAUDE.md` (949 lines of architecture + session logs), which document the implementation directly. Exact line-level code bodies (e.g. the precise comparison inside the grouping loop) should be confirmed by opening the files locally.

## Recommendations

**Stage 1 — Build the MVP engine (reuse directly).**
1. Port `FFmpegWrapper` + the concat-demuxer call as the core engine: `ffmpeg -f concat -safe 0 -i list.txt -c copy -movflags +faststart -y out.mp4`. Bundle FFmpeg 8.x in `Resources/`, sign via an adapted `sign-bundled-binaries.sh`, disable sandbox, enable hardened runtime. **Drop BMX and all MXF tooling.**
2. Port `Timecode`/`timecodeIssues` as a `creation_time`+duration adjacency check (read via ffprobe `-show_entries format_tags=creation_time:format=duration`). Block/segment on discontinuity.
3. Port `discoverP2Cards(in:)` → `discoverDJIMedia(in:)` scanning DCIM folders for `*.MP4`/`*.MOV`.

**Stage 2 — DJI-specific grouping.** Implement a grouper that: (a) parses both DJI naming schemes (`DJI_NNNN` and `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>`); (b) groups by camera-variant suffix first (never merge `_T` thermal with `_V`/`_W`/`_Z`); (c) within a variant, orders by index/timestamp; (d) confirms contiguity via `creation_time`+duration; (e) emits one output per contiguous group. Handle the DJI `creation_time` timezone/epoch bug defensively (fall back to filename order and file mtime).

**Stage 3 — Port the UX systems unchanged.** `QueueManager` (Codable JSON persistence, filename-conflict auto-rename, `IOPMAssertion` sleep prevention, security-scoped bookmarks), `SpeedTracker` ETAs, `VerificationService` (ffprobe + decode-to-null with VideoToolbox), `ThumbnailManager`. These are format-agnostic.

**Benchmarks/thresholds that change the plan:**
- If a contiguity gap > ~1 frame appears at a boundary, do NOT silently concat — split the output (mirrors P2toMXF blocking discontinuous merges). Tolerance should be ~½ frame at the clip's fps.
- If segments differ in codec/resolution/fps (e.g. mixed sessions), the concat demuxer will produce corrupt output — detect via ffprobe and fall back to the concat *filter* (re-encode) or refuse, with a clear message.
- If targeting the Mac App Store becomes a goal, FFmpeg's GPL licensing forces either an LGPL FFmpeg build or abandoning MAS — decide early.

## Caveats
- **No verbatim source could be read.** Findings derive from `README.md` + `CLAUDE.md`, which are richly detailed but are documentation, not the compiled code; the precise body of the grouping comparison and exact in-code command-array strings should be verified by opening the `.swift` files locally (the repo is public at github.com/Xpycode/P2toMXF; clone it).
- **The repo is the user's own**, public, MIT-licensed, Swift 6/SwiftUI, currently v1.2 (Apr 13, 2026) with 61 commits and a single contributor — small, recent, and actively iterated per the session logs.
- **DJI metadata is messier than P2's.** P2 has authoritative CLIP XML with explicit start timecode and edit units; DJI has no sidecar XML, frequently wrong `creation_time`, and often-zero embedded timecode. The grouping logic must therefore rely more on filename + file ordering + duration arithmetic than P2toMXF does on XML timecode.
- **P2toMXF's exact grouping primary key is documented as timecode-continuity**, not UMID or CLIP-XML head/next/prev pointers; if the user intended to also use P2's `<Relation>`/`head`/`next`/`prev` span pointers (which the P2 spec provides), that is not reflected in the documented design and would be confirmed only by reading the source.