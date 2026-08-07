# Tasks

Checkbox tracking for the active sprint. Execution detail (target files, success criteria,
backpressure) lives in **`IMPLEMENTATION_PLAN-gopro.md`** — this file only tracks progress.

## Current Sprint — GoPro wave G4 (join with telemetry)

*(G0.1–G0.3, G1.1–G1.3 and G2.1 completed 2026-08-07 → `tasks-archive.md`.)*

Taken before G3 on purpose: the plan's vertical slice is **G1 → G2.1 → G4.1/G4.3**, proving a real
GoPro seam joins with telemetry intact *before* grouping/gate/copy get built on top. That retires the
two highest technical risks — whether `-map 0:<i>` works against the concat demuxer at all, and
whether the index is resolved from the right file.

- [ ] **G4.1** `buildMergeArguments` learns a gpmd index (`nil` ⇒ arg vector byte-identical to 1.0.4)
- [ ] **G4.2** Resolve the index at join time + refuse mixed layouts
- [ ] **G4.3** Real seam-slice fixtures + end-to-end join test (cut from 6347 or 6345, **not** 6338)

> **Wave G2 is CLOSED (2026-08-07)** — suite **531 / 0 fail**. The gpmd index genuinely moves
> (**3** with audio, **2** without, **2** on a remux where ffmpeg put `tmcd` *after* gpmd), so G4.1
> must use the probed value and select on `codec_tag_string` — never `codec_name` (tmcd's is `null`),
> never position. `check(_:)` untouched, so join verdicts are unchanged. Two corrections logged in
> the plan: the format-tags fallback was dead until `-show_format` was added, and `startTimecode`
> **does** change DJI's persisted shape (DJI has a `tmcd` track) — additive and safe both ways, but
> not the no-op the task assumed.

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
- **G5** Verification: gpmd in Tier 0/1 parity checks and the Tier 2 hash
- **G6** Watch-folder: relative complete-set rule (no absolute split constant for GoPro)
- **G7** UI copy: camera-neutral empty state, no file-size figure
- **G8** Real-footage validation (GH H.264 probe — *user capture owed*; full real join) + docs close-out
</content>
