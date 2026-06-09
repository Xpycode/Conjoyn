# DJIjoiner — Auto-Stitcher Spec

## Overview
DJIjoiner is a native macOS app (SwiftUI / Swift 6, Apple Silicon, macOS 14+) that
automatically re-joins the split video segments DJI drones produce at the FAT32/exFAT
4 GB boundary (and ~16.8 GB on newer models) back into a single lossless file. It groups
segments by **embedded-metadata continuity** rather than filenames, joins them with
**FFmpeg's concat demuxer** (`-c copy`, no re-encode), fixes the timecode↔creation-date
metadata on the output, and stitches the sidecar **`.SRT` telemetry** with corrected
per-segment time offsets. A **watch-folder** mode automates the whole pipeline for SD-card
ingest. Architecture is ported from the user's own **P2toMXF** app (minus its BMX stage).

## User Stories
- As a drone operator, I want split `DJI_0001/0002/0003.MP4` clips auto-detected and
  joined into one file so I don't manually concatenate in an NLE.
- As an editor, I want the join to be **lossless and fast** (stream copy, I/O-bound) so
  quality is bit-identical to the originals.
- As a user, I want segments grouped by **actual recording continuity** so independent
  recordings dumped in one folder never get merged, and camera-variant lenses
  (`_W`/`_Z`/`_T`) are never merged together.
- As a user, I want the joined file's **creation date and timecode to be correct** so
  Finder/QuickTime/NLEs sort and display it properly.
- As a user, I want the **telemetry `.SRT`** for the whole recording in one continuous,
  correctly-timed subtitle file.
- As a user, I want to **drop an SD card / point at a watch folder** and have complete
  recordings join automatically once all segments have arrived.

## Acceptance Criteria

### Grouping engine
- [ ] Reads per-segment `creation_time`, exact `duration` (CMTime / rational), start
      timecode (`tmcd` when present), frame rate, codec/resolution/audio params — via
      AVFoundation primary, `ffprobe` JSON fallback.
- [ ] Orders/chains segments by a **layered key** (research-revised — DJI `creation_time` is
      unreliable and `tmcd` is usually `00:00:00:00`): (1) filename scheme + index, (2) SRT
      embedded wall-clock continuity, (3) decoded-duration adjacency — **and** stream params
      must match. `creation_time`/`tmcd` are corroborating-only, never the sole key.
- [ ] Parses both DJI naming schemes: legacy `DJI_NNNN.MP4` and timestamped
      `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>.MP4`.
- [ ] **Never** merges across camera-variant suffixes (`_T` thermal, `_W` wide, `_Z` zoom,
      `_V`/`_S`) — groups by variant first, then orders within variant.
- [ ] Handles DJI metadata quirks defensively: wrong/timezone-shifted `creation_time`
      (1904/1951 QuickTime-epoch bug), embedded TC often `00:00:00:00` → fall back to
      filename order + file mtime + duration arithmetic.
