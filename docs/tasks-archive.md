# Tasks Archive

Completed sprint tasks, newest first. Execution detail lives in the plan the task came from;
rationale lives in `decisions.md`. Sprint checkboxes are in `TASKS.md`.

**Total archived:** 6 · **Last updated:** 2026-08-07

## Completed

### Wave G1 — GoPro filename parsing (`IMPLEMENTATION_PLAN-gopro.md`)

- [x] **G1.1** `CameraFamily` + tail-anchored GoPro `GX`/`GH` regex in `DJIFilenameParser` (2026-08-07)
- [x] **G1.2** Parser acceptance tests, incl. all 71 corpus filenames (2026-08-07)
- [x] **G1.3** Thread family + `recordingNumber` through `DJIClip` and folder discovery — folder scan
      needed no code change; added the encoder-completeness guard (2026-08-07)

### Wave G0 — persistence safety net (`IMPLEMENTATION_PLAN-gopro.md`)

- [x] **G0.1** Check in a 1.0.4-shaped `queue.json` fixture + decode test (must pass against today's model) (2026-08-07)
- [x] **G0.2** Hand-write `DJIClip` `CodingKeys` + `init(from:)` with `decodeIfPresent` (2026-08-07)
- [x] **G0.3** Tolerant decode for `VerificationCheck.Kind` (unknown-case fallback) (2026-08-07)
