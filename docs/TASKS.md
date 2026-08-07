# Tasks

Checkbox tracking for the active sprint. Execution detail (target files, success criteria,
backpressure) lives in **`IMPLEMENTATION_PLAN-gopro.md`** — this file only tracks progress.

## Current Sprint — GoPro waves G1–G2 (parse + probe)

*(G0.1–G0.3 and G1.1–G1.3 completed 2026-08-07 → `tasks-archive.md`.)*

- [ ] **G2.1** Retain gpmd stream index, codec tag and start timecode from ffprobe

> **Wave G1 is CLOSED (2026-08-07)** — parser, tests and model threading merged. Suite **525 / 0
> fail**. `DJIClip.encode(to:)` is now **hand-written** (a non-Optional `family` would otherwise
> have written `"family":"dji"` into every DJI clip and changed the shape 1.0.4 wrote), so the
> G0 standing rule now has an **encoder half**: a new field must be added to `CodingKeys`, decoded
> with `decodeIfPresent` **and written in `encode(to:)`**. `CodingKeys` is `CaseIterable` and
> `testEncoderWritesEveryCodingKeyForAFullyPopulatedClip` pins that — verified by reproduction.

> ~~**G0 blocks everything.**~~ **Wave G0 is CLOSED (2026-08-07)** — the net is in place and the
> hazard was reproduced against it before the fix (a probe `var` on `DJIClip` failed all 10 G0.1
> tests with `keyNotFound` at `[0].clips[0]`). Suite **512 / 0 fail**. New `DJIClip` fields must
> still be added to `CodingKeys` **and** decoded with `decodeIfPresent`; `QueuePersistenceCompatTests`
> going red is stop-the-line, never a test to update.

## Backlog (later waves — see the plan)

- **G3** Grouping: composite bucket key, family-dispatched `continues()`, corpus fixtures, incomplete-set flag
- **G4** Join: gpmd `-map` index in the arg builder, join-time index resolution, real seam-slice integration test
- **G5** Verification: gpmd in Tier 0/1 parity checks and the Tier 2 hash
- **G6** Watch-folder: relative complete-set rule (no absolute split constant for GoPro)
- **G7** UI copy: camera-neutral empty state, no file-size figure
- **G8** Real-footage validation (GH H.264 probe — *user capture owed*; full real join) + docs close-out
