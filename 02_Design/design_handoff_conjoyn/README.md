# Handoff: Conjoyn — macOS App Main Window

## Overview

Conjoyn is a native macOS app (macOS 14+, SwiftUI, Apple Silicon) that losslessly re-joins
action/drone-camera recordings that were split at the ~4 GB memory-card file limit. It scans a
source folder, groups clips into recordings, joins selected sets without re-encoding, repairs
recording-date/timecode metadata, and stitches telemetry (.SRT) sidecars.

This package documents the design of the app's **single primary window** across its five core
states: Empty → Scanning → Groups loaded → Queue running → Done.

## About the Design Files

The files in this bundle are **design references created in HTML/React** — an interactive
prototype showing intended look and behavior. They are **not production code**. The task is to
**recreate this design in the target codebase** — for Conjoyn that means **SwiftUI on macOS 14+**
— using native AppKit/SwiftUI controls and conventions wherever they exist. Where this document
specifies custom colors/metrics, treat the system control as the baseline and the spec as the
skin. If your environment differs (e.g. Electron/React), keep the same metrics and tokens.

Open `Conjoyn Prototype.html` in a browser to click through the real flow. A "Jump to state"
pill row below the window jumps directly to each of the five states.

## Fidelity

**High-fidelity.** Colors, typography, spacing, control styling, copy, and interaction flows are
final design intent and should be matched closely. The only intentionally-fake parts:
- Video thumbnails are striped placeholders → use real AVAsset-generated thumbnails.
- Scan/join progress is simulated → wire to the real pipeline.
- One scripted failure (rec-12, "telemetry sidecar unreadable") exists purely to demo the
  failed/retry state.

## Window

- 1240 × 800 pt default, resizable; content min ~1000 × 640.
- Standard macOS window with traffic lights; the titlebar is a unified custom toolbar
  (like Final Cut Pro): traffic lights · app title + tagline · (flex) · source well · Scan button.
- Dark appearance only (pro-video tool). Window corner radius/shadow: system default.

## Layout (top → bottom, vertical flow mirrors the user flow)

1. **Titlebar / source bar** — 52 pt tall, bg `--titlebar`, 1 px black bottom border.
   - App title: 13 pt bold "Conjoyn", tagline 11 pt `--txt-3` "Split recordings, made whole".
   - Source well: 30 pt tall, radius 7, bg `rgba(0,0,0,0.30)`, 1 px border `--line`,
     min-width 320. Shows SD-card icon + monospace-numerals path
     (`/Volumes/DJI_MAVIC4/DCIM/100MEDIA`) or placeholder "No source selected" in `--txt-3`.
     Small "Choose…" button (height 20) inside its right edge.
   - "Scan" button (standard button, scan-frame icon). Label becomes "Scanning…" + disabled while scanning.
2. **Discovered recordings list** (hero region, flex ~5 of remaining height)
   - Section header: 11 pt, 700, uppercase, letter-spacing 0.6, `--txt-3`:
     "DISCOVERED RECORDINGS" + live count "8 of 14 selected · 42 clips on card" (`--txt-2`,
     normal case) + (flex) + segmented control **All | None | Splits**.
   - Scrollable row list (see Row spec below).
3. **Output settings bar** — single 46 pt row, bg `--panel`, 1 px `--line` top+bottom borders:
   "Output" label + destination well (like source well, 26 pt, `~/Movies/Ingest/2026-05-31` +
   "Choose…") + (flex) + three labeled switches: *Fix recording date*, *Preserve timecode*,
   *Stitch telemetry* (all default ON) + primary button "Add N to Queue" ("Add to Queue",
   disabled, when N = 0).
4. **Job queue** (flex ~3) — section header "QUEUE · N jobs", then one row per job.
   Empty placeholder: "No jobs yet — select recordings above and press 'Add to Queue'."
5. **Console** (collapsible, collapsed by default) — header row "› Console · N lines"
   (11 pt, 600, `--txt-3`, click toggles). Expanded: 130 pt log, bg `#151515`, monospace 11 pt,
   line-height 1.65, auto-scrolls to bottom.