- [ ] Detects a discontinuity larger than tolerance and **splits into separate output
      groups** rather than silently joining (mirrors P2toMXF's blocking behavior).
- [ ] Detects mixed codec/resolution/fps within a candidate group and refuses `-c copy`
      with a clear message (offer re-encode fallback as opt-in, not default).

### Join engine
- [ ] Joins via `ffmpeg -f concat -safe 0 -i list.txt -c copy -fflags +genpts
      -movflags +faststart -y out.mp4` with explicit stream mapping (`-map 0:v -map 0:a?`).
- [ ] Re-applies start timecode (`-timecode`) and `creation_time` on the output (concat
      copy does not reliably preserve `tmcd`/date atoms).
- [ ] Post-join metadata pass writes consistent QuickTime date atoms
      (`mvhd`/`tkhd`/`mdhd` create+modify on the **1904 epoch**, plus `Keys:CreationDate` so
      QuickTime Player's Movie Inspector and Finder/Photos agree) — via a **native Swift atom
      writer** (NOT bundled exiftool). FFmpeg sets `creation_time`/`-timecode` during the join;
      the atom writer fixes the rest. TC treated as authoritative; discrepancies surfaced, user confirms.
- [ ] Output verified before originals are touched: `ffprobe` container check +
      decode-to-null (VideoToolbox HW accel), A/V sync at join boundaries spot-checked.
- [ ] Originals are **never deleted automatically** without explicit user opt-in.

### SRT telemetry stitching (v1 — differentiator)
- [ ] Merges sidecar `.SRT` files for a group into one, **re-timing each segment's cues by
      the cumulative duration** of preceding segments so timestamps stay continuous.
- [ ] If `.SRT` is absent for a segment, degrades gracefully (join video anyway, note gap).
- [ ] Output `.SRT` written alongside the joined video.

### Watch-folder automation (v1)
- [ ] Monitors a folder (DispatchSource for flat; FSEvents for recursive DCIM trees).
- [ ] **Stability gate**: a file is "settled" only after size+mtime unchanged for N polls
      (~3–5 s) and no exclusive writer holds it — partial copies never processed.
- [ ] **Complete-set gate**: a group joins only when the last segment is below the split
      threshold AND no new chaining segment appears within a quiet window (~30–60 s).
- [ ] Per-group state machine: `Discovered → Settling → Grouped → Ready → Joining →
      VerifyingMetadata → Done/Failed`, **persisted** so relaunch resumes.
- [ ] Bounded background concurrency (1–2 jobs) to avoid disk thrash.

### App / packaging
- [ ] SwiftUI GUI: drag-and-drop + file picker feeding the same engine; shows detected
      groups, per-boundary continuity/gap report, TC/creation-date diff, confirm-before-fix.
- [ ] FFmpeg + exiftool (if used) bundled in `Resources/`, dylib paths fixed via
      `install_name_tool`, signed via adapted `sign-bundled-binaries.sh`.
- [ ] App Sandbox **disabled**, Hardened Runtime **enabled**, notarized for direct
      distribution (Developer ID). MAS is out of scope (FFmpeg GPL).

## Technical Considerations
- **Port from P2toMXF** (`_reference/P2toMXF/`): reuse `FFmpegWrapper`(+Conversion,
  +Thumbnails), `QueueManager`(+Operations/Processing/Verification), `SpeedTracker`,
  `VerificationService`, `BundledToolResolver`, `TempDirectoryManager`, `Timecode`,
  `ConversionViewModel`+RecordGroups, signing script. **Drop** `BMXWrapper`, `P2CardParser`,
  bundled `bmxtranswrap`/`mxf2raw` + their dylibs.
- **Replace** `P2CardParser` (CLIP-XML) with an ffprobe/AVFoundation DJI metadata reader.
- **Replace** `discoverP2Cards(in:)` with `discoverDJIMedia(in:)` scanning DCIM/`100MEDIA`.
- Engine: AVFoundation (read) + FFmpeg concat demuxer (join) + exiftool/atom write-back (fix).

## Edge Cases
- Multiple independent recordings in one folder → separated by the time-gap test.
- Trailing tiny final segment → included if it chains by continuity.
- Mixed drones / mixed settings → stream-param equality gate prevents bad merges.
- Missing middle segment → TC/time discontinuity > tolerance → split or flag the gap.
- VFR footage (`avg_frame_rate ≠ r_frame_rate`) → use creation-time/sample-count continuity
  instead of nominal-rate frame math.
- H.264 vs H.265 segments → never `-c copy` join across codecs; detect and refuse.
- "Non-monotonous DTS" warnings → mitigate with `+genpts`; verify A/V sync (warning ≠ error).

## Out of Scope (v1)
- Burned-in HUD telemetry overlay (visible data-burn).
- Re-encoding / transcoding as a primary path (only an opt-in fallback for mismatched groups).
- Mac App Store distribution.
- Non-DJI camera formats.

## Open Risks (flagged at interview)
- **SRT offset-correction stitching** is acknowledged in the brief as "a known unsolved pain
  point in the DJI community" — highest-uncertainty item in v1; may need real-footage
  iteration. Was explicitly chosen for v1 despite scope-creep risk.
- **Full app (engine + GUI + watch-folder) as the first bite** is large; planning should
  still stage internally (engine → GUI → watch-folder) even though all land in v1.
- Tolerance / quiet-window / stability-poll values are starting defaults, not measured —
  tune against real DJI footage from the target drones (Mavic/Air/Mini).
