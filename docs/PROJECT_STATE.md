# Project State

> Lean digest (<100 lines). Full history → `docs/sessions/`; rationale → `docs/decisions.md`.

## Identity
- **Project:** Conjoyn (brand lowercased **conjoyn**; bundle `com.lucesumbrarum.conjoyn`). Xcode
  project/target/module/.app = `Conjoyn`; source `01_Project/Conjoyn` + `ConjoynTests`; repo root
  folder `Conjoyn` (renamed from the `DJIjoiner` placeholder 2026-06-11).
- **One-liner:** native macOS app that auto-stitches split DJI drone MP4 segments into one lossless
  file, fixes the date/timecode metadata, and re-times the `.SRT` telemetry sidecar.
- **Started:** 2026-06-07 · **Tags:** macOS, video, DJI, metadata, ffmpeg.
- **Git:** canonical history at `github.com/Xpycode/Conjoyn` (private, **HTTPS via `gh`**, no SSH).
  Code syncs across Macs via **Syncthing, which excludes `.git`** → history travels **only via
  `origin`**. A fresh Mac (no `.git`) → run the **`git-bootstrap` skill**; **never `reset --hard`
  blind**. Commit identity `Luces Umbrarum <87826179+Xpycode@users.noreply.github.com>`.

## Now
- **Phase:** implementation — **100% feature-complete + SHIPPED PUBLIC.** Version **1.0.2 / build 102**
  (monotonic for Sparkle). **Tests: 360 app / 1 skip / 0 fail · 10 FeedbackKit pkg.**
- **✓ Post-ship verification-honesty polish committed `e90f838` (2026-06-18), pushed.** Five
  eyeball-confirmed fixes (see the 2026-06-18 Recent entry) — Debug-local only; shipped 1.0.2/102 DMG +
  appcast untouched, so the **live download still predates these fixes** (re-cut owed only if/when a new
  build ships).
- **Blockers:** none. **🎉 1.0-public is LIVE** — the last gate (Sparkle Wave 4) is closed.
- **✓ Repo public + licensed** (2026-06-16) — `github.com/Xpycode/Conjoyn` flipped **private → public**
  after a clean pre-public secrets scan (no keys/secrets in tree or history; only Sparkle *public* key;
  `99-AUTH/` is outside the repo). Added `README.md` (overview/features/build-from-source/LGPL note/DJI
  non-affiliation disclaimer) + `LICENSE.md` = **PolyForm Noncommercial 1.0.0** (source-available, **no
  commercial/paid-app use**), licensor Luces Umbrarum. GitHub license chip may not auto-detect PolyForm.
- **✓ Sparkle Wave 4 DONE — live auto-update feed** (2026-06-17). `appcast.xml` (EdDSA-signed, build
  102) hosted at `https://conjoyn.lucesumbrarum.com/appcast.xml`; raw enclosure
  `…/Conjoyn-1.0.2.dmg` (29,487,589 B) + release notes `…/Conjoyn-1.0.2.html` (`sparkle:releaseNotesLink`)
  beside it; counted human download `dl.php?app=conjoyn` → refreshed to 1.0.2. Deployed from the website
  repo (`3-Websites/App-Websites`, `APPS/Conjoyn/`, `./deploy.sh` = `lftp mirror -R` no `--delete` → 644;
  `counts.json` preserved). **Verified live**: appcast 200, enclosure 200 w/ exact `Content-Length` match,
  `sign_update --verify` on the downloaded bytes = exit 0, dl.php 302 → 1.0.2. Mechanism itself was already
  proven end-to-end in Wave 3 (100→101 over HTTPS). **Live GUI Check-for-Updates click-through CONFIRMED
  2026-06-17** ("You're up to date! conjoyn 1.0.2 is currently the newest version available") — last optional
  gate closed. Memory `wave4-lives-in-websites-repo`.
