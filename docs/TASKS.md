# Tasks

Checkbox tracking for the active sprint. Execution detail (target files, success criteria,
backpressure) lives in **`IMPLEMENTATION_PLAN-gopro.md`** — this file only tracks progress.

## Current Sprint — GoPro wave G8 (real-footage validation & close-out)

*(G0.1–G0.3, G1.1–G1.3, G2.1, G3.1–G3.4, G4.1–G4.3, G5.1–G5.2, G6.1 and G7.1 completed →
`tasks-archive.md`.)*

- [x] **G8.2** — real full join of a GoPro group, end-to-end through the app
- [x] **G8.4** — *(added mid-wave, from what G8.2 found)* preserve GoPro's frame-accurate start timecode
- [x] **G8.3** — suite green, decisions logged, spec → Implemented, state + session log
- [ ] **G8.1** — GH (H.264) probe · **blocked on capture**: one ~30 s Hero 11 clip shot with video
      compression set to H.264. No `GH…` file exists anywhere on V26 or the boot disk (checked
      2026-08-09); mediaingest preserves the GoPro stem, so renaming is not hiding one.

> **Wave G8 is CLOSED except G8.1 (2026-08-09)** — suite **618 / 0 fail** (605 → 618).
>
> **G8.2 passed on recording 6349** (2 chapters, 12.57 GB in / 13.49 GB out). Proven independently
> of the app's own verdict, against hashes taken **before** the app ran: video `d69ab68d…`
> (13,416,612,803 B), audio `3726bf24…` (57,354,105 B) and telemetry `d28b73bd…` (16,106,180 B) all
> **byte-identical** to the concatenated sources. Originals untouched (size, mtime and inode
> unchanged). Seal green at both tiers. The output stream order is `v,a,gpmd,tmcd` against the
> source's `v,a,tmcd,gpmd` — the reorder G5 builds its Tier-2 map vector twice for, confirmed here
> on a camera original for the first time rather than on a remux-shaped fixture.
>
> **G8.2 also found a real defect, which became G8.4:** the joined output's `tmcd` was re-derived
> from the second-truncated `creation_time`, discarding the camera's frame offset (`20:14:42:00` vs
> the camera's `20:14:42:06`). Correct for DJI, whose `tmcd` is garbage; wrong for GoPro, whose
> `tmcd` the app already trusts as its **sole** chapter-chaining signal. The green seal could not
> catch it — the write-back check compares the output to what the join stamped, i.e. self-consistency
> rather than fidelity to the camera. Fixed, falsified on all three links, and confirmed on real
> originals: `GX014623` @200 fps → `13:44:07:127`, `GX014637` @100 fps → `15:46:57:71`. → `decisions.md`.

