# Troubleshooting

## The scan finds no recordings

- Make sure you've selected the folder that contains the `.MP4` files directly, not a parent folder several levels up. Conjoyn descends only one level from a card root.
- Non-DJI files (GoPro, Sony, etc.) are skipped — the "skipped" counter in the header tells you how many were bypassed.
- If files from a third-party DJI lens adapter or accessory use non-standard naming, they may not be recognised.

## The date shown looks wrong

Check the origin tag (`from filename` / `from SRT cue`) under the recording name. If the date is still incorrect, the filename or SRT may encode a wrong timestamp (rare). Use the manual TC override — expand the queue row's caret, click the pencil icon on the **Applied TC** line — to set a custom timecode for that job.

## My NLE doesn't see the correct date or timecode

Make sure **Fix recording date** and **Timecode from recording time** are both enabled in the settings bar before adding to the queue. Some NLEs (DaVinci Resolve in particular) require a valid `creation_time` to import clips at the right date.

## The join is slow

Speed depends on source and destination disk throughput. Reading from a UHS-I SD card limits reads to around 95 MB/s. Writing to the same USB bus as the card will bottleneck further. For fastest results, read from the card and write to an internal SSD.

## A red seal appeared after joining

The output failed Conjoyn's verification. This is rare with lossless `-c copy` joins.

1. Re-add the same recording to the queue and try again.
2. Open the source segments in QuickTime Player to confirm they play back correctly.
3. Check that there is enough free space at the destination.

If the red seal persists, please report it with the Console log — click **▶ Console** at the bottom of the window to expand it, then copy the contents.

## An orange SINGLE badge appeared on a clip

An orange badge means an integrity note was detected — most commonly that the clip's embedded date is missing or looks wrong, or that a slow-motion clip was found. Hover the badge for a tooltip explaining the specific issue. The clip can still be joined; the badge is informational.