6. **Footer bar** — bg `--panel`, 1 px `--line-strong` top border: large primary
   **Start** (or red-tinted **Stop** while running) + overall progress bar (flex) + totals text
   ("Queue empty" / "3 of 8 joined · 0 failed" / green "✓ 8 of 8 joined, 0 failed").

## Recording row spec (the money shot)

Height ≈ 56 pt (9 pt vertical padding), 1 px `--line` bottom border, 12 pt gap, 16 pt side padding:

| Element | Spec |
|---|---|
| Checkbox | 14 pt, radius 3.5; checked = solid `--acc2`, white 1.8 pt checkmark |
| Disclosure chevron | 18 pt hit area, only on Split rows (hidden-but-space-reserved on singles); rotates 90° when open |
| Thumbnail | 16:9, 38 pt tall, radius 4, 1 px `--line` border (placeholder: gray horizon gradient + diagonal stripes + play glyph) |
| Name | 13 pt, 600, `--txt` — e.g. "DJI_0042 – DJI_0047" (en-dash range) or "DJI_0048" |
| Sub-line | 11 pt `--txt-2`: date · time (`--txt-3`) · "+ 6 telemetry .SRT" (`--txt-3`, splits only) |
| Badge | pill, 10 pt, 700, uppercase. Split: light-orange text `--acc1` on 12 % `--acc1` bg + 28 % border, text "SPLIT · 6". Single: `--txt-3` on `rgba(255,255,255,0.04)` |
| Meta columns | 12 pt `--txt-2`, tabular numerals, right-aligned fixed columns: "6 files" (count bold `--txt`) · duration "30:15" (bold) · size "22.70 GB" |

- Row click toggles the checkbox. Hover: `rgba(255,255,255,0.025)`.
- Checked row: flat 12 % `--acc2` tint (no left bar, no gradient).
- **Pre-selection rule:** after scan, split recordings are checked, singles are not.
- Expanded segment sublist: bg `rgba(0,0,0,0.22)`, monospace 11 pt rows, 78 pt left inset:
  `├ DJI_0042.MP4  + DJI_0042.SRT  …(flex)…  5:23  4.04 GB` (last row `└`).

## Queue row spec

34 pt row: output filename (220 pt, 600, truncating, e.g. `DJI_0042_joined.MP4`) · progress bar
(flex, 5 pt tall, track `rgba(0,0,0,0.35)`, radius full) · status (84 pt, 11 pt) · icon actions (22 pt).

| Status | Fill | Status text | Actions |
|---|---|---|---|
| Queued | empty | "Queued" `--txt-2` | remove (×) |
| Running | `--acc2` at pct | "Joining…" `--acc1` 600 | — |
| Done | green `--ok` 100 % | "Done" `--ok` 600 | reveal-in-Finder (magnifier) |
| Failed | red `--bad` at failure pct | "Failed" `--bad` 600 | retry (circular arrow), remove (×) |

**Do not animate bar width with a CSS width transition** — drive it directly from progress
updates (we hit a wedged-transition bug; native ProgressView is fine).

## Interactions & Behavior

- **Choose/Scan:** Empty state's "Choose Folder…", the source well "Choose…", or "Scan" all start
  a scan. Scanning state: centered system spinner + "Scanning card…" + live "N clips found ·
  grouping by timecode & metadata" counter.
- **All/None/Splits** set the selection in one click. Header count updates live.
- **Add to Queue:** appends selected recordings as queued jobs (skips ones already queued),
  then clears the selection. Console gets the scan/join log lines (see `data.js → jobLog`).
- **Start/Stop:** jobs run strictly sequentially. Footer button swaps to "Stop" while running.
  Per-job log lines stream into the console as progress advances.
- **Retry** re-queues a failed job (attempt 2 succeeds in the prototype). **Remove** deletes a
  queued/failed job. **Reveal in Finder** on done jobs.
- **Console** remembers open/closed; auto-scrolls on new lines.
- Footer overall progress = mean of per-job percentages; goes green when all done with 0 failed.

## State Management (prototype reference: `conjoyn/app.jsx`)

