# Conjoyn — Rename Files + Timecode Disclosure Spec

> Companion to `specs/dji-auto-stitcher.md`. Covers two output-bar/queue UX additions that
> arrived together in the 2026-06-10 design handoff (`02_Design/design_handoff_rename_popover/`)
> and the user's timecode-framing feedback. Both touch the **output settings bar** and the
> **queue rows**. Decisions logged in `docs/decisions.md` (2026-06-10).

## Overview

Two related changes:

1. **Rename Joined Files** — a fourth output-bar toggle that opens an NSPopover token-pattern
   editor (`{name}` `{date}` `{time}` `{###}`) with presets, a counter, and a live before→after
   preview. Queued jobs adopt the patterned output name (queue rows, console, Finder output, and
   the `.SRT` sidecar all follow). **New feature.**

2. **Timecode-from-recording-time disclosure** — rename the misleading "Preserve timecode" toggle
   to **"Timecode from recording time,"** and surface, per job in the queue row, the difference
   between DJI's (meaningless) **source TC** and the **applied TC** we derive, with its origin and
   a slow-motion note. **No engine change** — the engine already derives TC from the resolved
   recording-start wall-clock (see `docs/decisions.md`, 2026-06-09 "date+timecode stamp model").
   This is honesty/relabel + exposing values the resolver already computes.

---

## Part 1 — Rename Joined Files

### User stories
- As a user dumping a card, I want joined files named by a **pattern I control** (date, original
  name, a counter) so my exports land already-named for my edit/library, not as `DJI_0042_joined`.
- As a user, I want a **live preview** of the resulting names for the recordings I've selected,
  updating as I type, so I never queue a batch with a wrong pattern.
- As a user, I want the renamed name to carry through **everywhere** — queue row, console log,
  the output `.MP4`, and its `.SRT` sidecar — so nothing is left under the old name.

### Acceptance criteria

**Entry point & lifecycle**
- [ ] Fourth toggle **"Rename files"** in the output settings bar, after *Fix recording date*,
      *Timecode from recording time*, *Stitch telemetry*. Standard 30×18 switch, `--acc2` when on.
- [ ] Switch ON → NSPopover opens, anchored above the switch, arrow pointing down at it.
- [ ] Switch OFF, or popover ✕ → popover closes; ✕ also turns the switch OFF (renaming disabled).
- [ ] State persists **for the app session only** (reopening shows the last pattern/counter/digits).
      Not written to disk in v1.
- [ ] Renaming applies **at Add-to-Queue time**. Jobs already queued are **not** retroactively
      renamed.

**Popover form**
- [ ] Container per handoff: 348 pt wide, dark HUD material, title "Rename Joined Files" + ✕.
- [ ] **Preset chips:** `Original + date` = `{name}_{date}_joined` (default), `Date + counter` =
      `{date}_flight_{###}`, `Date + time` = `{date}_{time}`. A chip shows selected when the
      pattern field exactly equals its pattern; editing the field deselects all chips.
- [ ] **Pattern field:** monospace `TextField`. Four token pills below it (`{name}` `{date}`
      `{time}` `{###}`); clicking a pill inserts the token **at the caret** (replacing any
      selection) and restores focus + caret position after the inserted token.
- [ ] **Counter row:** "Start at" numeric `Stepper`/field (0–999, default 1) + "Digits" segmented
      `Picker` (2 | 3 | 4, default 3). The whole row dims to ~45 % and disables unless the pattern
      contains `{###}`.
- [ ] **Preview well:** up to the first **3 currently-selected recordings**, two lines each
      (original first-segment name dimmed `→`, then resulting name in `--acc1`, middle-truncating).
      Empty selection → single dimmed line "Select recordings to preview". Live on every keystroke.

**Pattern semantics** (recording *r* at 0-based batch index *i*, in Add-to-Queue order)
- [ ] Token replace: `{name}` → first segment basename without extension (e.g.
      `DJI_20260521195303_0009_D`); `{date}` → recording date `YYYY-MM-DD`; `{time}` → start time
      with `:`→`.` (e.g. `19.53.03`); `{###}` → `start + i` zero-padded to the digits setting.
      Date and time come from the **same resolved recording-start wall-clock** the TC/date stamp
      uses (so rename and metadata never disagree).
- [ ] Strip filesystem-illegal chars (`\ / : * ? " < > |` → `-`), trim whitespace.
- [ ] If the result is empty, fall back to `{name}`. Append the container extension (`.MP4`/`.mp4`
      matching source case is acceptable; default `.MP4`).
- [ ] The telemetry sidecar gets the **same stem** with `.SRT`.

**Counter scope** *(product decision 2026-06-10)*
- [ ] The counter **restarts at "Start at" for each Add-to-Queue batch**. A second batch counts
      from `start` again (it does not continue from the previous batch).

**Collision handling** *(product decision 2026-06-10)*
- [ ] If two resolved output names collide — within the same batch, against jobs already in the
      queue, **or** against a file already present in the destination — **auto-suffix** `_2`,
      `_3`, … to the stem until unique. The `.SRT` sidecar follows the same suffixed stem.
- [ ] The final (possibly suffixed) name is what appears in the preview/queue, so the user sees the
      real result, not the pre-collision name. *(If cheap: reflect the suffix live in the preview.)*

