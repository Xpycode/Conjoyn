# Project State

> Lean digest. Full history → `docs/sessions/`; rationale → `docs/decisions.md`; sprint
> checkboxes → `docs/TASKS.md`.

## Identity
- **Project:** Conjoyn (brand lowercased **conjoyn**; bundle `com.lucesumbrarum.conjoyn`). Xcode
  project/target/module/.app = `Conjoyn`; source `01_Project/Conjoyn` + `ConjoynTests`; repo root
  folder `Conjoyn` (renamed from the `DJIjoiner` placeholder 2026-06-11).
- **One-liner:** native macOS app that auto-stitches split DJI drone MP4 segments into one lossless
  file, fixes the date/timecode metadata, and re-times the `.SRT` telemetry sidecar.
- **Started:** 2026-06-07 · **Last updated:** 2026-10-10 · **Tags:** macOS, video, DJI, metadata, ffmpeg.
- **Git:** canonical history at `github.com/Xpycode/Conjoyn` (public, **HTTPS via `gh`**, no SSH).
  Code syncs across Macs via **Syncthing, which excludes `.git`** → history travels **only via
  `origin`**. A fresh Mac (no `.git`) → run the **`git-bootstrap` skill**; **never `reset --hard`
  blind**. Commit identity `Luces Umbrarum <87826179+Xpycode@users.noreply.github.com>`.

## Now
- **Phase:** maintenance — public release **1.0.6 / build 106**.
  <!-- Phase changed: 2026-10-10 -->
- **Focus:** post-release monitoring; repair sprint **6/6 closed**, overall **33/52 (63%)**.
- **Acceptance:** E3 closed by explicit user waiver of unperformed clean-install, actual Sparkle
  upgrade/relaunch, legacy migration and final exact-artifact GUI smoke checks. No GUI pass claimed.
- **Validation:** prior 721/0 full-suite and 64/0 focused tests; app/DMG notarized and stapled;
  nine signatures and three delta reconstructions passed. Published bytes hash-verified over HTTPS.
- **User acceptance:** user reports the updater completed and About confirms 1.0.6. This is
  real-world upgrade confirmation, not the waived disposable-state acceptance suite.
- **Next:** monitor 1.0.6 feedback; schedule deferred 1.1 device-loss acceptance when media is available.
- **App:** unchanged notarized artifact at `01_Project/build/E3-Acceptance/export/Conjoyn.app`;
  no new build or relaunch during publication. Source frozen at `c6a1b23`.
- **Git:** user authorized full release-source integration and push on 2026-10-10;
  closeout includes the published README, plans, evidence and session history.
- **Deferred:** 19 groups/items; Inbox 0. Physical active-read device loss remains a 1.1 acceptance item.
- **Known limit:** both stalled discovery workers require app relaunch; identical recording
  descriptors cannot distinguish every replacement. HERO11 H.264 and HERO7 footage checks pending.

## Recent (newest first — full logs in `docs/sessions/_index.md`)
- **2026-10-10 — Appearance fixes:** Conjoyn website follows system dark mode; all screenshots switch, and updater notes have readable light/dark colors. Safari checked; published with refreshed cache URLs.
- **2026-10-10 — Published 1.0.6:** download, signed feed, website and changelog live and hash-verified;
  GUI acceptance explicitly waived by user. GitHub README and both project logs updated.
- **2026-10-10 — E3 feed:** approved backup key used; nine signatures and three delta reconstructions pass.
  App/DMG notarized; exact GUI acceptance still lacks a disposable environment.
- **2026-10-10 — E2 freeze:** user approved all eight reviewed files; local source commit matches
  all 170 tested source hashes and seven build inputs. E3 signed-artifact acceptance is next.
- **2026-10-10 — E1 device/timing:** live timing and physical-volume mount/path recovery passed;
  normal app/data restored. User deferred unverified active-read device-loss test to 1.1; E1 accepted.


## Backlog (tracked in `docs/TASKS.md`)
- **Review follow-up:** R4/R6/R7 and queue-recovery R10 are now in the planned repair sprint. Other
  scope remains deferred. Evidence: `docs/reviews/2026-09-05/app-code-review.md`; tracking in TASKS.
- **Output name re-ingest guard** — with no rename template applied, the output takes the first
  segment's stem verbatim (`ConversionViewModel.swift:407-425`), so `…GX016349.mp4` still parses as
  a valid GoPro chapter 01 and could be re-ingested as source. The watch-folder path always appends
  `_joined` (`WatchFolderCoordinator.swift:503`); only the GUI-with-rename-off path doesn't.
  Enqueue reservations and no-replacement publication now protect pending and late collisions;
  final live batch acceptance passed (R1 closed for this safety scope).
- **More camera families** — GoPro is **done** (above); **Osmo Action 1 + GoPro 7** remain
  footage-gated. On the in-app Roadmap.