- `phase`: `empty | scanning | loaded`
- `selection: {recId: bool}`, `openRows: {recId: bool}`
- `jobs: [{rec, status: queued|running|done|failed, pct, attempts}]`, `running: bool`
- `consoleLines: [[kind, text]]` where kind ∈ `cmd | info | ok | bad`
- `opts: {fixDate, timecode, telemetry}` (all true by default)

## Design Tokens

Colors (dark-only, neutral charcoal — Final Cut Pro-style):

| Token | Value | Use |
|---|---|---|
| `--bg` | `#1D1D1D` | window/content background |
| `--panel` | `#232323` | output bar, footer |
| `--titlebar` | `#282828` | titlebar/toolbar |
| console bg | `#151515` | console well |
| `--line` | `rgba(255,255,255,0.07)` | hairline separators |
| `--line-strong` | `rgba(255,255,255,0.12)` | footer top border |
| `--txt` | `#E8E8E8` | primary text |
| `--txt-2` | `#9F9F9F` | secondary text |
| `--txt-3` | `#6E6E6E` | tertiary/labels |
| `--acc1` | `#FFB23E` | light accent: Split badge, "Joining…" status, spinner |
| `--acc2` | `#F0622A` | control accent: primary buttons, checks, switches, progress, selection tint |
| `--ok` | `#3FD68A` | success |
| `--bad` | `#FF6B6B` | failure |

- Selection tint = `--acc2` at 12 % over row bg.
- Typography: system font (SF Pro). 13 pt names/controls, 12 pt meta, 11 pt sub-lines/labels/console,
  10 pt badges. Numerals: tabular wherever numbers align. Console + segment sublists: SF Mono.
- Controls are **flat macOS dark-mode style** — no gradients. Standard buttons:
  `rgba(255,255,255,0.12)` fill, radius 5, 22 pt tall, 13 pt regular, hairline top inner highlight.
  Primary buttons: solid `--acc2`, white 500 text. Large (footer/empty-state) buttons 28 pt, radius 6.
  Stop button: `rgba(255,107,107,0.22)` fill, `#FFB3B3` text.
  Segmented control: inset `rgba(0,0,0,0.28)` well, padding 1, selected segment raised
  `rgba(255,255,255,0.16)`. Switches: 30 × 18 pt, solid `--acc2` when on.
  In SwiftUI prefer real `Button`/`Toggle`/`Picker(.segmented)`/`ProgressView` with
  `.tint(accent)` over hand-built lookalikes.
- Radii: 4 (thumbs), 5 (buttons), 6 (segmented/large buttons), 7 (wells), full (pills/progress).
- Spacing: 16 pt side gutters, 12 pt in-row gaps, rows 9 pt v-padding (compact density: 5 pt,
  28 pt thumbs, sub-line hidden).

## Assets

No external assets. All icons in the prototype are simple 16 × 16 strokes (`conjoyn/ui.jsx →
CJ_PATHS`): folder, chevrons, retry, ×, magnifier, scan-frame, SD-card. In SwiftUI use SF Symbols:
`folder`, `chevron.right/down`, `arrow.clockwise`, `xmark`, `magnifyingglass`,
`viewfinder`, `sdcard`. Thumbnails: generate from the actual clips.

## Files

| File | Contents |
|---|---|
| `Conjoyn Prototype.html` | Entry point — open in a browser |
| `conjoyn/styles.css` | **All visual styling + tokens** (the authoritative spec) |
| `conjoyn/data.js` | Mock card data (14 recordings / 42 clips), formatters, console-log script |
| `conjoyn/ui.jsx` | Atoms: icons, checkbox, switch, badge, progress, thumb |
| `conjoyn/rows.jsx` | Recordings list, row + segment sublist, empty & scanning states |
| `conjoyn/queue.jsx` | Output bar, queue rows, console, footer |
| `conjoyn/app.jsx` | State machine, scan/join simulation, state jumper, tweaks |
| `frames/macos-window.jsx`, `frames/tweaks-panel.jsx` | Prototype-only scaffolding (window chrome bits, tweaks panel) — ignore for implementation |
| `uploads/conjoyn-mockup-brief.md` | Original product brief |

Prototype-only elements to **exclude** from the real app: the "Jump to state" pill row, the
Tweaks panel, the scripted rec-12 failure, and the simulated timing.
