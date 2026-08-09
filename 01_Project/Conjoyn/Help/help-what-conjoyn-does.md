# What Conjoyn Does

Drone and action cameras split long recordings into several files on the SD card. What looks like one continuous take in the camera actually arrives as separate files that belong together — `DJI_0001.MP4`, `DJI_0002.MP4`, `DJI_0003.MP4` from a DJI, or `GX016338.MP4`, `GX026338.MP4` from a GoPro.

Conjoyn finds those split groups, verifies they're joinable, and merges them into a single lossless file using FFmpeg's concat demuxer (`-c copy` — no re-encode, no quality loss). It also fixes three things cameras commonly get wrong:

## Recording date

Cameras embed the recording start in the container as `creation_time`, but the value is often local time labeled as UTC (no timezone conversion), or missing entirely. Copying files resets the filesystem date. Conjoyn derives the correct date from the best signal the camera actually left behind — the `.SRT` telemetry or filename timestamp on DJI, the embedded date on cameras that write neither — and writes it back.

## Timecode

NLEs such as DaVinci Resolve, Premiere Pro, and Final Cut Pro use the `tmcd` track to place a clip at the right time of day on the timeline. DJI files carry no `tmcd` at all; GoPro files do. Either way Conjoyn stamps a fresh one on the output, seeded from the corrected recording start.

## Telemetry

DJI writes flight telemetry into `.SRT` sidecar files next to the segments. Conjoyn merges them with corrected time offsets into a single `.SRT` next to the output file.

GoPro instead records its telemetry into a data track *inside* the video file. Conjoyn carries that track through the join untouched, then checks it survived — the same verification the picture and sound get.

## Singles

Single files that weren't split still benefit: the date and timecode fixes apply, any `.SRT` sidecar is carried over, and Conjoyn's lossless re-mux adds `+faststart` (moov atom at the front) for faster NLE ingest.