> **Wave G7 is CLOSED (2026-08-09)** — copy-only, suite unchanged at **605 / 0 fail**. The empty
> state no longer names a file size at all ("Long recordings get split into several files on the
> card…"), because no camera splits at a printable constant — DJI's ~3.9 GB and GoPro's ~10.7 GiB
> (which itself moves with fps) have no shared number. The scan-found-nothing message names both
> families rather than calling GoPro files unrecognised, keeping the 2026-08-06 why-is-it-empty fix.
>
> **The wave closed wider than it was written**, on user instruction after a sweep: the task named
> two sites, but camera-specific copy also lived in `WatchFoldersPanel.swift:62` and — far larger —
> the **in-app Help book**, 18 DJI mentions across 8 markdown topics. That rewrite is where the value
> was: Help now states GoPro's `GX`/`GH` chaptered naming and that `GOPR…`/`GP01…` aren't recognised,
> that GoPro chapters chain on **timecode continuity** while DJI chains on cap+clock, that GoPro's
> telemetry rides **inside** the file (carried through the join and verified at both tiers) rather
> than in an `.SRT`, and that GoPro *does* carry a source `tmcd` where DJI carries none.
>
> **Two pre-existing factual errors surfaced and were corrected rather than copied forward:** the
> Help documented the date chain as filename-then-SRT when `RecordingStartResolver.swift:103-107`
> tries **SRT first** (checked in code, not assumed), and the Roadmap still advertised
> **watch-folder ingest as "Planned"** though the 1.0.3 release notes announce it as shipped.
> `RecordingsList.swift:266` (`+ N telemetry .SRT`) needed **no** change — already guarded by
> `srtCount > 0`, so GoPro never renders it. Backpressure is by eye; no test asserts these strings.

> **Wave G6 is CLOSED (2026-08-09)** — suite **605 / 0 fail** (590 → 605). GoPro groups no longer
> consult the absolute 3.9 GB `splitThreshold`, which is wrong in both directions for a camera whose
> cap moves with fps: a chapter is final when it is below **0.94×** the smallest preceding chapter of
> the same recording. DJI delegates **verbatim** to the untouched 4-argument rule, so its verdicts are
> unchanged by construction — the existing `CompleteSetGateTests` needed **zero edits**, which is the
> evidence.
>
> Both constants were measured on the real 71-file corpus and both sit in genuinely empty bands.
> The ratio band is the tight one: finals run **0.0762–0.8850** (tightest 6348 ch03) against
> non-finals at **0.99989–1.00015** — which is also why the comparison must be a strict `<`, since a
> non-final ratio can exceed 1.0 when a later chapter is marginally larger than the smallest earlier
> one. The floor band is wide: largest genuine single-chapter recording **7.66 GB**, smallest
> cap-filled chapter **11.4976 GB**.
>
> **The plan's text was wrong about the no-reference case and following it would have regressed the
> shipped app.** It said "with only one member and no reference, the quiet window alone decides" —
> but mid-copy a 4-chapter recording *is* a one-member group, so an 11.5 GB chapter 01 would have
> been joined alone after 45 s of quiet, leaving the rest orphaned. Today's absolute rule blocks that
> correctly. A **9.5 GB no-reference floor** (user decision) keeps it correct with a GoPro-appropriate
> number. Also hardened past the task text: non-positive preceding sizes are filtered before `min()`,
> so a stray `0` errs toward "wait" rather than "join" — defensive only, since `isSettled` rejects an
> unsampled clip at Gate 1 first. Detail in `decisions.md` (2026-08-09).
>
> Verified by falsification in **both** directions: ratio → 0.5 fails the three tightest finals;
> floor → 20 GB fails all six recordings at **chapter 1/N**, the exact premature-join regression the
> floor exists to prevent.

> **Wave G5 is CLOSED (2026-08-09)** — suite **590 / 0 fail** (561 → 590). Verification now checks
> GoPro's in-container `gpmd` telemetry at both depths: packet-count/byte parity in the Tier 0/1 fast
> pass (G5.1) and byte-exact MD5 in the Tier 2 escalation (G5.2). Before this, a join could lose or
> corrupt telemetry and still seal green at every tier.
>
> The telemetry stream is selected by **absolute index on both sides, never `d:0`** (decision 4) —
> `d:0` resolves to whichever data stream is first, which on a camera original is `tmcd`, so the
> shortcut would have produced a *passing* check that verified the timecode track. Source and output
> indices are resolved separately, and the Tier 2 map-arg vector is built **twice**, because the join
> re-orders streams; one shared vector would hash two different streams and compare them. A `nil`
> index — every DJI job — reproduces the shipped argument vector exactly, pinned by exact-vector
> assertions rather than a fuzzy check.
>
> **A cold review of the wave found four more silent-pass routes, all closed before merge** — worth
> reading as a set, because each one let a GoPro join lose telemetry and still seal green:
> the output index was **derived** (`hasAudio ? 2 : 1`) from the join's arg order rather than probed,
> which `-map 0:a?` breaks on a two-audio-track source (it maps *all* audio) — and the test for it
> merely restated the formula; a GoPro job whose `streamInfo` probe hiccupped (`try?` at discovery)
> verified with **no telemetry check at all** while still joining with telemetry; `mapStatus` let a
> passing Tier-2 hash **forgive** the telemetry verdict, which is unsound precisely when gpmd is
> missing and Tier 2 falls back to hashing v/a only; and that carve-out then read only the **first**
> `.gpmdParity` check when the telemetry stream emits **two** (count and bytes), laundering a
> bytes-only failure — the exact shape corruption takes when packet count survives but payload
> doesn't. Detail in `decisions.md` (2026-08-09).
>
> Three things worth carrying forward:
> (a) `-f streamhash` numbers its lines by **local position within that invocation's own `-map`
> selection**, not by absolute source index, so positional pairing in `classifyHashLines` stays
> correct with a third stream. The opposite assumption was tested against real ffmpeg and disproved
> rather than reasoned about.
> (b) The new `Kind` case is **`gpmdParity`, not `telemetryParity`** — G0.3's
> `QueuePersistenceCompatTests` already uses the literal `"telemetryParity"` as its unknown-kind
> fixture, so that name would have turned a protected test's placeholder into a real decodable case.
> (c) The positive fixture test **cannot catch a shared-vector regression on its own**: in the G4.3
> fixtures source and output gpmd both land at index 2, so a wrong index coincidentally selects the
> right stream. The unit tests and the negative wrong-stream test carry that coverage. A fixture
> whose source and output indices differ would close the gap.

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

- **G8** Real-footage validation (GH H.264 probe — *user capture owed*; full real join) + docs close-out
</content>