**Interaction with the default namer**
- [ ] When Rename is OFF, behavior is unchanged (existing default naming).
- [ ] Note: rename **bypasses** the default output-namer, so it side-steps the known doubled
      camera-variant-suffix bug (`…_0009_D_D.mp4`, PROJECT_STATE 6.x). The default-namer fix is
      tracked separately and is **not** in scope here.

---

## Part 2 — Timecode-from-recording-time disclosure

### Rationale
The design bar's **"Preserve timecode"** label is wrong: DJI's source `tmcd` is almost always
`00:00:00:00`, so there is nothing to preserve. The engine already **derives** the output start
timecode from a resolved recording-start wall-clock (priority chain: SRT first-cue → filename
datetime → sane embedded `creation_time` → filesystem date → manual override), and stamps the
**same** instant as the calendar date. The UI should say what actually happens and **show** the
transformation rather than implying preservation. (Engine basis: `docs/decisions.md` 2026-06-09.)

### Acceptance criteria

**Relabel**
- [ ] Output-bar toggle **"Preserve timecode" → "Timecode from recording time"** (short form
      "TC from recording time" acceptable if width-constrained). Default ON, unchanged behavior.
- [ ] The toggle's bound setting stays `preserveTimecode` internally (no engine rename required) —
      this is a label/wording change. *(Optional later: rename the symbol for clarity.)*

**Per-job disclosure in the queue row** *(product decision 2026-06-10: per-job, not on the toggle)*
- [ ] Each queued job row exposes, for that recording:
      - **Source TC:** the segment-1 `tmcd` value (almost always `00:00:00:00`), labeled as the
        camera's original — visibly inert.
      - **Applied TC:** the `HH:MM:SS:FF` we stamp, with an **origin tag**: *from SRT cue* /
        *from filename* / *from file date* / *manual* — matching which resolver source won.
      - The **frame rate** used for the `FF` component (e.g. `· 25 fps`).
- [ ] Presentation is a **disclosure caret on the row** *(product decision 2026-06-10)*: the row
      stays single-line by default; clicking the caret expands a small inline panel showing Source
      TC, Applied TC + origin, frame rate, and (when relevant) the slow-mo note. Keeps the queue
      compact; detail on demand. The caret's collapsed/expanded state is per-row, session-only.
- [ ] When *Timecode from recording time* is OFF, the row shows the source TC is passed through
      (or "—" if none) and no Applied TC.

**Slow-motion handling note**
- [ ] When a group contains a slow-motion recording (container/playback duration ≫ real elapsed;
      see `slowmo-dual-timebase`), the row (or its disclosure) carries a one-line note:
      *“Slow-mo: timecode starts at the real recording time and advances at the file's playback
      rate (NN fps).”*
- [ ] Behavioral truth to preserve in copy: the **start instant** is the real wall-clock and is
      **unaffected** by slow-mo; only the frame-rate tag follows the container playback fps, so the
      TC stays in sync with the joined video's own timeline. (No engine change — document, don't
      “fix.” The SRT stitcher's playback-time offsets are already correct.)

**Data plumbing (engine-side, minimal)**
- [ ] Surface the resolver's outputs to the ViewModel/queue-row model so the row can render them:
      resolved `Date`, the **winning source** of that date (enum: srtCue / filename / creationTime
      / filesystem / manual), the source `tmcd` string, the applied `HH:MM:SS:FF`, the frame rate,
      and an `isSlowMotion` flag. Most already exist in `RecordingStartResolver` /
      `JoinMetadata` / the grouping pass — this is exposing, not recomputing.

---

## Out of scope (v1)
- Persisting rename/TC-disclosure settings to disk across launches.
- Renaming files already on disk / batch re-rename of past exports.
- Per-recording manual name override inside the queue (pattern is batch-level).
- Fixing the default-namer doubled-suffix bug (tracked separately).
- Renaming the `preserveTimecode` symbol throughout the codebase (cosmetic, later).

## Implementation notes / wiring (disposable plan)
1. **Model:** add `RenameOptions { pattern, start, digits }` (+ `renameEnabled`) and a
   `RenamePatternEngine.apply(recording:index:options:) -> stem` to `ConversionSettings` /
   the enqueue path. Port the JS `cjApplyPattern` semantics 1:1 (token split/join, illegal-char
   strip, fallback, extension). Add the collision-suffix loop at enqueue against {batch ∪ queue ∪
   destination dir listing}.
2. **Enqueue:** the output-name is decided **once, at Add-to-Queue**, and frozen onto the job
   (so later queue mutations don't shift counters). Sidecar `.SRT` name derives from the frozen stem.
3. **UI (SwiftUI):** real `.popover` on the Rename `Toggle`; `TextField` + token `Button`s with
   caret-insertion via the field's selection; segmented `Picker` for digits; `Stepper` for start;
   preview list bound to current selection. Reskin per `rename-popover.css` tokens
   (`--acc1 #FFB23E`, `--acc2 #F0622A`).
4. **TC disclosure:** relabel the toggle; extend the queue-row model with the resolver outputs;
   render the Source/Applied/origin (+ slow-mo caption) line in the row. No export-path change.
5. **Tests:** pattern-engine unit tests (each token, counter padding, illegal chars, empty→fallback,
   per-batch restart, collision suffixing); a resolver-passthrough test asserting the row model
   carries the right origin + applied TC for SRT-cue / filename / slow-mo fixtures.
