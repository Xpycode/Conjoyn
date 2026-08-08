# Tasks

Checkbox tracking for the active sprint. Execution detail (target files, success criteria,
backpressure) lives in **`IMPLEMENTATION_PLAN-gopro.md`** — this file only tracks progress.

## Current Sprint — GoPro wave G5 (verification)

*(G0.1–G0.3, G1.1–G1.3, G2.1, G3.1–G3.4 and G4.1–G4.3 completed → `tasks-archive.md`.)*

Wave G5 is next: it was equally unblocked all along (the plan's serial spine is G0 → G2 → G4 → G5),
and with G3 closed the critical path to the **G8.2 final gate** is clear — GoPro chapters now group,
so a real recording can reach the join path from the UI.

> **Wave G3 is CLOSED (2026-08-08)** — suite **561 / 0 fail** (542 → 561). GoPro chapters group on
> **timecode continuity**, not DJI's size-cap + wall-clock rule: the cap isn't a constant and
> recording 6338's two chapters share an identical `creation_time`, so the DJI rule would have
> refused a real, valid chain. `continuesDJI` is the shipped body moved verbatim — DJI verdicts are
> untouched, and the composite bucket key `family|variantSuffix|recordingNumber` is a 1:1 relabel
> for DJI (whose `recordingNumber` is always nil). All **71** measured corpus files are pinned as
> fixtures: 6 multi-chapter groups + 51 singles, transcribed by script and re-verified field-by-field
> against the CSV (781 comparisons, 0 mismatches). Three things worth carrying forward:
> (a) the 1 ms continuity slack was re-measured against the source production actually feeds it —
> **AVFoundation's `CMTime`, not ffprobe's `format.duration`** that the corpus CSV records; they
> agree exactly on all 13 non-final chapters, but ffprobe's own format-vs-video durations differ by
> up to 0.667 ms, so measuring the wrong clock would have eaten most of the budget while every unit
> test still passed. (b) timecode→seconds divides by the **actual** fps, never the rounded one —
> invisible at 25/50/100/200 fps, silently wrong on the NTSC rates a Hero 11 can also shoot.
> (c) the incomplete-set flag **warns but does not block the join** — a user decision that overturns
> the spec's "not joined" line; see `decisions.md` (2026-08-08).

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
