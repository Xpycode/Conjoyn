# Project State

> Lean digest (<100 lines). Detail lives in session logs and `decisions.md`.

## Identity
- **Project:** Conjoyn (visible brand `conjoyn`; bundle id `com.lucesumbrarum.conjoyn`). Xcode
  project/target/module/.app = `Conjoyn`; source folders `01_Project/Conjoyn` + `ConjoynTests`.
  **Repo root folder is still `DJIjoiner`** (intentionally not renamed — keeps tooling/memory paths
  stable). "DJIjoiner" was the working placeholder.
- **One-liner:** macOS app that auto-stitches split DJI drone MP4 segments back into one lossless
  file, fixes the date/timecode metadata, and re-times the `.SRT` telemetry sidecar.
- **Tags:** macOS, video, DJI, metadata, ffmpeg
- **Started:** 2026-06-07
- **Repo/git:** canonical history at `github.com/Xpycode/Conjoyn` (private), baseline `830b8fa`
  (created 2026-06-10c). Code syncs across Macs via **Syncthing, which excludes `.git`** — so git
  history travels **only via `origin`**. Any other Mac must `git remote add origin … && git fetch
  && git reset --hard origin/main` **before committing**, or history forks (see memory
  `git-remote-reconciliation`).

## Now
- **Phase:** implementation, ~97%. Engine validated end-to-end on real footage (14/14 batch,
  date/TC/SRT all `ffprobe`-verified), **signed + notarized + stapled**, and the **designed UI is
  now live** — the design handoff is ported to SwiftUI and a real join ran through the new window
  on the real card (user-driven, 1/1 joined).
- **Blockers:** none.
- **Next:** (1) **`feature/rename-tc-disclosure` — FEATURE-COMPLETE** (both commits done; branch
  **not yet pushed** — Commit 1 `cfbc5a1` was on `origin`, but Commit 2 `2524b00` is local-ahead).
  Commit 1 (2026-06-10d) = Rename popover + `RenamePatternEngine`. **Commit 2 DONE** (`2524b00`,
  2026-06-10e) = per-queue-row TC disclosure (lazy/row-side `TimecodeDisclosure` + caret/panel on
  `QueueRow`) + ported `SourceTimecodeReader`; 220/220 tests. **Still owe: eyeball the panel on a
  real card** (empty queue this session) + **push to `origin`**. (2) **UI polish pass** — **3 items
  done 2026-06-10d** (popover width 348→430, draggable list/queue `VSplitView` divider, "Clear Queue"
  button); more sizing/position deviations vs the prototype remain to enumerate against a live build
  (the new TC caret/panel sit in the queue-row region a polish pass touches). (3) **single-file export** (user request 2026-06-10):
  let a lone 1-segment recording be exported via copy/remux so its date/timecode get stamped + `.SRT`
  carried over — today the engine refuses with "need at least two segments". (4) DMG wrapper. Smaller
  polish: Apple `Keys` creationdate atom (6.3), doubled camera-variant suffix (`…_0009_D_D.mp4`).

## Recent (newest first)
- **2026-06-10e — Implemented Commit 2 (per-queue-row timecode disclosure) + ported `SourceTimecodeReader`.**
  Final commit of `feature/rename-tc-disclosure` (`2524b00`). **Display-only, no engine/export change**
  (spec Part 2 = honesty + exposing already-computed values). New **`TimecodeDisclosure`** value built
  **lazily in the row** (`.task(id:)`, deviation from the plan's "freeze on `ConversionJob`" — user
  approved: same values from the job's frozen `clips`+`settings` via the *identical*
  `RecordingStartResolver`+`TimecodeFormatter` the engine stamps with, but zero model/`addJob`/`queue.json`
  churn). Async only for the `tmcd` read. **Ported `SourceTimecodeReader`** 1:1 (TN2310 `AVAssetReader`;
  `Result` `@unchecked Sendable` for strict-concurrency `complete`); DJI usually has no `tmcd` → "—".
  **`QueueRow`** gains a disclosure caret (per-row session-only) + inline panel (Source TC · Applied TC +
  origin tag + fps · slow-mo note). **Best-effort slow-mo detection** from the SRT playback-vs-real
  wall-clock span ratio. **9 tests → 220/220.** Not yet eyeballed live (empty queue) / not pushed.
