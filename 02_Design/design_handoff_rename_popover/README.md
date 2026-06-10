# Handoff: Conjoyn — "Rename Joined Files" Popover

## Overview

A rename feature for Conjoyn's output settings bar: a fourth switch, **Rename files**, that —
when turned on — opens an **NSPopover-style panel anchored to that switch** with a token-based
naming-pattern editor and a live before → after preview. Queued join jobs then use the renamed
output filenames (queue rows, console log, and Finder output all reflect the pattern).

## About the Design Files

These files are **design references created in HTML/React** — they show intended look and
behavior, not production code. Recreate this in the target codebase: for Conjoyn that is
**SwiftUI on macOS 14+**, where the panel should be a real `.popover` (NSPopover) attached to
the Rename toggle, using native `TextField`, segmented `Picker`, and `Stepper` controls skinned
to the spec below. The bundled CSS is the authoritative source for colors and metrics.

## Fidelity

**High-fidelity.** Layout, metrics, colors, copy, and interaction rules are final design intent.
The token-insertion and pattern semantics are real and should be implemented as specified.

## Entry Point: the "Rename files" switch

- Lives in the output settings bar as the **fourth** toggle, after *Fix recording date*,
  *Preserve timecode*, *Stitch telemetry*. Standard macOS switch (30×18, solid `--acc2` when on),
  11–12 pt label "Rename files" to its right.
- Switch ON → popover opens, anchored to (centered above) the switch, arrow pointing down at it.
- Switch OFF, or the popover's ✕ close button → popover closes. Closing via ✕ also turns the
  switch off (renaming disabled). State persists while the app runs: reopening shows the last
  pattern/settings.
- Renaming applies **at Add-to-Queue time**: jobs added while the switch is on get patterned
  names; jobs already in the queue are not retroactively renamed.

## The Popover

### Container
- Width 348 pt; height fits content. Corner radius 11.
- Material: opaque dark HUD — `rgba(45,45,45,0.96)` + background blur (30 px, saturate 160%) —
  i.e. NSPopover with dark vibrancy. Hairline border `rgba(255,255,255,0.16)` (0.5 px),
  shadow `0 14px 38px rgba(0,0,0,0.5)` plus 0.5 px black ring.
- **Arrow**: 12×12 rotated square at bottom center, same fill/border as the panel, pointing at
  the switch. (Free with a real NSPopover.)
- Title row: centered "Rename Joined Files", 12 pt semibold, hairline bottom border; 17 pt
  circular ✕ button at top-right (`rgba(255,255,255,0.10)` fill, hover 0.18).

### Form layout (macOS label-column form)
Grid: 62 pt right-aligned label column + flexible control column; 10 pt column gap, 11 pt row
gap, 12–14 pt padding. Labels 12 pt `--txt-2`, with trailing colon: `Preset:` `Pattern:`
`Counter:` `Preview:`.

### Row 1 — Preset
Three chip buttons (11 pt, radius 5, `rgba(255,255,255,0.10)` fill + hairline top inner
highlight; selected = solid `--acc2`, white text):

| Preset | Pattern |
|---|---|
| Original + date | `{name}_{date}_joined` (default) |
| Date + counter | `{date}_flight_{###}` |
| Date + time | `{date}_{time}` |

A preset is shown "selected" when the pattern field exactly equals its pattern — editing the
field deselects all presets automatically.

### Row 2 — Pattern
- Monospace text field (12 pt, radius 6, `rgba(0,0,0,0.30)` fill, 1 px `--line-strong` border).
  Focus: accent border + 3 px outer focus ring at 30 % `--acc2`.
- Below it, four **token pills** (NSTokenField-style): monospace 10.5 pt, radius 9, fill 20 %
  `--acc2`, text `--acc1`; hover 32 %. Clicking inserts the token **at the field's caret**
  (replacing any selection), then restores focus + caret after the inserted token:
  `{name}` (first clip name) · `{date}` (recording date) · `{time}` (start time) · `{###}` (counter).

### Row 3 — Counter
- "Start at" numeric field (52 pt wide, 0–999, default 1) and "Digits" segmented control
  (2 | 3 | 4, default 3).
- The whole row (incl. its label) dims to 45 % opacity and disables unless the pattern
  contains `{###}`.

### Row 4 — Preview
- Inset well (radius 6, `rgba(0,0,0,0.28)` fill, hairline border) listing up to the first **3
  currently-selected recordings**, monospace 10.5 pt, two lines each:
  - line 1: original first-segment name dimmed (`--txt-3`) + " →"
  - line 2: resulting filename in `--acc1`, indented 12 pt, middle-truncating if long
- Live — updates on every keystroke/setting change.
- Empty selection → single dimmed line "Select recordings to preview".

## Pattern semantics

For recording *r* at batch index *i* (0-based, in Add-to-Queue order):

1. Replace tokens: `{name}` → first segment's basename (e.g. `DJI_0042`); `{date}` → recording
   date as `YYYY-MM-DD`; `{time}` → start time with `:` → `.` (e.g. `09.14.02`);
   `{###}` → `start + i`, zero-padded to the digits setting.
2. Strip filesystem-illegal characters (`\ / : * ? " < > |` → `-`), trim whitespace.
3. If the result is empty, fall back to `{name}`. Append the container extension (`.MP4`).
4. Telemetry sidecars get the same stem with `.SRT`.

Counter state (`start`, batch index) belongs to one Add-to-Queue batch — a second batch
restarts at `start` unless product decides otherwise (open question worth confirming).

## Design tokens

See `rename-popover.css` — it carries the full extracted styles plus the token variables the
popover depends on (`--acc1 #FFB23E`, `--acc2 #F0622A`, neutral charcoal text/line scale,
SF Pro / SF Mono).

## Files

| File | Contents |
|---|---|
| `rename.jsx` | Reference React implementation: popover markup, token insertion, pattern engine (`cjApplyPattern`), presets, counter gating, live preview |
| `rename-popover.css` | Extracted authoritative styles + required token variables |

Context: this panel belongs to the Conjoyn main-window design (see the separate
`design_handoff_conjoyn` package). In the prototype the popover is rendered by the output bar —
the anchor wrapper is `.rename-anchor` around the Rename switch; jobs pick up names via
`cjApplyPattern` at Add-to-Queue time.
