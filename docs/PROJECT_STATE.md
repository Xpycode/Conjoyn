# Project State

> Lean digest (<100 lines). Full history → `docs/sessions/`; rationale → `docs/decisions.md`.

## Identity
- **Project:** Conjoyn (brand lowercased **conjoyn**; bundle `com.lucesumbrarum.conjoyn`). Xcode
  project/target/module/.app = `Conjoyn`; source `01_Project/Conjoyn` + `ConjoynTests`; repo root
  folder `Conjoyn` (renamed from the `DJIjoiner` placeholder 2026-06-11).
- **One-liner:** native macOS app that auto-stitches split DJI drone MP4 segments into one lossless
  file, fixes the date/timecode metadata, and re-times the `.SRT` telemetry sidecar.
- **Started:** 2026-06-07 · **Tags:** macOS, video, DJI, metadata, ffmpeg.
- **Git:** canonical history at `github.com/Xpycode/Conjoyn` (public, **HTTPS via `gh`**, no SSH).
  Code syncs across Macs via **Syncthing, which excludes `.git`** → history travels **only via
  `origin`**. A fresh Mac (no `.git`) → run the **`git-bootstrap` skill**; **never `reset --hard`
  blind**. Commit identity `Luces Umbrarum <87826179+Xpycode@users.noreply.github.com>`.

## Now
- **Phase:** implementation — **100% feature-complete + SHIPPED PUBLIC**, version **1.0.4 / build 104**
  (shipped 2026-07-18: output-folder-popover crash fix + saved rename templates; notarized DMG + signed
  appcast + 104→103 binary delta live). **Tests: 495 app / 1 skip / 0 fail · 10 FeedbackKit pkg.**
  ⚠️ **`main` is AHEAD of the shipped build** since 2026-08-06: the renamed-footage parser fix is on
  `main` but not in 1.0.4, so renamed folders still scan empty in the installed app until the next bump.
- **Focus:** **Wave 5 (watch-folder ingest) is fully closed AND daemon-hardened** — engine + multi-folder
  UI merged to `main` (`c814efc`), the **real removable-SD-card eyeball (5.14) PASSED 2026-06-24**, and the
  **3 worth-fixing engine-review items are now fixed + merged** (2026-06-24, `fix/wave5-watchfolder-hardening`
  → `main` `2905b38`). **Wave 6 is now effectively closed; next focus = GoPro + Osmo Action
  camera-family support** — user now has the hardware (DJI Osmo Action 1, GoPro 11, GoPro 7).
- **Blockers:** none. 🎉 1.0-public is live; the last gate (Sparkle auto-update) is closed.
- **Next:** **Wave 6 is effectively closed.** **6.3 (legacy *and* timestamped + slow-mo) + 6.4 SRT alignment
  are engine-validated on real footage** (2CULL legacy + 2026-06-24 M4P-1 timestamped/slow-mo pass).
  **6.5 missing-middle CLOSED** via the **index-gap guard** in `continues()` (+3 tests). **6.5 variant-guard +
  mixed-codec now closed via synthetic real-tool fixtures (2026-06-24)** — `JoinGuardIntegrationTests` drives
  the production guard path on clips made by the bundled LGPL ffmpeg + probed by the real ffprobe: `_W`/`_T`
  parsed by the real `DJIFilenameParser` never co-group even when size/time/index would chain them; an
  `mpeg4`+`mjpeg` pair and a 25-vs-30 fps pair are **refused by `ensureJoinable`** end-to-end (+4 tests).
  **Only two slivers stay genuinely footage-gated (cannot synthesize):** real multi-lens **index numbering**
  (Mavic 3 Pro / thermal — guard asserted on the single-camera consecutive model only) and the **exact
  h264/hevc bytes** (LGPL build ships no x264/x265, so mpeg4/mjpeg stands in; the guard compares codec-name
  strings, so the path is identical). Neither is a blocker.
- **Watch-folder hardening — DONE (2026-06-24, merged):** the 3 worth-fixing items from the 2026-06-23
  review are fixed: **(1)** hung-`discover` deadlock → bounded `discoverTimeout` (90 s, tunable) + split
  `isDiscovering`/`isResampling` latch so a wedged scan can't latch the watcher shut (`e3f9789`); **(2)**
  FSEvents teardown UAF → stream now takes a context retain on the monitor, balanced at `Release`
  (`d7e05fe`); **(3)** enqueue→join TOCTOU → `FileIdentity` `(dev,ino)` snapshot at enqueue, re-verified
  before `mergeClips`, swap/rotation throws non-retriable (`3ee5933`, cookbook #127). +#4 stale-key cache
  eviction. +13 tests. Rationale in `decisions.md` (2026-06-24). **Still deferred** (cosmetic, not
  reachable): unbounded ledger, `nil`-vs-`""` fingerprint, decorative `WatchGroupState`, shared GCD label.

## Recent (newest first — full logs in `docs/sessions/_index.md`)
- **2026-08-06 (latest)** — **Fixed: a folder of renamed footage scanned as completely empty.** The
  filename parser demanded that a name *begin* with `DJI_`, so archived clips carrying a prefix
  (`M4P--2026-05-21--…--DJI_20260521194329_0001_D.MP4`) were all rejected — 9 clips and 9 telemetry
  sidecars vanished with no explanation, because the "N skipped" counter only shows in the recordings
  list, which isn't on screen when nothing was found. A prefix is now allowed (it must end in a
  separator); a trailing addition is still refused, which is what stops the app re-reading its own
  joined output as new source. The empty state now says *why* it's empty. Proven on the real footage:
  the renamed copy groups identically to June's hand-verified run on the same clips under their
  original names. +7 tests → 495. **Ships with the next version bump.**