- **2026-06-10d — Implemented Commit 1 (Rename Joined Files popover) + 3 live-review UI fixes.** Built
  the patterned-output-name feature from the 2026-06-10c plan: new pure **`RenamePatternEngine`** (1:1
  `cjApplyPattern` port + `uniqueStem` collision-suffixer), **ViewModel** rename state (session-only,
  memoised start-date cache) + batch enqueue that de-dups vs *batch ∪ unfinished-queue ∪ dest-folder*
  (rename-OFF path untouched), new **`RenamePopover`** + a **`CaretTextField`** `NSViewRepresentable`
  for caret token-insertion, 4th "Rename files" switch. `{date}`/`{time}` share the same
  `RecordingStartResolver` instant as the date/TC stamp. **16 new tests → 211/211.** Merged into
  Commit 1: popover **widened 348→430** (native controls bulkier than the CSS mockup). Two more
  review fixes as their own commits: draggable list/queue **`VSplitView` divider** (`18d617a`) and a
  **"Clear Queue" button** (`8579210`, keeps a mid-write job). Branch **pushed** to `origin`. Next:
  Commit 2 (per-row TC disclosure + `SourceTimecodeReader`).
- **2026-06-10c — Reconciled this Mac's git, then scoped (and deferred) the next feature.** A routine
  `/status` exposed a git/reality split: docs describe many merges to `main`, but this Mac's `.git`
  held only 2 commits with the whole Conjoyn source uncommitted. Root cause: the repo syncs via
  **Syncthing, whose `.stignore` excludes `.git`** ("code travels via GitHub remotes"), and this Mac
  was **never wired to a GitHub origin** (none existed). On-disk source confirmed authoritative/current.
  **Re-baselined from this Mac:** committed the tree as `830b8fa` on `main` (renames auto-detected),
  fixed a rebrand leftover (`.gitignore` `DJIjoiner.xcodeproj`→`Conjoyn.xcodeproj`), created **private
  `github.com/Xpycode/Conjoyn`**, pushed + set upstream, deleted stale `feature/wave1-verification`.
  Then scoped `feature/rename-tc-disclosure` (specced, 0 code): read the full code+design surface,
  produced an **approved 2-commit plan**, branched off `830b8fa` — **implementation deferred to next
  session**. Decided rename state lives on the ViewModel (session-only, not `ConversionSettings`) and
  **feature-then-polish** ordering.
- **2026-06-10b — Ported the design handoff to SwiftUI; live-validated on the real card.** The
  main window is now the designed vertical flow (titlebar/source bar → recordings hero → output
  bar → queue → collapsible console → footer) with the full token set, real row thumbnails,
  split-disclosure sublists, drag-drop, and a gear popover for the off-design engine knobs.
  195/195 tests; merged to `main`. User drove a real join through the new UI (1/1 ✓) and asked
  for: a sizing/position polish pass + **single-file export** (stamp TC on lone clips — engine
  currently refuses 1-segment jobs).
- **2026-06-10 — Wired in the final app icon (molten-weld-bead).** User delivered the final icon;
  the project had **no asset catalog at all** (generic icon until now). Created
  `01_Project/Conjoyn/Assets.xcassets/AppIcon.appiconset/` (10 renditions 16→512@2x), set
  `ASSETCATALOG_COMPILER_APPICON_NAME=AppIcon`, regenerated via xcodegen. Debug-build verified:
  `Assets.car` carries all renditions, Info.plist icon keys = `AppIcon`, launches with the icon in
  the Dock. Design source (1024 SVG master + `.iconset`) committed under `02_Design/conjoinAppIcon/`.
- **2026-06-10 — Added the canonical UI design handoff (port target).** High-fidelity design for the
  single main window across its 5 states (Empty → Scanning → Loaded → Running → Done): HTML/React
  prototype + authoritative `styles.css` tokens + a SwiftUI-oriented `README.md` spec, in
  `02_Design/design_handoff_conjoyn/`. Dark charcoal / orange (`#F0622A`) Final-Cut look. **Spec only —
  not yet implemented;** the SwiftUI port is the next (design) session. The engine already drives every
  flow the UI shows, so the port is a reskin + region restructure of `ContentView.swift`, not new logic.