- **SD-card photo preservation (post-v1)** — cards carry stills alongside video; today they're
  silently dropped. Scope locked in `decisions.md` (2026-07-14): **preserve, don't process** —
  Tier 0 detect & surface, Tier 1 opt-in verified copy, no stitching/HDR/RAW. Tier 2 footage-gated.
  Natural `/spec` candidate once a photo-bearing card is on hand.
- **Localization / i18n** — English-only; future work is `Localizable.xcstrings` + target languages.
- Optional DMG polish (custom background image).
- Footage-gated engine items: 2.2/2.3 reader polish, 2.7 TS-remux fallback, Apple `Keys`
  creationdate atom (6.3). Two Wave-6.5 slivers stay unprovable without footage that doesn't exist —
  see the 2026-06-24 decision's caveat.
- Owed eyeballs (low-risk, unit-tested only): adaptive ETA in a current build; live AppCitizenshipKit
  menu/About surfaces; SRT-mismatch integrity chip; the slow-mo integrity-chip UI (its join + SRT
  engine path is already footage-validated).

## Risks
- **SRT offset-correction stitching** = highest-uncertainty v1 item. Engine implemented +
  footage-validated; scope-creep flagged but user-chosen.
- ~~FFmpeg GPL~~ **RESOLVED** — reproducible static arm64 **LGPL** FFmpeg 8.1 (no GPL/nonfree),
  validated lossless on real footage; build via `01_Project/scripts/build-ffmpeg-lgpl.sh`
  (binaries gitignored).

## Infrastructure (operational reference)
- **Version 1.0.6 / build 106** — keep monotonic for Sparkle. The appcast keeps a rolling 3-item
  window (now 1.0.6 + 1.0.5 + 1.0.4; `generate_appcast` drops the oldest itself) **+ binary deltas**
  (106→105, 106→104, 106→103). It emits a `Conjoyn<new>-<old>.delta` for every older DMG still in
  `04_Exports/appcast/` — **deploy them with the DMG**, else updaters on those versions 404 before
  falling back to the full download.
- **DMG** = frozen source `c6a1b23`, notarized + double-stapled, `/Applications` drop-link, ~29 MB, installs
  offline. Cut on the **M4 Pro** (it holds the Developer ID identity, the `conjoyn-notary` profile and
  the Sparkle key; the M1 Max is down). The `conjoyn-notary` keychain profile is **per-Mac** —
  recreate via `setup-notary-profile.sh` from `99-AUTH/` (memory `notary-credentials-recreation`).
- **Ship recipe (verified 1.0.3 + 1.0.4):** bump `project.yml` + `xcodegen generate` → re-run tests →
  `make-dmg.sh` → write `Conjoyn-<v>.html` notes into `04_Exports/appcast/` **before**
  `make-appcast.sh` (that's how the releaseNotesLink gets emitted) → drop the staged
  `04_Exports/appcast/Conjoyn-<v>.dmg` + any `*.delta` + `appcast.xml` + `Conjoyn-<v>.html` into
  `App-Websites` `APPS/Conjoyn/01_Source/` (and overwrite `downloads/conjoyn.dmg` for the human
  button) → its `deploy.sh`. **Also bump the `v1.0.x` badge in `index.html` `.hero-meta`** — a manual
  per-release source of truth alongside the appcast, DMG name and `downloads/conjoyn.dmg`.
- **Sparkle auto-update** — appcast `https://conjoyn.lucesumbrarum.com/appcast.xml`; public key
  `Ks14npeWNt9Rd8QawQiBYQuzFq08vPe2hXgu1s5zVOE=` (in Info.plist). EdDSA private key custody = **3
  verified copies** (M4-Pro keychain `account=conjoyn` + `99-AUTH/conjoyn-sparkle-private.key` +
  password manager); `make-appcast.sh` signs via `SPARKLE_ED_KEY_FILE` on Macs lacking the keychain
  key. Website/Wave-4 assets live in the **`3-Websites/App-Websites`** repo, not here (memory
  `wave4-lives-in-websites-repo`); deploy via its `deploy.sh` (`lftp mirror -R`, **no `--delete`** →
  `counts.json` preserved).

## Detail (read only if needed)
- `docs/decisions.md` — why behind every choice · `docs/sessions/_index.md` — per-session logs ·
  `docs/plans/release-blockers-1.0.6.md` — **completed repair plan (GUI waiver)** ·
  `docs/TASKS.md` — sprint checkboxes · `docs/plans/output-safety-1.0.6.md` — **completed safety plan** ·
  `IMPLEMENTATION_PLAN-gopro.md` — historical GoPro plan plus G8.1 footage gate ·
  `specs/gopro-camera-family.md` — GoPro spec · `IMPLEMENTATION_PLAN.md` +
  `specs/dji-auto-stitcher.md` — the shipped v1 plan and spec.
