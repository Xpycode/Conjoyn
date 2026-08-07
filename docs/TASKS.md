# Tasks

Checkbox tracking for the active sprint. Execution detail (target files, success criteria,
backpressure) lives in **`IMPLEMENTATION_PLAN-gopro.md`** — this file only tracks progress.

## Current Sprint — GoPro waves G0–G2 (persistence safety net + parse + probe)

- [ ] **G0.1** Check in a 1.0.4-shaped `queue.json` fixture + decode test (must pass against today's model)
- [ ] **G0.2** Hand-write `DJIClip` `CodingKeys` + `init(from:)` with `decodeIfPresent`
- [ ] **G0.3** Tolerant decode for `VerificationCheck.Kind` (unknown-case fallback)
- [ ] **G1.1** `CameraFamily` + tail-anchored GoPro `GX`/`GH` regex in `DJIFilenameParser`
- [ ] **G1.2** Parser acceptance tests (incl. all 71 corpus filenames)
- [ ] **G1.3** Thread family + `recordingNumber` through `DJIClip` and folder discovery
- [ ] **G2.1** Retain gpmd stream index, codec tag and start timecode from ffprobe

> **G0 blocks everything.** No model gains a field until G0.2 is merged — a non-Optional field on
> `DJIClip` wipes a shipped user's entire persisted queue.

## Backlog (later waves — see the plan)

- **G3** Grouping: composite bucket key, family-dispatched `continues()`, corpus fixtures, incomplete-set flag
- **G4** Join: gpmd `-map` index in the arg builder, join-time index resolution, real seam-slice integration test
- **G5** Verification: gpmd in Tier 0/1 parity checks and the Tier 2 hash
- **G6** Watch-folder: relative complete-set rule (no absolute split constant for GoPro)
- **G7** UI copy: camera-neutral empty state, no file-size figure
- **G8** Real-footage validation (GH H.264 probe — *user capture owed*; full real join) + docs close-out
