# DJIjoiner — Project AI Context

> Read `docs/00_base.md` for the Directions workflow. Read `specs/dji-auto-stitcher.md` for
> the full spec and `docs/decisions.md` for the why behind every choice.

## What it is
Native **macOS app** (SwiftUI / Swift 6, macOS 14+, Apple Silicon) that **auto-stitches
split DJI drone MP4 segments** back into one lossless file. It groups segments by embedded
**metadata continuity** (`creation_time` + duration + filename order, never merging camera
variants), joins with **FFmpeg's concat demuxer** (`-c copy`, no re-encode), fixes the
timecode↔creation-date metadata, stitches the `.SRT` telemetry with corrected time offsets,
and offers a **watch-folder** mode for SD-card ingest.

## Source material (read these)
- `specs/dji-auto-stitcher.md` — the spec + acceptance criteria.
- `docs/Technical Brief--Native macOS App for Auto-Stitching Split DJI Drone Video Files.md`
  — authoritative, sourced research on grouping, FFmpeg, metadata, watch-folder.
- `docs/P2toMXF Architecture Analysis -- Transferable Patterns for a DJI MP4 Auto-Stitcher.md`
  — what to port from P2toMXF and what to drop.
- `_reference/P2toMXF/` — the actual Swift 6/SwiftUI codebase to port from (gitignored).
  Its `CLAUDE.md` (949 lines) documents the architecture in depth.

## Tech stack
- **UI:** SwiftUI, Swift 6, MVVM. macOS 14.0+, arm64, Xcode 16+.
- **Read:** AVFoundation (`AVAsset`, `tmcd` track, `CMTime` duration) primary; `ffprobe` JSON fallback.
- **Join:** bundled **FFmpeg 8.x** concat demuxer —
  `ffmpeg -f concat -safe 0 -i list.txt -c copy -fflags +genpts -movflags +faststart -y out.mp4`.
- **Metadata fix:** exiftool / QuickTime atom write-back (TC authoritative).
- **No BMX / MXF tooling** — DJI MP4s are self-contained (the key divergence from P2toMXF).

## Architecture (ported from P2toMXF)
- **Reuse:** `FFmpegWrapper`(+Conversion/+Thumbnails), `QueueManager`(+Operations/Processing/
  Verification), `SpeedTracker`, `VerificationService`, `BundledToolResolver`,
  `TempDirectoryManager`, `Timecode`, `ConversionViewModel`+RecordGroups, signing script.
- **Replace:** `P2CardParser` (CLIP-XML) → ffprobe/AVFoundation DJI metadata reader;
  `discoverP2Cards(in:)` → `discoverDJIMedia(in:)` over DCIM/`100MEDIA`.
- **Drop:** `BMXWrapper`, bundled `bmxtranswrap`/`mxf2raw` + their dylibs.
- **New for DJI:** DJI filename parser (legacy `DJI_NNNN` + `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>`),
  camera-variant guard (`_T`/`_W`/`_Z`/`_V`/`_S` never merged), `.SRT` offset-stitcher,
  watch-folder (DispatchSource/FSEvents + stability + complete-set quiet-window state machine).

## Key decisions (see docs/decisions.md)
- Group by metadata continuity, not filenames.
- concat demuxer `-c copy` (lossless); never join across mismatched codec/res/fps.
- Timecode is authoritative for the date fix; surface discrepancies, user confirms.
- **Direct distribution + notarized**; App Sandbox **disabled**, Hardened Runtime **enabled**
  (FFmpeg GPL → MAS out of scope).
- v1 scope = engine + GUI + watch-folder + SRT stitching (scope-creep on SRT flagged).

## Packaging gotchas (from P2toMXF, save days)
- Keep bundled binaries OUT of the Xcode navigator; copy via a Run Script `ditto` phase.
- `ENABLE_USER_SCRIPT_SANDBOXING = NO`; entitlements: `cs.disable-library-validation`,
  `allow-unsigned-executable-memory`, `allow-jit`.
- Rewrite dylib load paths with `install_name_tool -change @rpath/… @executable_path/lib/…`,
  then re-sign (`sign-bundled-binaries.sh`).

## Folder layout (Directions convention)
- `01_Project/` — Xcode project + app code (the one place code lives).
- `02_Design/`, `03_Screenshots/`, `04_Exports/` — assets.
- `specs/`, `docs/` (Directions + briefs), `docs/sessions/` — logs.
- `_reference/P2toMXF/` — port source (gitignored).

## Working agreements
- Solo dev, **no PRs** — feature branches merged locally to `main`. Branch before building.
- Clean Xcode build cycle (kill app → clean → build → launch) before testing.
- Test the real join flow against actual DJI footage, not just "build succeeded".
- Log decisions to `docs/decisions.md`; update `docs/PROJECT_STATE.md` after phase changes.
