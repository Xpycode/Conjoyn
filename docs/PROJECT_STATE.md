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
- **Phase:** implementation — **100% feature-complete.** Version **1.0.1 / build 101** (monotonic for
  Sparkle). **Tests: 343 app / 1 skip / 0 fail · 10 FeedbackKit pkg.**
- **Blockers:** none.
- **✓ Repo public + licensed** (2026-06-16) — `github.com/Xpycode/Conjoyn` flipped **private → public**
  after a clean pre-public secrets scan (no keys/secrets in tree or history; only Sparkle *public* key;
  `99-AUTH/` is outside the repo). Added `README.md` (overview/features/build-from-source/LGPL note/DJI
  non-affiliation disclaimer) + `LICENSE.md` = **PolyForm Noncommercial 1.0.0** (source-available, **no
  commercial/paid-app use**), licensor Luces Umbrarum. GitHub license chip may not auto-detect PolyForm.
- **The ONE gate to 1.0-public = Sparkle Wave 4**, and it lives in a **different repo**
  (`3-Websites/App-Websites`, `APPS/Conjoyn/`), **not here.** It's a website session: stand up
  `conjoyn.lucesumbrarum.com`, host `appcast.xml` + the **raw** DMG (Strato: `lftp mirror -R` *without*
  `--delete`, chmod 644/755; enclosure → raw DMG URL, not the counted PHP endpoint; `curl -sI` verify),
  publish the link. Within *this* repo the release engineering is **done**. Memory `wave4-lives-in-websites-repo`.
- **DMG lags `main`** (since 2026-06-16 PM-2 — console/ETA/failure-hardening landed after the re-cut). Last
  re-cut `04_Exports/Conjoyn.dmg` is the **1.0.1/101** build (app + DMG both notary **Accepted**, double-stapled, `source=Notarized Developer
  ID`, `/Applications` drop-link; verified version inside = 1.0.1/101; installs offline, 28 MB). Cut via
  `01_Project/scripts/make-dmg.sh` on the release Mac (notary profile valid; `create-dmg` ran fine in the
  GUI session). Re-cut again only if `main`'s app binary changes before publish. The `conjoyn-notary`
  keychain profile is **per-Mac** — recreate via `setup-notary-profile.sh` from `99-AUTH/` (memory
  `dmg-recut-on-fresh-release-mac`).
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
  Memory `feedbackkit-in-app-feedback`. *Optional owed:* delete the `fttttj` test entry (`/admin`);
  eyeball the live ACK menu/About surfaces.
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
- ~~nil-date sort policy~~ **DONE 2026-06-16** — chose Finder "undated always last" (bottom in **both**
  directions). New pure generic `ConversionViewModel.ordered(_:field:by:ascending:)` partitions undated
  rows out, sorts+reverses the dated, re-appends undated; `filteredGroups` routes through it. +2 tests
  (343/1 skip/0 fail).
- Optional DMG polish (custom background image).
- **Localization / i18n** (raised 2026-06-16, "for later") — app is English-only; no `.lproj` /
  String Catalog. Future: extract UI strings → `Localizable.xcstrings`, add target languages.
- Roadmap futures (not built): **watch-folder ingest** (spec v1 scope, never shipped — stale comment at
  `RecordGroup.swift:10`), **more camera families** (engine already camera-agnostic).
- Footage-gated: 2.2/2.3 reader polish, 2.7 TS-remux fallback, Apple `Keys` creationdate atom (6.3).
- Minor owed eyeballs: slow-mo + SRT-mismatch integrity chips (unit-tested only — no such clip on cards seen).

## Recent (newest first — full logs in `docs/sessions/_index.md`)
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