- **DMG = current `main` (1.0.2/102)** — re-cut on the M1 Max (`make-dmg.sh`, notary **Accepted**,
  double-stapled, `source=Notarized Developer ID`, `/Applications` drop-link; version inside = 1.0.2/102;
  29 MB, installs offline). Incorporates the 2026-06-16 PM-2 fixes (console copy / bytes-ETA / join
  hardening). The `conjoyn-notary` keychain profile is **per-Mac** — recreate via `setup-notary-profile.sh`
  from `99-AUTH/` (memory `dmg-recut-on-fresh-release-mac`). The EdDSA private key is **not** in the M1 Max
  keychain — `make-appcast.sh` now signs via `SPARKLE_ED_KEY_FILE=…/99-AUTH/conjoyn-sparkle-private.key`.
- **Sparkle: complete through Wave 3** — pipeline Apple-notary-validated *and* self-update-proven
  end-to-end (`notarize.sh` archive→export, 8 nested Mach-Os Developer ID → `make-dmg.sh` →
  `make-appcast.sh`). Key custody = **3 verified-identical copies** (M4 Pro keychain `account=conjoyn`
  + `99-AUTH/conjoyn-sparkle-private.key` + password manager). Public key
  `Ks14npeWNt9Rd8QawQiBYQuzFq08vPe2hXgu1s5zVOE=`. The M4 Pro is the complete release Mac.
- **✓ App-citizenship surfaces via AppCitizenshipKit 0.1.2** (2026-06-14, logged 2026-06-16) — one
  `CitizenshipCommands(citizenship)` now drives **Send Feedback…** (FeedbackKit, re-exported; posts to
  the shared `feedback-submit.php`, server gates on `ALLOWED_APPS` ⊇ `conjoyn`), **Leave a Tip** (was
  "Donate"/"Support" — tip-jar framing, `?app=conjoyn`), and a **link-rich About panel**. Replaced the
  hand-assembled `FeedbackCommands` + local `DonateCommands` struct; `project.yml` drops the direct
  FeedbackKit dep (now transitive via ACK). ACK was generalized from this app's own #102/#104 patterns.
  Memory `feedbackkit-in-app-feedback`. *Optional owed:* eyeball the live ACK menu/About surfaces.
  (`fttttj` test feedback entry **deleted** 2026-06-17.)
