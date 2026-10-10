<div align="center">

# conjoyn

**Auto-stitch split DJI and GoPro recordings back into one lossless file — on your Mac.**

Long camera recordings often arrive as several MP4 files. Conjoyn finds the segments that belong
together and joins them **without re-encoding**, preserving recording dates, timecode, and telemetry.
It supports DJI split recordings and GoPro GX/GH chapters, with DJI `.SRT` sidecars re-timed and
GoPro embedded sensor data preserved across the join.

![Conjoyn main window](01_Project/Conjoyn/Help/main-loaded.png)

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple)
![Apple Silicon](https://img.shields.io/badge/Apple%20Silicon-arm64-black?logo=apple)
![Swift 6](https://img.shields.io/badge/Swift-6-orange?logo=swift)
![License: PolyForm Noncommercial](https://img.shields.io/badge/license-PolyForm%20Noncommercial%201.0.0-blue)

</div>

---

## Why

When you copy footage off an SD card, a single long shot arrives as several numbered MP4 files.
Stitching them by hand in an NLE means a re-encode (quality loss + time) or fiddly concat commands,
and the joined file usually ends up with the wrong creation date and a broken telemetry track.

Conjoyn does it the right way:

- **Lossless.** Joins with FFmpeg's concat demuxer using `-c copy` — your video and audio streams
  are copied bit-for-bit. No re-encode or generation loss; processing time depends on footage, storage, and verification.
- **Smart grouping.** DJI segments use recording-date continuity and filename order; GoPro
  chapters use camera timecode and chapter names. Stream parameters are checked, and DJI
  camera variants (`_W`/`_T`/`_Z` wide / tele / zoom) stay separate.
- **Correct metadata.** The output carries the real recording start date and timecode, with any
  date↔timecode discrepancy surfaced for you to confirm.
- **Telemetry preserved.** The `.SRT` sidecar (GPS, altitude, gimbal, exposure) is stitched back
  together with corrected time offsets — when one is present.

## Features

- 🎬 One-click join of DJI split recordings and GoPro GX/GH chapters, grouped automatically
- 📁 Watch-folder ingest with recording-aware history and recovery after remounting
- 🔎 Recordings search through Edit → Find, preserving selection
- 🛡️ Output collision protection for queued videos and telemetry sidecars
- 🧬 Lossless concat (`-c copy`) — no re-encoding, ever
- 🗓️ Date + timecode metadata fix, with manual timecode override
- 🛰️ DJI `.SRT` telemetry stitching and byte-preserved GoPro `gpmd` telemetry
- ✅ Source↔output verification with integrity flags (codec/res/fps mismatch, gaps, slow-mo)
- 📊 Sortable recordings list, live ETA / speed, single-file export
- 🌗 Light / Dark / Match-System appearance, runtime Dock-icon switch
- 🔄 Built-in auto-update (Sparkle)
- 🔒 Direct distribution, **signed & notarized** by Apple

> **Works with just the MP4s.** SRT sidecars are optional — if you only copied the video files,
> Conjoyn still discovers, groups, and losslessly joins them. The SRT step is simply skipped when
> there's nothing to stitch.

## Requirements

- macOS **14.0 (Sonoma)** or later
- **Apple Silicon** (arm64)

## Download

**[Download Conjoyn 1.0.6 for macOS](https://conjoyn.lucesumbrarum.com/dl.php?app=conjoyn)**

Released 10 October 2026 · macOS 14+ · Apple Silicon · signed and notarized DMG.
Open the DMG and drag Conjoyn into Applications. Existing installations can update through Sparkle.
See the [website](https://conjoyn.lucesumbrarum.com) and
[release history](https://conjoyn.lucesumbrarum.com/changelog.html).

### What's new in 1.0.6

- Protect queued outputs and telemetry sidecars from filename collisions.
- Keep folder scans current and recover watch discovery after changes or remounting.
- Preserve unreadable queues for recovery and review ambiguous older processing history.
- Search recordings and apply destination changes to pending jobs after restoring a queue.

### Camera compatibility

DJI split MP4 recordings and GoPro `GX`/`GH` chapter names are supported. Older GoPro
`GOPR`/`GP` naming is not supported. Real-footage GoPro validation covers HERO11 HEVC;
HERO11 H.264 and HERO7 validation remain pending.

If watch discovery stays stalled because both workers do not return, relaunch Conjoyn.
Recording identity uses metadata and file descriptors; identical replacements may be indistinguishable.

## Build from source

The repo is the full app source. The FFmpeg binaries are **not** committed (they're large and
reproducibly built) — fetch or build them first.

```bash
# 1. Project generator + FFmpeg
brew install xcodegen
01_Project/scripts/fetch-ffmpeg.sh          # or build-ffmpeg-lgpl.sh to build LGPL FFmpeg yourself

# 2. Generate the Xcode project and open it
cd 01_Project
xcodegen generate
open Conjoyn.xcodeproj
```

Then build & run the **Conjoyn** scheme. macOS 14 SDK / Xcode 16+.

## How it works

| Stage | What happens |
|-------|--------------|
| **Discover** | Scan a folder (e.g. `DCIM/100MEDIA`); read each clip's duration + embedded metadata via AVFoundation, with an `ffprobe` fallback. |
| **Group** | Match DJI recording-date continuity or GoPro timecode and chapter order, with compatible streams. Camera variants are kept apart. |
| **Join** | `ffmpeg -f concat -safe 0 -i list.txt -c copy -fflags +genpts -movflags +faststart -y out.mp4` |
| **Fix** | Write the corrected `creation_time` and timecode atoms back to the output. |
| **Telemetry** | Re-time DJI `.SRT` cues; preserve and verify embedded GoPro `gpmd` data across chapters. |
| **Verify** | Compare source vs. output and raise integrity flags before declaring success. |

## Tech

SwiftUI · Swift 6 · MVVM · AVFoundation · a bundled, statically-linked **LGPL** build of FFmpeg 8.x.
The app runs **without the App Sandbox** (Hardened Runtime enabled) so it can drive the bundled
FFmpeg, which is why it ships via direct distribution rather than the Mac App Store.

### FFmpeg

Conjoyn bundles FFmpeg under the **LGPL** (no GPL/nonfree components). The binaries are built
reproducibly by `01_Project/scripts/build-ffmpeg-lgpl.sh` and are not part of this repository.

## License

Licensed under the **[PolyForm Noncommercial License 1.0.0](LICENSE.md)**.

You're free to read, fork, modify, and share the code **for non-commercial purposes** — personal
use, study, hobby projects, research, education. **You may not use this code (or a derivative of it)
for a commercial purpose**, including selling it or shipping it as part of a paid app. This is a
source-available, non-commercial license — not an OSI "open source" license.

---

<sub>Conjoyn is an independent project and is **not affiliated with, endorsed by, or sponsored by
DJI or GoPro**. Their names and related marks are trademarks of their respective owners. Copyright © 2026 Luces
Umbrarum.</sub>
