# Scanning a Card

## What Conjoyn looks for

Conjoyn recognises three filename patterns:

- **DJI modern:** `DJI_YYYYMMDDHHMMSS_NNNN_D.MP4` — e.g. `DJI_20260521174715_0004_D.MP4`
- **DJI legacy:** `DJI_NNNN.MP4` — e.g. `DJI_0042.MP4`
- **GoPro chaptered:** `GX<chapter><number>.MP4` or `GH<chapter><number>.MP4` — e.g. `GX016338.MP4`, where `01` is the chapter and `6338` identifies the recording. GoPro's older `GOPR….MP4` and `GP01….MP4` names aren't recognised yet.

Files are grouped into recordings by metadata continuity — not just filename order. Two files belong to the same recording when their codec, resolution, frame rate, and timebase all match and the files run consecutively. This prevents incorrectly merging clips from different camera modes or separate takes.

How "consecutive" is judged depends on the camera. A DJI segment continues into the next when it filled the card's split size and the next one picks up on the clock. GoPro chapters chain when the timecode embedded in one runs straight into the start of the next — the size a GoPro splits at isn't a fixed number, so it can't be used as the signal.

## Card root vs. media folder

You can drop the card root (e.g. `/Volumes/SD_CARD`) or navigate directly to the media folder (e.g. `DCIM/100MEDIA` on a DJI card, `DCIM/100GOPRO` on a GoPro one). When you drop the card root, Conjoyn descends one level to find the `DCIM/*` media folder automatically.

## Skipped files

Files that don't match a recognised camera naming scheme, cannot be read, or whose stream parameters can't be probed are counted as **skipped** and shown in the header. They are never touched or moved.

## Rescanning

Click **Scan** at any time to refresh the list. The filter resets to **All** and split recordings are pre-selected. Any jobs already in the queue are unaffected.