- **2026-07-18 session 3** — **Shipped 1.0.4 / build 104 — public point release.** Carries the
  two finished changes `main` had been sitting on: the output-folder-popover crash fix + saved rename
  templates. Suite re-run green before cutting (488/1 skip/0 fail); both notary round-trips Accepted +
  stapled; appcast now serves 1.0.4+1.0.3+1.0.2 **plus a first-ever 104→103 binary delta** (212 KB —
  generate_appcast emits it when the previous DMG is still staged; must be deployed or old updaters 404
  before falling back). Website: badge → v1.0.4, notes page live, `downloads/conjoyn.dmg` swapped.
  **All live checks passed** (byte-exact DMG length vs. signed enclosure, dl.php 302→200, old DMGs intact).
- **2026-07-18 session 2** — **Built saved rename templates in the Rename popover.** A
  custom naming pattern can now be stored with one click on a ＋ chip and recalled from a new
  "Saved:" chip row that appears once the first template exists (right-click deletes; chips are
  labelled with the pattern itself, so there's no naming step). Templates survive relaunch —
  previously a custom pattern reset every launch by design. Pattern-only by user choice (counter
  settings stay per-batch, like the built-in presets). 13 new tests; all four user-eyeball checks
  passed live; merged to `main` and pushed. Ships with the next version update alongside the
  crash fix below.
- **2026-07-18** — **Fixed a live crash in shipped 1.0.3: changing the output folder while
  jobs waited in the queue killed the app.** The folder picker on macOS 26+ is hosted out-of-process
  (ViewBridge), and the "Apply new folder to pending jobs?" popover was presented in the same instant
  the picker closed — racing the picker's teardown and hitting a dead observer, which macOS turns
  into a hard crash. Fix: the popover now waits 400 ms after the picker closes
  (`ConversionViewModel.swift:293`, with a why-comment so the delay survives future cleanup). The
  watch-folders picker was audited too — safe, its popover is only ever opened by hand. Verified by
  a clean build plus the user re-running the real repro on the 2CULL card: no crash. On `main` and
  pushed; **ships with the next planned version update** — the installed 1.0.3 still crashes until
  then.
- **2026-07-14** — **Captured a roadmap idea: honour photos on a DJI SD card (preserve,
  don't process).** No code changed. Found that discovery (`DJIFolderReader.read`) silently drops any
  file that isn't `mp4/mov/srt/lrf` — a `.JPG`/`.DNG` next to the clips vanishes with no trace, a
  latent data-loss footgun if the card is treated as ingest-then-format. Logged the scope guard to
  `decisions.md`: SD-card mode offers a checksum-verified byte copy → `Photos/` sibling; watch-folder
  mode just surfaces a count; **no** panorama stitching / HDR / RAW dev. Rides existing seams
  (`.photo` mediaKind, DCIM descent, `VerificationService`) — no new subsystems. Post-v1; promote to
  `/spec` once a real photo-bearing card is on hand. Design camera-agnostic (GoPro/Osmo also shoot
  stills). Backlog entry added below.
*(older entries trimmed per the lean-digest rule — full history in
`docs/sessions/_index.md` and dated logs under `docs/sessions/`.)*

## Backlog (all optional / post-ship)
- **Real-SD-card TCC + relaunch eyeball (5.14)** — see Now/Next; the only thing between current state
  and a fully-closed Wave 5.
- **More camera families = NEXT FOCUS** (engine is already camera-agnostic) — **hardware now in hand:
  DJI Osmo Action 1, GoPro 11, GoPro 7** (footage to be captured). Validate per-brand **filename
  grouping**, **metadata read**, and **telemetry/SRT sidecar** (sidecar may trail the video join per
  brand). On the in-app Roadmap.
- **SD-card photo preservation (post-v1)** — cards carry stills (JPG/DNG/panorama/AEB) alongside video;
  today they're **silently dropped** (`DJIFolderReader.read` only classifies `mp4/mov/srt/lrf`). Scope
  **locked** in `decisions.md` (2026-07-14): **preserve, don't process.** Tier 0 = detect & surface (add
  `.photo` `mediaKind` + `Discovery.photos`, show a count — closes the silent-drop footgun). Tier 1 =
  opt-in checksum-verified byte copy → `Photos/` sibling, **SD-card mode only**, feeds a "safe to format"
  confirmation. Fence: **no** panorama stitching / HDR merge / RAW dev. Tier 2 (keep sets intact) is
  footage-gated — needs a real photo-bearing card first. Design `.photo` camera-agnostic (GoPro/Osmo also
  shoot stills). Natural `/spec` candidate once a card is on hand.
- **Localization / i18n** — app is English-only; future work is extract UI strings →
  `Localizable.xcstrings` + target languages.
- Optional DMG polish (custom background image).
- Footage-gated engine items: 2.2/2.3 reader polish, 2.7 TS-remux fallback, Apple `Keys`
  creationdate atom (6.3).
- Owed eyeballs (low-risk, unit-tested only): adaptive ETA in a current build; live AppCitizenshipKit
  menu/About surfaces; SRT-mismatch integrity chip (no such clip seen on cards yet). **Slow-mo footage is
  now seen** (M4P-1, ≈4×) and its **join + SRT path is engine-validated** (2026-06-24); only the in-app
  slow-mo *integrity-chip UI* remains an un-eyeballed GUI surface.

## Risks
- **SRT offset-correction stitching** = highest-uncertainty v1 item (per brief). Engine implemented +
  footage-validated; scope-creep flagged but user-chosen.
- ~~FFmpeg GPL~~ **RESOLVED** — reproducible static arm64 **LGPL** FFmpeg 8.1 (no GPL/nonfree),
  validated lossless on real footage; build via `01_Project/scripts/build-ffmpeg-lgpl.sh`
  (binaries gitignored).

## Infrastructure (operational reference)
- **Version 1.0.4 / build 104** — keep monotonic for Sparkle. (1.0.4 shipped 2026-07-18; appcast keeps
  1.0.4 + 1.0.3 + 1.0.2 items **+ a 104→103 binary delta**. generate_appcast emits a
  `Conjoyn<new>-<old>.delta` whenever the previous DMG is still in `04_Exports/appcast/` — **deploy it
  with the DMG**, else updaters on the previous version 404 before falling back to the full download.)
- **DMG** = current `main`, notarized + double-stapled, `/Applications` drop-link, ~29 MB, installs
  offline. **1.0.3 was cut on the M4 Pro** via `make-dmg.sh` (it holds the Developer ID identity, the
  `conjoyn-notary` profile, and the Sparkle key — the M1 Max is down). The `conjoyn-notary` keychain profile is
  **per-Mac** — recreate via `setup-notary-profile.sh` from `99-AUTH/` (memory
  `notary-credentials-recreation`). Re-cut only when a new build ships. **Ship recipe (verified 1.0.3 + 1.0.4):** bump
  `project.yml` + `xcodegen generate` → re-run tests → `make-dmg.sh` → write `Conjoyn-<v>.html` notes into
  `04_Exports/appcast/` **before** `make-appcast.sh` (that's how the releaseNotesLink gets emitted) → drop the
  staged `04_Exports/appcast/Conjoyn-<v>.dmg` + any `*.delta` + `appcast.xml` + `Conjoyn-<v>.html` into
  `App-Websites` `APPS/Conjoyn/01_Source/` (and overwrite `downloads/conjoyn.dmg` for the human button) →
  its `deploy.sh`.
  **Also bump the `v1.0.x` badge in `index.html` `.hero-meta`** (added 2026-06-25 — now a manual per-release
  source of truth alongside the appcast + DMG name + `downloads/conjoyn.dmg`).
- **Sparkle auto-update** — appcast `https://conjoyn.lucesumbrarum.com/appcast.xml`; public key
  `Ks14npeWNt9Rd8QawQiBYQuzFq08vPe2hXgu1s5zVOE=` (in Info.plist). EdDSA private key custody = **3
  verified copies** (M4-Pro keychain `account=conjoyn` + `99-AUTH/conjoyn-sparkle-private.key` +
  password manager); `make-appcast.sh` signs via `SPARKLE_ED_KEY_FILE` on Macs lacking the keychain
  key. The website/Wave-4 assets live in the **`3-Websites/App-Websites`** repo, not here (memory
  `wave4-lives-in-websites-repo`); deploy via its `deploy.sh` (`lftp mirror -R`, **no `--delete`** →
  `counts.json` preserved).

## Detail (read only if needed)
- `docs/decisions.md` — why behind every choice · `docs/sessions/_index.md` — per-session logs ·
  `specs/dji-auto-stitcher.md` — spec + acceptance criteria · `IMPLEMENTATION_PLAN.md` (repo root) —
  the 7-wave plan · **2026-06-20 log Resume block** — exact SD-card (5.14) test steps.
