# The Queue

## Adding recordings

Select recordings in the list using the checkboxes, or use the **All · Splits · Singles** filter buttons to select a whole category at once. Then click **Add N to Queue**.

Each selected recording becomes one job in the queue.

## Row details

Expand a row's **▶** caret to see:

- **Source TC** — timecode already in the source files. Usually `—` for DJI (no `tmcd` track).
- **Applied TC** — the timecode Conjoyn will stamp, with its origin tag.
- **Output** — the full destination path for this job.

## Settings

The settings bar controls what happens during a join:

| Toggle | What it does |
|--------|-------------|
| **Fix recording date** | Stamps the correct `creation_time` from the filename or SRT |
| **Timecode from recording time** | Adds a `tmcd` track to the output |
| **Stitch telemetry** | Merges `.SRT` sidecars with corrected time offsets |
| **Rename files** | Applies a custom output filename pattern |

Settings are frozen onto each job when it's added to the queue. Changing a toggle after adding has no effect on already-queued jobs.

## Output folder

The **Output** bar shows where finished files will land. If you change the output folder after queuing, Conjoyn prompts you to re-apply the new path to pending (unstarted) jobs. Active and finished jobs are never moved.

## Session restore

Pending (unstarted) jobs are saved when you quit and restored on the next launch. A banner at the top of the queue shows how many were restored and offers **Clear pending** to discard them.
