# Scanning a Card

## What Conjoyn looks for

Conjoyn recognises two DJI filename patterns:

- **Modern:** `DJI_YYYYMMDDHHMMSS_NNNN_D.MP4` — e.g. `DJI_20260521174715_0004_D.MP4`
- **Legacy:** `DJI_NNNN.MP4` — e.g. `DJI_0042.MP4`

Files are grouped into recordings by metadata continuity — not just filename order. Two segments belong to the same recording when their codec, resolution, frame rate, and timebase all match and the files are consecutive. This prevents incorrectly merging clips from different camera modes or separate flights.

## Card root vs. media folder

You can drop the card root (e.g. `/Volumes/SD_CARD`) or navigate directly to the media folder (e.g. `DCIM/100MEDIA`). When you drop the card root, Conjoyn descends one level to find the `DCIM/*` media folder automatically.

## Skipped files

Files that are not DJI clips, cannot be read, or whose stream parameters can't be probed are counted as **skipped** and shown in the header. They are never touched or moved.

## Rescanning

Click **Scan** at any time to refresh the list. The filter resets to **All** and split recordings are pre-selected. Any jobs already in the queue are unaffected.
