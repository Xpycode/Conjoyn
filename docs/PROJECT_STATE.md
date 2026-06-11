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
- **Next:** (1) ~~`feature/rename-tc-disclosure`~~ **DONE — merged to `main` (`30c8447`, 2026-06-10f)
  and pushed.** Both commits in; eyeballed live on a real SRT-bearing card (Source TC `—`, Applied TC
  `19:53:03:11 · from SRT cue · 25 fps`, slow-mo caption — Applied TC matches the engine's s7 stamp
  exactly). 220/220 tests. (2) **UI polish pass** — **3 items
  done 2026-06-10d** (popover width 348→430, draggable list/queue `VSplitView` divider, "Clear Queue"
  button); **2026-06-10h** added a visual-diff rig (cookbook #77) + dropped redundant user-facing
  "DJI" copy + restored the Scan button label (`.labelStyle(.titleAndIcon)`). **DONE — 220/220 tests,
  merged `--no-ff` → `main` (`f4eeb99`, 2026-06-10i) and pushed; both feature branches deleted.**
  Empty + Loaded match the prototype; Scanning/Running seen during a live join; **Done not yet
  clean-eyeballed.** (3) ~~**single-file export**~~ **DONE + LIVE-TESTED + MERGED → `main`
  (`73cffed`, 2026-06-10k); branch deleted.** Relaxed `mergeClips`'s
  `>= 2` guard to `>= 1`; a lone clip runs the same concat-`-c copy` path (preview/data dropped,
  +faststart, creation_time/tmcd stamped, `.SRT` carried over via the N=1 stitch). Param guard
  skipped for N=1; in-place export can't clobber its source (`addJob` case-insensitive collision →
  `(1)`). UI already allowed ticking single rows. **+2 integration tests → 229/229.** **Live-tested
  2026-06-10k** (independent ffmpeg repro on real clip `0004`, 0.98 GB, 4 streams): source v:0
  packet **MD5 == output v:0 MD5** (byte-identical, truly lossless), 5554→5554 frames, mjpeg preview
  + 2 telemetry data tracks dropped, duration 222.16 s exact, `creation_time=2026-05-21T17:47:15Z` +
  `tmcd=19:47:15:08` stamped, faststart (moov before mdat). **GUI eyeball (tick lone row → Start)
  still owed** (no UI automation). (4) ~~**ETA readout**~~ **DONE + MERGED → `main` (`2f0cde4`,
  2026-06-10p); branch deleted, pushed.** Surfaced the ETA machinery ported-but-unused from P2toMXF
  (Penumbra has none). Per active queue row: `12.5× · ~2:34 left` (1 s `TimelineView`;
  history-independent `elapsed/progress`, historical `currentJobEstimate` fallback before 5%; speed
  from ffmpeg's live `speed=` via new `QueueManager.activeMetrics`). Footer: whole-queue
  `· ~N min left` (`remainingQueueSeconds(at:)` = active live remaining + pending historical
  estimate). Shared `formattedCoarseDuration()`; no new source files. **+5 tests → 250/250.**
  **Owed:** live eyeball during a real join (display-only; math unit-tested) + cosmetics (140 pt
  metrics column at the 1220 pt min window; `×` vs `x`). (5) ~~**Empty-space metadata-integrity panel**~~ **DONE + MERGED → `main` (`e74f431`, 2026-06-11);
  feature `3a7a238`, branch deleted, pushed.** New pure `RecordingIntegrity` service built lazily per
  row (`.task`), reusing the engine's `RecordingStartResolver` + `TimecodeDisclosure.detectSlowMotion`
  (no engine coupling; skips the absent-for-DJI `tmcd` read). The row's date line now shows the
  **corrected** date + an origin tag ("from filename"/"from SRT cue") instead of parroting a
  wrong/missing embedded date; a chip strip appears **only** for genuine problems (no date / bad date /
  SRT↔filename mismatch) + slow-mo, each with a `.help()` tooltip. `CJBadge` gained `isFlagged`
  (flagged lone clip → orange SINGLE badge → single-file re-export discoverable). The routine
  "date from X" is the inline tag only, never a chip (no duplication). **+13 tests → 263/263.**
  Live-confirmed the SRT path (all "from SRT cue", clean → no chips); **owed:** eyeball the slow-mo +
  SRT-mismatch warning chips (no such clip on the cards seen — unit-tested only). Original ask: the
  recordings list/queue have empty vertical space; surface per-recording integrity (missing embedded
  date, slow-mo dual-timebase) — which also makes single-file export discoverable.
  **(5b) Codec + dimensions in the recordings-row empty space — DONE 2026-06-10o (`6683656`).**
  Each row now shows `HEVC · 3840×2160 · 25 fps` in the gap before the SINGLE/SPLIT badge (new
  `CJFormat.codec`/`resolution`/`fps` + `RecordingRow.streamSummary` off the first segment's
  `streamInfo`). Pure display add as predicted; +7 tests. Live-confirmed on the `2CULL` card.
  (6) ~~**Wire up source↔target verification**~~ **DONE + MERGED → `main` (`bca191c`, 2026-06-11b);
  branch deleted, pushed.** Replaced the dead decode-only check with **true source↔target
  verification** (new `SourceTargetVerifier`: Tier 0 readability / Tier 1 fast container-index compare
  — exact packet count+bytes, ±1-frame duration, codec-param identity, A/V drift / Tier 2 opt-in
  byte-exact per-stream packet-MD5). Auto fast-verify after each join (live source scope),
  auto-escalating to the hash on any anomaly; per-row green/orange/red **seal** + non-pass chips + a
  manual "Thorough verify (byte-exact)" button. New `VerificationStatus.warning`; old decode-only
  `VerificationService` left unwired. **Caught + fixed a pipe-buffer deadlock** (`cf3de85`) that would
  have hung the queue after every real join (ffprobe per-packet stdout > 64 KB pipe buffer → stdout
  now captured to a temp file). **+42 tests → 305/305**; real-ffmpeg integration (byte-identical pass
  + tampered-source fail). **Owed:** live GUI eyeball of the seal on a real card.
  (7) **Help window** (2026-06-10i) —
  vendor the standalone `/1-macOS/AppHelp/` package; cost is topic content, not wiring (**no Settings
  scene** — decided unnecessary). (8) DMG wrapper. ~~(9) **Per-recording manual TC entry**~~ **DONE +
  MERGED → `main` (2026-06-11d); branch deleted.** `HH:MM:SS:FF` `TimecodeField`
  (orchetect/swift-timecode v3.1.2) in the queue-row TC disclosure panel. Override replaces only
  the `-timecode` ffmpeg arg; `creation_time` unaffected. Session-only (`timecodeStringOverride`
  excluded from `CodingKeys`). `TimecodeDisclosure.build()` reflects override with `.manualOverride`
  provenance; `QueueRow .task` keyed reactively. 4 commits: model+engine, disclosure reactivity,
  TimecodeKit dep, UI. **+10 tests → 315/315.** **Owed:** live GUI eyeball (expand queue-row caret →
  Override TC field → Set → join). **(10) Output-folder ↔
  queue clarity — DONE + LIVE-VERIFIED + MERGED → `main` (`37aca3f`, 2026-06-10n); branch deleted,
  pushed.** Implemented 2026-06-10m (`2eb0143`); **live A+B GUI verify 2026-06-10n** on a real 60-job
  queue: per-row "Output" disclosure row showed each job's destination; changing the Output folder
  fired the "Apply new output folder to 60 pending jobs?" popover; **Keep** lit the orange ⚠ badge +
  `⚠ → …/DJI_001 (≠ current output)` sub-line on every pending row; **Apply** re-pointed all 60 +
  cleared the badges reactively. 238/238.
  (plan in repo: `docs/plans/output-folder-clarity.md`). User picked
  **A = Hybrid** (per-job destination always in the row's TC disclosure panel + an inline ⚠ badge/
  sub-line only when a job's folder ≠ the current Output-bar folder) and **B = themed popover**
  (click-away = the safe "Keep"). Shared `QueueManager.directoriesDiffer(_:_:)` (robust dir compare,
  cookbook #52) powers both halves; new `reassignPendingDestinations(to:)` preserves each pending
  job's filename stem + re-resolves collisions (mirrors `resolveFilenameConflict`); `.pending` only,
  never active/finished; **no new source files** (no xcodegen regen). Original diagnosis:
  `addToQueue()`
  (`ConversionViewModel.swift:177-187`) **freezes** `outputFolderURL` into each `job.destinationURL`
  at enqueue; the Output bar governs only *future* adds and **rows never show their destination**, so
  changing the folder after queuing silently doesn't apply. Per-job freezing is correct for a queue —
  the defect is missing feedback. **A (Transparency):** show each job's destination in the queue
  (inline `→ <folder>/` or in the row-disclosure panel; data on `job.destinationURL`). **B (Re-apply
  on change):** when the Output folder changes *and* `.pending` jobs exist, prompt "Apply new output
  folder to N pending jobs? [Apply / Keep]" — pending/unstarted only (`!status.isFinished`, not
  `active`/`preparing`), recompute `newFolder + same stem`, re-run collision resolution; never touch
  active/Done. Tier C (pending jobs track the live folder, freeze at start) noted as a bigger optional
  model change — defer. **DONE this session:** "Singles" added to the selection filter
  (All·None·Splits·Singles, `cee27e3`). Smaller polish: Apple `Keys` creationdate atom (6.3), doubled
  camera-variant suffix (`…_0009_D_D.mp4`).
  **(11) Minimum window size mangled the Output bar — FIXED + MERGED → `main` (`3928f47`/`37aca3f`,
  2026-06-10n).** At the old `minWidth: 1000` floor the Output bar overflowed ("Output"→"utput",
  "Timecode from recording time" wrapped, "Add to Queue" clipped). `.windowResizability(.contentMinSize)`
  does **not** derive the bar's true floor through the `VSplitView`, so the window could shrink below
  it. **Fix:** measured the bar's intrinsic width via AppKit font metrics (~1160 pt worst-case: well +
  4 switch labels + gear + "Add N to Queue"), set root `minWidth: 1220` (`ContentView.swift`), and
  `.fixedSize()`-ed the "Output" + switch labels as a backstop. Drag-verified live: labels intact, no
  clipping, window stops at the comfortable width. 3 reference screenshots in
  `03_Screenshots/min-window-size_2026-06-10m/`.

## Recent (newest first)
- **2026-06-11d — Shipped per-recording manual TC override (backlog 9); refined UX.**
  `TimecodeField` (orchetect/swift-timecode v3.1.2); `ConversionJob.timecodeStringOverride`
  session-only; `TimecodeDisclosure.build()` gains `tcOverride:` + `.manualOverride` provenance.
  4 commits, `/execute` wave-based. **+10 tests → 315/315.** Live-tested: popover opens, auto-advance
  HH→MM→SS→FF works, Set updates Applied TC to `manual`, orange pencil.circle.fill confirms active
  state. **UX iteration same session:** replaced inline Override TC row with a `pencil.circle` button
  inline on the Applied TC row → popover with `.autoAdvance` `TimecodeField` + Set (Enter) + Revert
  (Esc). One fewer disclosure row. Icon bumped to default scale + `txt2` (was `.small` + `txt3` —
  too dim). Merged + pushed.
- **2026-06-11c — Researched + planned backlog (9): per-recording manual TC override.**
  Multi-agent research across three reference projects + TimecodeKit library. Decided on
  `orchetect/swift-timecode` v3.1.2 (SwiftUI-native `TimecodeField`, macOS 14+, Swift 6
  compatible). Override is TC-only (not `creation_time`), stored session-only on `ConversionJob`
  outside `CodingKeys`. Full 4-commit plan written in `docs/sessions/2026-06-11c.md`, ready to
  `/execute` next session.
- **2026-06-11b — Shipped true source↔target verification (backlog 6); caught + fixed a deadlock.**
  Executed wave-based (`/execute`) against an in-repo plan, fresh-context agent per wave. New
  `SourceTargetVerifier` exploits the lossless join (output kept-streams == Σ sources): **Tier 0**
  readability gate, **Tier 1** fast container-index compare (exact packet count+bytes, ±1-frame
  duration with "missing trailing segment" detection, codec-param identity via `StreamParameterGuard`,
  A/V drift), **Tier 2** opt-in byte-exact per-stream packet-MD5 (sources via the join's own
  `buildConcatList`). `autoVerifyJoin` runs after `.completed` while source scope is live (before the
  fn-level `defer`), auto-escalating to the hash on `hasWarning || !passed`; `runThoroughVerify`
  re-resolves the bookmark for the manual button. `QueueRow` seal (checkmark/exclamationmark/xmark
  `.seal`) + `VerificationChip` row + `.cjGhost` "Thorough verify" button + progress. New
  `VerificationStatus.warning`; old decode-only `VerificationService` left **unwired** (zero callers).
  All `-map` restricted to kept streams (`v:0`/`a:0`). **Deadlock caught in review** (`cf3de85`): the
  process runner read ffprobe stdout from a `Pipe` in the termination handler — per-packet
  `packet=size` output (>64 KB on a real join) overflows the pipe buffer, blocking the child forever →
  queue hangs after every real join (test clips too small to hit it). Two concurrent-drain attempts
  hung even tiny output (`readDataToEndOfFile` never saw EOF); diagnosed by `sample`-ing the stuck
  process, fixed by capturing stdout to a **temp file**. **+42 tests → 305/305.** Merged `--no-ff` →
  `main` (`bca191c`), pushed, branch deleted; 11 files, +1689 lines. **Owed:** live GUI eyeball of the
  seal on a real card (engine covered by the byte-identical + tampered-source integration test).
- **2026-06-11 — Shipped the per-recording metadata-integrity flags (backlog 5) + two eyeball fixes.**
  Planned with Explore + Plan agents and a web/HIG check, then live-iterated on real cards. New pure
  `RecordingIntegrity` service (lazy `.task` per row, reuses `RecordingStartResolver` +
  `TimecodeDisclosure.detectSlowMotion`, no engine coupling): the date line now shows the **corrected**
  date + origin tag rather than a wrong/missing embedded date, and a chip strip appears **only** for
  real problems (no date / bad date / SRT↔filename mismatch) + slow-mo, each with a tooltip. `CJBadge`
  `isFlagged` tints a flagged lone clip's SINGLE badge orange. Plan-agent catch: `displayStartDate`
  returned the raw embedded date only; DJI's real integrity story is date *provenance*, not
  source-`tmcd`. Dropped the redundant "date from X" chip (duplicated the inline tag). **+13 tests →
  263/263.** Merged `--no-ff` (`e74f431`, feature `3a7a238`), pushed. Then two eyeball fixes: the
  queued-job "black rectangle" was `CJProgressBar`'s empty track at 0% → **hidden for `.pending`
  jobs** (`d96bc51`, `119e2c3`); and the **thumbnail loading placeholder** flattened + its `play.fill`
  glyph removed (flat tile + ▶ read as a clickable play button) → bare flat dark tile (`1d6136a`,
  `abe96eb`). Diagnosed "thumbnails not loading" as a non-bug — `ThumbnailManager` caps extraction at
  3 concurrent FFmpeg procs, so large 4K segments fill in slower. **Owed:** live-eyeball the slow-mo +
  SRT-mismatch chips.
- **2026-06-10p — Shipped the live ETA + speed readout (backlog 4); planned against Penumbra/P2toMXF.**
  Research keystone: it was a **wiring** job — `ProgressMetrics.estimatedRemainingSeconds`,
  `currentJobEstimate`, and ffmpeg's live `speed=` were all **ported from P2toMXF and sitting unused**
  (Penumbra has no ETA). Scope (user): **per-row + footer total**, and **show the speed multiplier**
  (the only part needing plumbing — the live `ProgressMetrics` was discarded after the slow-speed
  check). Impl, no new files: `QueueManager.activeMetrics` (`@Published`, fed by the `metricsHandler`,
  cleared at job start/end); testable `remainingQueueSeconds(at:)` (active job's live
  `elapsed/progress` remaining + historical fallback < 5% + `getTotalQueueEstimate()` for pending);
  shared `formattedCoarseDuration()` (de-duped `ConversionEstimate.formattedEstimate` onto it).
  `QueueRow` → `12.5× · ~2:34 left` inline (1 s `TimelineView`, active rows only); `FooterBar` →
  whole-queue `· ~N min left`. Per-row ETA is history-independent (robust on a fresh install). **+5
  tests → 250/250.** Merged `--no-ff` → `main` (`a9f4de1`→`2f0cde4`), branch deleted, pushed; Debug
  app launched. **Owed:** live eyeball during a real join + 2 cosmetic confirmations.
- **2026-06-10o — Two UI polish items shipped: codec/resolution on rows (backlog 5b) + a font cleanup.**
  (1) **Codec · resolution · fps on each recording row** (`6683656`) — pure display add (scan already
  reads `VideoStreamParams` per clip for the param guard, so no new I/O). New `CJFormat` helpers
  (`codec`/`resolution`/`fps`) + `RecordingRow.streamSummary` reading the first segment's `streamInfo`
  (speaks for the whole group — the grouping gate refuses mismatched codec/res/fps), placed in the
  empty space before the SINGLE/SPLIT badge. `CJFormatTests` +7 → **245/245**. Live-confirmed on the
  `2CULL` card (`HEVC · 3840×2160 · 25 fps`); wrong-folder empty state also confirmed. (2) **Font
  cleanup** (`6adb44a`) — the "serif-like" font was **SF Mono** (`design: .monospaced`). Switched the
  segment-sublist filenames + queue-row disclosure **Output** path to **SF Pro** (kept
  `.monospacedDigit()` for column/date alignment); **TC stays SF Mono** (user's choice); console +
  Rename token field left mono. Path wells + queue-row title were already SF Pro. Both merged `--no-ff`
  → `main`, branches deleted, pushed.
- **2026-06-10n — Fixed the min-window Output-bar bug, live-verified output-folder A+B, merged + pushed.**
  (1) **Window fix:** the `minWidth: 1000` floor let the Output bar overflow (truncate/wrap/clip);
  `.windowResizability(.contentMinSize)` doesn't derive the bar's floor through the `VSplitView`.
  Measured the bar's intrinsic width via AppKit font metrics (~1160 pt worst-case), set root
  `minWidth: 1220` + `.fixedSize()`-ed the labels as a backstop (`3928f47`). Drag-verified live; 238/238.
  (2) **Output-folder A+B live-verified** on a real 60-job queue: per-row "Output" disclosure row,
  the "Apply to 60 pending jobs?" popover, **Keep** → orange ⚠ badge + `(≠ current output)` sub-line on
  every row, **Apply** → all 60 re-pointed + badges cleared reactively. (3) Merged `feature/output-folder-clarity`
  `--no-ff` → `main` (`37aca3f`), branch deleted, **pushed** (origin `e6a2fb1..37aca3f`). (4) Diagnosed a
  false-alarm "crash": the app never died (10-min uptime, no crash report) — a file-dialog beachball on the
  USB `2CULL-IN/DJI_001` folder (349 items, thumbnail storm; boot disk 96 % full), then the window slipped
  behind another app.
- **2026-06-10m — Reconciled git after the Mac switch, then implemented output-folder ↔ queue clarity
  (A+B); found a min-window-size bug.** (1) **Git:** no `origin` on this Mac + `main` stale at
  `3e27526` — later work showed "uncommitted" only because Syncthing excludes `.git`. Wired
  `origin`→`github.com/Xpycode/Conjoyn`, fetched (`e6a2fb1`), proved on-disk source byte-identical to
  origin (only the gitignored generated `.xcodeproj` differed), user-approved the auto-blocked
  `reset --hard origin/main` → reconciled, regenerated `.xcodeproj`, removed the resolved handoff
  banner. (2) **Feature `2eb0143`** on `feature/output-folder-clarity`, per the in-repo plan, **no new
  files:** `QueueManager.directoriesDiffer` + `reassignPendingDestinations` (pending-only, stem-
  preserving, collision-safe, bookmark-refreshing); VM prompt state + change-detect in
  `chooseOutputFolder`; `ApplyFolderPopover` + per-row ⚠ badge/sub-line + always-on "Output" disclosure
  row. **+9 tests → 238/238**; Debug build SUCCEEDED + launched. **UNMERGED — live A+B GUI verify
  owed.** (3) **NEW BUG:** at `minWidth: 1000` the Output bar middle row mangles; 3 reference
  screenshots saved. Next: bump `minWidth`, live-verify A+B, merge.
- **2026-06-10l — Planned the output-folder ↔ queue clarity (A+B) feature (no code).** 3 Explore
  agents mapped the freeze point (`addToQueue` bakes `outputFolderURL` into each `job.destinationURL`),
  the job/status model, collision logic, and the all-in-`QueuePanel.swift` UI; confirmed dialog APIs
  via sosumi MCP. User chose **A = Hybrid** (destination always in the row's TC disclosure panel +
  inline ⚠ badge only when a job's folder ≠ the current Output folder) and **B = themed popover**
  (click-away = "Keep"). A shared robust `QueueManager.directoriesDiffer(_:_:)` powers both halves;
  `reassignPendingDestinations(to:)` re-points `.pending` jobs (preserve stem, re-resolve collisions).
  Plan at `~/.claude/plans/merry-painting-toast.md`; **no new source files**. User exited before
  approving — implementation next session.
- **2026-06-10k — Live-tested + merged single-file export; added the Singles filter; reaffirmed TC
  source; approved A+B for the output-folder trap.** (1) **Single-file export** clean-built (229/229,
  both single-file tests ran w/ real ffmpeg), **independently verified on real clip `0004`** via the
  bundled ffmpeg + the exact production N=1 arg vector: **source v:0 packet MD5 == output v:0 MD5**
  (byte-identical, truly lossless), 5554→5554 frames, mjpeg preview + 2 telemetry data tracks dropped,
  duration exact, `creation_time`+`tmcd=19:47:15:08` stamped, faststart. Merged `--no-ff` → `main`
  (`73cffed`), pushed, branch deleted. (2) **"Singles" selection filter** (`cee27e3`) — mirror of
  Splits; bar = All·None·Splits·Singles; built, merged, pushed, branch deleted. (3) **TC source: no
  change** — user asked to switch filename→creation_time; traced the resolver and showed filename is
  correctly ranked higher (camera-local + copy-proof; atom is UTC/skewed, filesystem resets on copy;
  no `:00`-frame precision gain — only SRT cue is sub-second), user confirmed *keep filename priority*.
  (4) **Output-folder ↔ queue trap diagnosed** — destination frozen per-job at enqueue + no per-row
  dest shown → changing the folder after queuing silently no-ops. **Approved A+B** (transparency +
  re-apply-to-pending prompt) for next session. Logged backlog (5b) codec/dimensions in row, (9)
  manual TC entry. Owed: GUI eyeball of single-file export (tick lone row → Start).
- **2026-06-10i — Merged the UI-polish pass; scoped Help/Settings; shipped card-aware folder descent.**
  (1) `feature/ui-polish` → **220/220** → merged `--no-ff` `main` (`f4eeb99`) + pushed; deleted it and
  the stale-merged `feature/rename-tc-disclosure`. (2) **Help/Settings audit:** neither ever scoped;
  **decided no Settings scene** (no persistent pref — tunables in-context, rename/override session-only)
  and **Help = deferred backlog** (vendor the standalone `/1-macOS/AppHelp/` package; cost is content).
  (3) Live test on the card root surfaced four items: queue "won't clear" = **by-design** restore
  (`queue.json` reloads on launch → use Clear Queue); ETA → backlog; "slower I/O" = **the UHS-I SD card**
  (source `disk12` SD read-capped ~95 MB/s, dest `disk11` USB — different disks, earlier runs read from
  USB), not a regression. (4) **Card-aware descent** (`feature/recursive-card-scan`, `543ddc8`): new
  `DJIFolderReader.resolveMediaFolders(startingAt:)` finds `DCIM/*` media when a card *root* is dropped,
  **bounded to one subdir level** (no deep walk). **7 tests → 227/227.** Live-verified on `/Volumes/M4P-1`.
- **2026-06-10h — UI polish pass (visual-diff driven): dropped redundant "DJI" copy + restored the
  Scan button label.** From the user's "Choose a DJI folder is a bit redundant now." Built a
  visual-diff rig (**cookbook #77** — Playwright+WebKit rendered all 5 prototype states; live
  `screencapture` blocked by missing Screen Recording permission, user supplied Empty+Loaded
  manually). `Theme.swift` mirrors `styles.css` 1:1 — port is faithful; 3 divergences are
  intentional (native-toolbar wordmark drop, Rename+gear, queue TC caret). **Only 2 user-facing
  "DJI" strings** (both `ConversionViewModel.swift`); ~18 internal `DJI*` identifiers are the domain
  model and stay. Applied 3 edits on `feature/ui-polish`: picker msg → "Choose a media folder (e.g.
  DCIM/100MEDIA)", empty-scan status → "No video segments found…", and `ContentView.swift:69` Scan
  `Label` gains `.labelStyle(.titleAndIcon)` (toolbars default `Label` to `.iconOnly` → primary
  action had been a bare `viewfinder` glyph since the 2026-06-10g native-toolbar move). Clean build
  ✓, user confirmed. **Committed on branch — tests + merge deferred to next session per user.**
- **2026-06-10g — Migrated the custom titlebar to a native macOS toolbar (UI polish).** From the
  user's "could the toolbar be in the title bar?" Replaced the custom 52 pt `TitleBar` HStack +
  `WindowConfigurator` with a native `.toolbar` + `.toolbarRole(.editor)` (App Shell Standard, like
  Penumbra/CropBatch): source path well centered (`.principal`), Scan trailing (`.primaryAction`),
  app name/tagline dropped. **Hit + fixed macOS 26 Tahoe Liquid Glass "bubbles"** — native toolbar
  items get auto-enrolled into Liquid Glass on the 26 SDK (siblings look flat only because they're
  pre-Tahoe-SDK builds). Opted the app out app-wide via **`UIDesignRequiresCompatibility`**, after the
  `INFOPLIST_KEY_*` route silently failed → minimal base `Info.plist` + `GENERATE_INFOPLIST_FILE`
  merge. Removed orphaned `Theme.titlebar`. 220/220. `feature/native-toolbar` → `main` (`b6c7418`),
  pushed. Captured as **cookbook #89**. Next: continue the UI polish pass.
- **2026-06-10f — Eyeballed the TC disclosure live, then merged `feature/rename-tc-disclosure` to `main`.**
  Cleared the last two owed items on the branch. **Live eyeball** on a real SRT-bearing card
  (`/Volumes/M4P-1/DCIM/DJI_001`, the 2026-05-21 footage): queued the split `0006–0009`, opened the
  queue-row caret → **Source TC `—`** (DJI has no `tmcd`), **Applied TC `19:53:03:11` · from SRT cue ·
  25 fps** (orange), **slow-mo caption** fired. The Applied TC is **byte-identical to the engine's
  s7-validated stamp** (`19:53:03:11`, frame 11 = floor(.448×25)) — confirming the feature's premise:
  the row reuses the *same* `RecordingStartResolver`+`TimecodeFormatter` the join calls, so readout
  can't drift from stamp. Split-group disclosure sublist (`SPLIT·4` + `.SRT` sidecars) also correct.
  Then **merged `--no-ff` → `main` (`30c8447`) and pushed**; feature branch retired. Caveat logged:
  the slow-mo path is now eyeballed, but the *original* `2CULL/…/DJI_001` card (2026-03-18, no SRTs)
  can't exercise it — slow-mo detection is SRT-derived by design. Next: UI polish pass.
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
- **Tests:** 315 (all pass; 1 pre-existing real-decode skip). Incl. real ffmpeg/ffprobe integration
  (source↔target byte-identical pass + tampered-source negative case).
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
