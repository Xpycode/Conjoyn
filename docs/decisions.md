# Decisions Log

This file tracks the WHY behind technical and design decisions for DJIjoiner.

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