- **✓ Light theme** — default Dark; **Appearance** menu (Match System / Light / Dark). Intentionally
  diverges from the App Shell Standard (dark-only) — flagged. **Match-System revert fixed 2026-06-16**
  (`feb3c43`): driven via `NSApplication.shared.appearance`, not `.preferredColorScheme` (whose `nil`
  doesn't clear a forced `NSWindow.appearance` on macOS) — cookbook #113.
- **✓ App icon — runtime light/dark Dock switch** (2026-06-16, `945ff4d`) — Appearance menu has a 2nd
  "App Icon" section (Match System / Light / Dark) below a divider. macOS can't vary the *bundle* icon
  by appearance (actool drops dark renditions as "unassigned children"), so `AppIconController` sets
  `NSApp.applicationIconImage` at runtime (`.auto` tracks `effectiveAppearance` via KVO). Bundle/Finder
  icon stays dark; SVG masters in `02_Design/app-icon/`. Cookbook #114.

## Backlog (all post-ship / optional)
- **✓ Footer progress bar misread a *stopped* queue as success — FIXED 2026-06-17** (found + fixed,
  real 60-job run, eyeball-confirmed). Was: after **Stop** with jobs incomplete, the footer showed
  green **"✓ 36 of 60 joined, 0 failed"** + a **full green bar**, indistinguishable from a clean
  finish (stopped jobs are `.cancelled`, `Status.isFinished` true for `.cancelled` → both
  `overallProgress` and `allFinished` treated 60/60 as done → success branch). **Fix:** new
  `QueueManager.cancelledCount`; new `CJBarSegment` + `CJQueueOutcomeBar` (segmented composition bar
  — green=completed, red=failed, amber=cancelled/stopped, orange=live-active, empty=pending; leaves
  the single-fill `CJProgressBar` and its 3 other call sites untouched); footer only shows the green
  ✓ success styling when `failed == 0 && cancelled == 0`, otherwise neutral amber/red text with
  "· N stopped" / "· N failed". The filled width while processing still equals the old
  `overallProgress`, so progress math is unchanged — only colour composition is added.
- ~~nil-date sort policy~~ **DONE 2026-06-16** — chose Finder "undated always last" (bottom in **both**
  directions). New pure generic `ConversionViewModel.ordered(_:field:by:ascending:)` partitions undated
  rows out, sorts+reverses the dated, re-appends undated; `filteredGroups` routes through it. +2 tests
  (343/1 skip/0 fail).
- Optional DMG polish (custom background image).
- **Localization / i18n** (raised 2026-06-16, "for later") — app is English-only; no `.lproj` /
  String Catalog. Future: extract UI strings → `Localizable.xcstrings`, add target languages.
- Roadmap futures (not built): **watch-folder ingest** (spec v1 scope, never shipped — stale comment at
  `RecordGroup.swift:10`), **more camera families** (engine already camera-agnostic). User's target test
  set (footage to be collected later, 2026-06-17): **GoPro 11 / 7 / 5 + DJI Osmo Action.** On the in-app
  Roadmap as "More camera families" (GoPro + Osmo Action named generically; telemetry/sidecar handling
  may trail the video join per brand).
- **✓ ETA accuracy — whole-queue "time left" oscillation FIXED** (found + fixed 2026-06-17, real 60-job
  4K card eyeball). Footer swung wildly: "~3 min left" mid-join → "~3h 43m" while a job was *Verifying…* →
  "~2 min" on the next fast job. **Cause:** `remainingQueueSeconds` derived a *live* throughput from the
  active job (`activeBytes × progress / elapsed`) for the pending estimate — but `progress` covers only the
  fast ffmpeg join (internal-SSD write); the PM-2 **cross-volume staged move + auto-verify** tail isn't
  progress-tracked, so the live sample read ~10× too fast mid-join and *collapsed* toward zero during
  verify (progress frozen at 1.0, elapsed climbing), blowing the pending term up to hours. **Fix:** dropped
  the live-throughput override; the pending portion now uses `SpeedTracker.throughputBytesPerSec` (already
  correct — `recordConversion` times the full join→move→verify wall-clock). Active job keeps its own
  `elapsed/progress` countdown. +1 regression test (`testRemainingQueueSecondsPendingStableAcrossActiveJobPhase`
  asserts the pending estimate is phase-independent). **Two follow-ups from the same eyeball** (run finished
  ~13 min vs ~10 est — oscillation gone, 9→10 stable): **(a) ETA now extrapolates from THIS run's observed
  pace** — `QueueManager.sessionBytesDone/sessionSecondsDone` accumulate per completed job (full
  join→move→verify wall-clock), reset each batch; pending = bytes ÷ session-pace, falling back to
  `throughputBytesPerSec` only until job #1 finishes, then default. A cold start (first file ~6 min, 10×
  slower than the 70 MB/s history) now honestly raises the estimate and converges as the drive warms, instead
  of trusting a steady-state average (+1 test `testRemainingQueueSecondsUsesObservedSessionPaceForPending`).
  **(b) Console hang FIXED** — the PM-2 single-`AttributedString` `.textSelection` `Text` re-laid-out *all*
  up-to-5 000 lines on every streamed line → main thread pegged at 99% CPU. **Final form (2026-06-17 eve):
  line-by-line, uncapped, in a `LazyVStack`** — lazy layout bounds cost to the visible rows, so the full log
  scrolls without hanging; per-line selection (the accepted trade), **Copy All** still copies the full log.
  (Superseded the interim 300-line cap.) **351 tests/1 skip/0 fail.** **Committed `d995624` (ETA + console),
  pushed; DMG still = shipped 1.0.2.** *Owed:* live-queue eyeball of the adaptive ETA in a current build.