- **2026-06-10 — Signed + notarized the app (task 6.2 done).** Drove the full Developer ID pipeline
  end-to-end: Release build signed with **Developer ID Application** (Team `FDMSRXXN73`), hardened
  runtime + secure timestamp on the app wrapper *and* both bundled helpers (ffmpeg/ffprobe), then
  notarized via Apple's service (**App Store Connect API key**, keychain profile `conjoyn-notary`) and
  **stapled**. First submission **Accepted**; `spctl -a` now reports `source=Notarized Developer ID`
  (launches on any Mac, no "unidentified developer" block, works offline). Codified one-command in
  `01_Project/scripts/notarize.sh` (build → verify → zip → submit --wait → staple → spctl). Caught +
  fixed a `grep -q`/`pipefail` SIGPIPE bug in the helper-hardening check (signing was always fine).
  Distribution artifact: stapled zip in `04_Exports/`. DMG wrapper deferred to the design session.
- **2026-06-09 — Executed the Conjoyn rebrand (app/project/module/bundle).** Renamed the placeholder
  "DJIjoiner" → **Conjoyn**: project + targets, bundle ids `com.lucesumbrarum.conjoyn(.tests)`, source
  folders (`git mv`, history kept), `ConjoynApp`, entitlements, 19 test imports, runtime storage paths,
  build scripts; regenerated `Conjoyn.xcodeproj` via xcodegen. Visible brand is lowercase **conjoyn**
  (`CFBundleDisplayName`); binary/module/.app stay PascalCase `Conjoyn` (keeps `TEST_HOST` +
  `import Conjoyn` clean). **Repo root folder + git intentionally left `DJIjoiner`** (tooling/memory
  path stability). Clean build + full suite green (195/195); built bundle verified (id, display name,
  signed helpers). Merged to `main`.

## Progress
- **Funnel:** Define ✓ · Plan ✓ · Build — in progress (~97%).
- **Waves:** Wave 0 ✓ · Wave 1 queue ports ✓ · Wave 2 footage-free (2.1/2.5/2.6) ✓ · **2.4 real
  grouping ✓ (footage-validated)** · **2.8 date/TC stamp ✓ (footage-validated)** · Wave 3 SRT ✓ ·
  UI wired + per-group selection ✓ · **full GUI pipeline ✓ (footage-validated end-to-end: scan→join→
  date→TC→SRT, 14/14 batch)** · **design handoff ported to SwiftUI ✓ (live-validated)**.
  Footage-gated remaining: 2.2/2.3 reader polish vs more real cards, 2.7 (TS-remux fallback), the
  size-changing Apple `Keys` creationdate atom (6.3).
- **Tests:** 220 (all pass; 1 pre-existing real-decode skip). Incl. real ffmpeg/ffprobe integration.
- **Readiness:** Directions installed; spec at `specs/dji-auto-stitcher.md`; P2toMXF port source
  cloned (gitignored); tech stack locked (macOS 14+, SwiftUI/Swift 6, Apple Silicon, AVFoundation +
  bundled FFmpeg + exiftool; direct distribution + notarized, sandbox off / hardened runtime on).

## Risks
- **SRT offset-correction stitching** = highest-uncertainty v1 item ("known unsolved pain point"
  per brief). Scope-creep flagged but user-chosen. (Engine implemented; needs footage to validate.)
- ~~Interim FFmpeg is GPL~~ **RESOLVED 2026-06-09 (task 6.1):** swapped to a reproducible static
  arm64 **LGPL** build (FFmpeg 8.1 from source, no `--enable-gpl`/`--enable-nonfree`, no external
  libs; 20 MB each, self-contained, validated lossless on real footage). Binaries gitignored; run
  `01_Project/scripts/build-ffmpeg-lgpl.sh` (the GPL `fetch-ffmpeg.sh` is now a dev-only fallback).

## Detail (read only if needed)
- `docs/decisions.md` — the why behind every technical/design choice.
- `docs/sessions/_index.md` — full per-session logs.
- `specs/dji-auto-stitcher.md` — spec + acceptance criteria.
- `IMPLEMENTATION_PLAN.md` — the 7-wave plan and atomic tasks.
