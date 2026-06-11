# What Conjoyn Does

DJI cameras split long recordings into segments at around 4 GB on the SD card. What looks like one continuous flight in the camera actually arrives as `DJI_0001.MP4`, `DJI_0002.MP4`, `DJI_0003.MP4` — separate files that belong together.

Conjoyn finds those split groups, verifies they're joinable, and merges them into a single lossless file using FFmpeg's concat demuxer (`-c copy` — no re-encode, no quality loss). It also fixes three things that DJI gets wrong:

## Recording date

DJI embeds the recording start in the container as `creation_time`, but the value is often local time labeled as UTC (no timezone conversion), or missing entirely. Copying files resets the filesystem date. Conjoyn derives the correct date from the filename timestamp or the `.SRT` telemetry sidecar and writes it back.

## Timecode

NLEs such as DaVinci Resolve, Premiere Pro, and Final Cut Pro use the `tmcd` track to place a clip at the right time of day on the timeline. DJI files have no `tmcd`. Conjoyn stamps one, seeded from the corrected recording start.

## Telemetry sidecars

If DJI wrote `.SRT` telemetry files alongside the segments, Conjoyn merges them with corrected time offsets into a single `.SRT` next to the output file.

## Singles

Single files that weren't split still benefit: the date, timecode, and SRT fixes all apply, and Conjoyn's lossless re-mux adds `+faststart` (moov atom at the front) for faster NLE ingest.