- Footage-gated: 2.2/2.3 reader polish, 2.7 TS-remux fallback, Apple `Keys` creationdate atom (6.3).
- Minor owed eyeballs: slow-mo + SRT-mismatch integrity chips (unit-tested only — no such clip on cards seen).

## Recent (newest first — full logs in `docs/sessions/_index.md`)
- **2026-06-18 (PM)** — **Timecode write-back verification** (ported the one reusable idea from TCE's
  ladder; audit found Conjoyn already equals/exceeds TCE on media integrity). Conjoyn's headline
  date/timecode fix was **stamped but never verified** — now the output's `tmcd` is re-read and
  compared to the assigned TC. New persisted `ConversionJob.appliedTimecode`; new
  `VerificationCheck.Kind.timecodeWriteback` wired into `runTier0And1` (runs in fast **and** thorough
  tiers); pure `compareTimecode`/`timecodeFields` (separator-insensitive `:`/`;`, drop-frame-aware);
  mismatch/missing = `.fail`, unparseable = `.warning`. **`mapStatus` fix:** a passing byte-exact hash
  no longer masks a TC write-back fail (the hash can't speak to the `tmcd`). **+6 tests → 360/1 skip/0
  fail.** Zero UI work (seal/chip row iterates checks generically). **Live eyeball on real `2CULL`
  footage caught a read-path bug the units couldn't:** the `tmcd` was written fine, but the AVFoundation
  reader (`SourceTimecodeReader`, Penumbra port) threw `.missingFormatDescription` — an ffmpeg-muxed
  tmcd puts its format description on the *track*, not the sample buffer. Switched the verifier to read
  via **ffprobe** (`stream_tags=timecode`, consistent with the rest of `SourceTargetVerifier`); re-run
  logs "Timecode write-back: match", Verify reads "No issues flagged." ✓. Debug-local; **1.0.2/102 DMG +
  appcast untouched.**
- **2026-06-18** — **Post-ship UI-honesty polish (full day, committed `e90f838` + pushed).** Five eyeball-confirmed fixes
  on real `2CULL` footage. **(1)** Thorough-verify control `.cjGhost`→`.cjStandard` (visible filled
  button + `checkmark.shield`). **(2)** Bar lifecycle: new transient `ConversionJob.isFinishing` →
  "Finishing…" label for the move tail; `barFill` gates green on `verificationStatus == .verified`.
  **(3)** `moveIntoPlace` → streamed 8 MB-chunk copy with `progress` + fsync-before-delete; composite
  bar `joinPortion = staged ? 0.5 : 1.0`. **(4) Green-only-when-verified extended to text + footer:**
  new `VerificationStatus.outcomeTier` (verified/working/failed) = **single source of truth**, routed
  through `barFill`, `statusColor`, and the footer (`verifiedCount`/`awaitingVerificationCount`/
  `verifyFailedCount`); verifying now reads **amber** everywhere, green only at the seal. **(5) Verify
  folded into the single bar:** `ConversionJob.lifecycleFraction` (+`producePortion=0.85`) — produce
  fills `[0,0.85]`, verify fills `[0.85,1]`, produce caps at 0.85 for a jump-free hand-off; phase math
  on the model = unit-testable; detail keeps its own verify bar. Weighting = cost-weighted (rejected
  equal thirds: move=0 unstaged, fast verify=seconds → would lurch). **+3 tests this day**
  (move-bytes-intact, tier-buckets, lifecycle-fraction). Full suite **354/1 skip/0 fail**. Debug-local;
  **1.0.2/102 DMG + appcast untouched.** Committed `e90f838` (code+tests) + a docs commit, pushed.
- **2026-06-17 (eve / PM-3)** — **Post-ship polish, mostly committed.** **(1)** Console finalized
  **line-by-line + uncapped** (`LazyVStack`; supersedes the 300-cap) — committed with the PM-2 ETA fixes
  as `d995624`. **(2) Segmented footer outcome bar** (`381ff89`, eyeballed): a *stopped* queue no longer
  reads as green success — new `cancelledCount` + `CJBarSegment`/`CJQueueOutcomeBar` (green done / red
  failed / amber stopped / orange active / empty pending); green ✓ only when `failed==0 && cancelled==0`.
  **(3) Stale-build false alarm** (not a bug): user's "regressions" were a **Jun 13 / 1.0.1 `_run`
  snapshot synced from a release Mac** being launched instead of a current build (`04_Exports/` syncs,
  `.git` doesn't). Fixed the local-build path (Developer ID manual signing on a Mac without a Mac
  Development cert) + overwrote `_run`. *Lesson:* short literals vanish from `strings` via Swift
  small-string inlining — verify builds with a long literal + binary mtime. **(4) Deep-verify label**:
  transient `ConversionJob.isDeepVerifying` drives **"Verifying (byte-exact)…"** in the row + detail +
  seal tooltip during the Tier-2 hash (auto-escalation or manual) — committed this session. **(5)** Confirmed
  verification "very quick" is **by design** (fast Tier 0+1 ffprobe check, auto-escalates to byte-exact on
  anomaly). **351 tests/1 skip/0 fail; `main == origin/main`; DMG/appcast still = shipped 1.0.2.**
- **2026-06-17 (PM-2)** — **Post-ship eyeball → ETA + console fixes (committed `d995624`).** Live GUI self-update
  confirmed. A real 60-job 4K run surfaced + fixed: **(1)** whole-queue ETA oscillation (live-throughput
  sample off the active job's join-only `progress`, collapsing during the un-tracked staged-move/verify
  tail) → dropped the live override; **(2)** ETA now **extrapolates from this run's observed pace**
  (`sessionBytesDone/Seconds`, reset per batch) so a cold start honestly raises the estimate — user's idea,
  ground-truthed against the log (first file 5.9 min/1.7× realtime vs 13-min run, ~10-min est); **(3)**
  console hang (99% CPU — PM-2 single-`AttributedString` `Text` over up-to-5 000 lines) → reverted to
  line-by-line uncapped (`LazyVStack`), Copy All still full. **351 tests/1 skip/0 fail.** Committed eve as
  `d995624` (+2 tests), pushed; `main` + shipped 1.0.2 DMG/appcast untouched. See backlog ✓ ETA / console.
- **2026-06-17** — **SHIPPED Sparkle Wave 4 → 1.0-public is LIVE.** Git reconcile first (pre-flight's
  "1 unpushed" was a stale pre-fetch snapshot; `main == origin/main`, clean). Then closed the last gate:
  bumped **1.0.1/101 → 1.0.2/102** (`54f69b3`; the live download DMG predated the PM-2 fixes by ~11 h, so
  re-cut from current `main`), re-cut the notarized DMG on the M1 Max (notary **Accepted**, double-stapled,
  1.0.2/102), generated the EdDSA-signed `appcast.xml` + `Conjoyn-1.0.2.html` release notes, deployed all to
  Strato `/CONJOYN/` (`deploy.sh`, no `--delete` → `counts.json` safe), refreshed the human download to 1.0.2.
  **Verified live**: appcast/enclosure/notes all 200, exact `Content-Length` match, `sign_update --verify` on
  the served bytes = exit 0, `dl.php` 302 → 1.0.2. Enhanced `make-appcast.sh` to sign via
  `SPARKLE_ED_KEY_FILE` (M1 Max lacks the keychain key; `e844259`). Website files committed (`4c1f852`).
  *Note:* the shell's git tooling semantically split commits — a pre-existing `apps.json` edit shipped as its
  own `c236287` ("add Magpie to roster"). *Owed (optional):* live GUI Check-for-Updates click-through.
- **2026-06-16 (PM-2)** — **3 user-found issues fixed on real footage** (on `main`, **not yet committed/pushed** at
  time of writing; 349 tests/1 skip/0 fail, +6). **(1) Console multi-line select + Copy All** — lines were
  separate `Text` views (`.textSelection` can't cross siblings); now one `Text` from a tinted `AttributedString`
  (drag-select + ⌘A + ⌘C all work, per-line colour kept) + a **Copy All** button. **(2) Whole-queue ETA fixed** —
  was `contentDuration ÷ speedMultiplier` (wrong for I/O-bound `-c copy`; 15× default + average-of-ratios bug);
  now **bytes ÷ throughput** measured **live off the running job** (fallback: pooled history → conservative
  default), so pending jobs are **size-weighted** (a 50 GB split ≈ 2.5× a 20 GB one). **(3) Two real failures
  diagnosed = NOT app bugs** — transient external-USB I/O under sustained load (volume healthy: APFS, 293 GB free;
  "failed" source reads + ffprobes clean now). **Hardening shipped:** delete partial output on failure (only files
  *we* wrote this attempt); **stage join on internal temp → move to destination** (external drive does only
  sequential source reads + 1 write, killing the read/write/faststart contention; off-main move; auto-skips when
  temp==dest volume); **auto-retry once** on transient errors (`conversionFailed`/`probeFailed`/unknown, never on
  deterministic ones). **DMG now lags `main`** again (these changes not in the 1.0.1/101 artifact). Version
  unchanged. *Owed:* real-footage eyeball of the staged-move multi-GB path.
- **2026-06-16** — Doc reconcile + **4 UI changes** (all on `main`, pushed, eyeballed): File-menu
  **Choose Source / Destination Folder** split (`24d14b2`); **Match-System appearance fix** (`feb3c43`,
  cookbook #113); **runtime light/dark Dock-icon switch** in the Appearance menu (`945ff4d`, new light
  variant). AM: logged the **AppCitizenshipKit migration** that landed 2026-06-14 but went unrecorded
  (`CitizenshipCommands` replaces split FeedbackKit + Donate, `8d8ccad`/`9c216ea`). Version unchanged
  1.0.1/101; no engine/test change.
- **2026-06-14** — Donate surface (Help topic + menu item, `8584ab3`; cookbook #104). Earlier same day:
  FeedbackKit fixed (0.1.0 broken → 0.1.3 works, proven end-to-end), app → 1.0.1/101; DMG re-cut from
  `main` (1.0/100); two fresh-release-Mac script fixes (`22373d4`).
- **2026-06-13** — Sparkle Waves 0–3 done + on `main` (key custody secured, notary Accepted, self-update
  proven); light theme merged; QuickLook thumbnails (cookbook #95); diagnostic logging; single-window +
  menu polish; Roadmap help topic; git-bootstrap discipline hardened.
- **2026-06-12** — DMG wrapper (shippable); sortable columns (v1.0.1); surfaced + decided + planned the
  Sparkle auto-update gap.
- **2026-06-10/11** — Feature run: manual TC override, source↔target verification, integrity flags, live
  ETA/speed, output-folder clarity, single-file export, Help window, native toolbar (cookbook #89), app
  icon, design-handoff SwiftUI port, signed + notarized, Conjoyn rebrand.

## Risks
- **SRT offset-correction stitching** = highest-uncertainty v1 item (per brief). Engine implemented +
  footage-validated; scope-creep flagged but user-chosen.
- ~~FFmpeg GPL~~ **RESOLVED** — reproducible static arm64 **LGPL** FFmpeg 8.1 (no GPL/nonfree), validated
  lossless on real footage; build via `01_Project/scripts/build-ffmpeg-lgpl.sh` (binaries gitignored).

## Detail (read only if needed)
- `docs/decisions.md` — why behind every choice · `docs/sessions/_index.md` — per-session logs ·
  `specs/dji-auto-stitcher.md` — spec + acceptance criteria · `IMPLEMENTATION_PLAN.md` — 7-wave plan.
