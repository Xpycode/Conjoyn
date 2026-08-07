# Tasks

Checkbox tracking for the active sprint. Execution detail (target files, success criteria,
backpressure) lives in **`IMPLEMENTATION_PLAN-gopro.md`** — this file only tracks progress.

## Current Sprint — GoPro wave G3 (grouping)

*(G0.1–G0.3, G1.1–G1.3, G2.1 and G4.1–G4.3 completed 2026-08-07 → `tasks-archive.md`.)*

**G5 (verification) is equally unblocked** — the plan's serial spine reads G0 → G2 → G4 → G5. G3 is
taken first because it is on the critical path to the **G8.2 final gate**: until GoPro chapters
actually group, a real recording can't reach the join path from the UI at all, so the end-to-end
proof G4 just established can't be exercised on real footage. G5 hardens a path that already works.

- [ ] **G3.1** Extend `SegmentMeta` + composite bucket key (`family|variantSuffix|recordingNumber`)
- [ ] **G3.2** Family-dispatched `continues()` — timecode continuity, no size-cap gate
- [ ] **G3.3** Corpus grouping fixtures (6 multi-chapter groups + 51 singles)
- [ ] **G3.4** Incomplete-set flag — **new visible UI chip, needs `36_ui-changes-protocol.md` sign-off first**

> **Wave G4 is CLOSED (2026-08-07)** — suite **542 / 0 fail**. Both headline risks are retired on
> real footage, not unit tests: **`-map 0:<i>` does work against the concat demuxer**, and gpmd
> survives a genuine chapter seam byte-exact (7,084 + 6,916 = 14,000 bytes; video and audio match to
> the byte too). The end-to-end test was verified by **falsification** — flipping the policy to
> `.drop` fails it with 0 gpmd streams found — so it detects the mechanism rather than merely
> passing. Two things worth carrying forward: (a) **finding C reproduced first-hand** — `-map 0` on a
> GoPro source errors on the tmcd track and leaves a **zero-byte output**, which is *why* streams are
> mapped explicitly; (b) the seam fixtures are **remux-shaped (gpmd at index 2)**, not
> camera-original-shaped (index 3), because ffmpeg cannot copy GoPro's source tmcd and regenerates it
> after gpmd. Index 3 is covered by unit tests and the join-time probe but **not** end-to-end — G8.2
> closes that. Also open: a GoPro join now probes each segment **twice** (param guard + telemetry
> index); correct but wasteful, worth folding together only if join latency becomes noticeable.

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

- **G5** Verification: gpmd in Tier 0/1 parity checks and the Tier 2 hash (**unblocked** — G4 closed)
- **G6** Watch-folder: relative complete-set rule (no absolute split constant for GoPro)
- **G7** UI copy: camera-neutral empty state, no file-size figure
- **G8** Real-footage validation (GH H.264 probe — *user capture owed*; full real join) + docs close-out
</content>
