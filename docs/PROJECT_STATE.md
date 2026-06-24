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
- **Phase:** implementation — **100% feature-complete + SHIPPED PUBLIC**, version **1.0.3 / build 103**
  (shipped 2026-06-25: missing-middle index-gap fix + watch-folder hardening; notarized DMG + signed appcast
  live, Sparkle now offers 1.0.3 to 1.0.2 installs). **Tests: 475 app / 1 skip / 0 fail · 10 FeedbackKit pkg.**
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
- **2026-06-25 (session 2, latest)** — **Post-ship Q&A + website v1.0.3 badge.** No app code changed.
  Traced the join output staging: finished media writes to the **temp/scratch volume first** (default boot
  SSD via `TempDirectoryManager`), copied to the destination **only when temp ≠ destination volume** — to
  keep ffmpeg's write + `+faststart` rewrite churn off slow external media (the "re-open / I/O error" fix).
  Confirmed the disk-space **preflight checks the temp volume** independently (fails open on `nil`). **Found
  + deferred a UX gap:** preflight errors point to a **"File → Temp Folder…" menu that doesn't exist** — the
  `TempDirectoryManager.setCustomTempDirectory` backend is built but never wired to UI (scratch dir is always
  the boot volume); **user chose leave as-is.** Website: `index.html` had no version string → added a static
  `v1.0.3` hero-meta badge, deployed + verified live (App-Websites `9faf089`, pushed). **Next: GoPro + Osmo
  Action camera families** (hardware now in hand).
- **2026-06-25 (ship)** — **Shipped 1.0.3 / build 103 — public.** Cut the first point release since 1.0.2,
  carrying real production fixes that had accumulated in `main`: the **missing-middle index-gap guard** (no
  silent corrupt join on a dropped slow-mo segment) + **watch-folder hardening** (FSEvents UAF, hung-discover
  deadlock, swapped-source TOCTOU guard). Bumped `project.yml` → 1.0.3/103, regenerated; `make-dmg.sh` (clean
  Release archive → Developer-ID export → both notary round-trips **Accepted** → stapled, Gatekeeper accepts);
  `make-appcast.sh` (EdDSA-signed, length 29575236 matches); wrote `Conjoyn-1.0.3.html` release notes; deployed
  via `App-Websites` `deploy.sh` (lftp, no `--delete` → 1.0.2 enclosure preserved). **Verified live:** appcast
  serves 1.0.3/103 + valid sig, DMG 200 with exact byte length, release-notes page 200, human `dl.php` button
  302→200 on the new DMG, old 1.0.2 DMG still 200. **Cut on the M4 Pro** (has Developer ID + `conjoyn-notary`
  profile + Sparkle key). This session's test/docs work was already on `main`; the shippable code was the
  earlier index-gap + watch-folder commits.
- **2026-06-24** — **Wave 6.5 variant + mixed-codec closed via synthetic real-tool fixtures.** Real
  DJI multi-lens split footage is undownloadable and the Mini 4 Pro is single-lens, so rather than leave the
  two guards proven only on hand-built params, added `ConjoynTests/JoinGuardIntegrationTests.swift` (+4): it
  drives the **production** guard path on clips generated by the bundled LGPL ffmpeg + probed by the **real
  ffprobe** — `mpeg4`+`mjpeg` and 25-vs-30 fps pairs **refused by `ensureJoinable`** end-to-end (the prior
  real-probe test only varied resolution), plus a positive control, plus `_W`/`_T` clips parsed by the real
  `DJIFilenameParser` that never co-group even when size/time/index would chain them. **475/1 skip/0 fail,
  no production code changed, no regressions.** Wave 6 now effectively closed; only real multi-lens *numbering*
  + exact h264/hevc bytes stay footage-gated (can't synthesize either; guard path is identical regardless).
  `decisions.md` + plan 6.5 row updated. Shipped 1.0.2/102 untouched.
- **2026-06-24 (missing-middle)** — **Wave 6.5 missing-middle: found & fixed a slow-mo silent-merge.** User asked me
  to source multi-lens/mixed-codec/missing-segment footage off the web; verdict = real DJI multi-lens
  split-video + SRT is essentially undownloadable (single clips / stills / SRT-only fixtures only). Reframed to
  verifying the 3 guards: variant + codec already unit-tested, **missing-middle was not**. Building the fixtures
  exposed that `continues()` had no index check — a missing **slow-mo** segment is silently bridged (playback
  bound ~4× real, too loose) into a corrupt join, while normal-speed splits safely. **Fixed with an index-gap
  guard** (adjacent segments must be index-consecutive; only ever adds a split, never a merge). +3 tests,
  **471/1 skip/0 fail**, no regressions. `b4ec873` → `--no-ff` `cd001bd`; `decisions.md` logged. **Pushed —
  `main` synced.** Closes 6.5 missing-middle; variant+codec still footage-gated.
- **2026-06-24 (earlier)** — **Wave 6.3 + 6.4 validated on real timestamped slow-mo footage (M4P-1, DJI
  Mini 4 Pro).** Prompted by "didn't we validate this on 2CULL already?" — yes for legacy naming, but 2CULL
  never had the **timestamped** scheme or **slow-mo** (an owed, never-seen case). Proved the engine's
  6-group split *semantically* correct against the SRT's own wall-clock (4-segment merge 0006→0009, seams
  exact to the second; 0010 correctly kept separate). Replicated the app's exact join: **duration = exact
  Σ (2871.72 s), streams byte-identical (10-bit HDR preserved), full decode-to-null clean (exit 0, 0
  errors)**; metadata write-back (`creation_time`+`tmcd`) confirmed; **SRT seam drift +34 ms < 1 cue, no
  accumulation**. Marked 6.3/6.4 ✅ in plan; 6.5 footage-gated (multi-lens drone). Slow-mo
  (≈4×, 100→25 fps) validates the chain-on-cap-not-playback design. Docs only; code + shipped 1.0.2/102
  untouched; tests unchanged. **6.5 variant-guard still needs a multi-lens drone.**
- **2026-06-24 (later)** — **Watch-folder daemon hardening — the 3 deferred engine-review items, fixed +
  merged.** `fix/wave5-watchfolder-hardening` → `main` (`2905b38`): bounded discovery timeout + split latch
  (a hung ffprobe no longer silently kills the watcher), FSEvents context retain (closes the teardown
  use-after-free), and a `FileIdentity` `(dev,ino)` TOCTOU guard that refuses to join a swapped/rotated
  source instead of joining the wrong bytes (cookbook #127). +#4 stale-key cache eviction. **468/1 skip/0
  fail (+13).** Code + tests only; shipped 1.0.2/102 untouched.
- **2026-06-24** — **Closed Wave 5.** Ran the real removable-SD-card eyeball (5.14) on a built-in-SDXC card
  (`Removable Media: Removable` — the precondition the `2CULL`/Fixed drive failed): 6 DJI groups joined +
  SRT-stitched + verified **off-card**, originals untouched; the macOS removable-volume prompt **never fired**
  (folder picked via panel = powerbox grant, which **persists across relaunch**); relaunch resumed the watch
  with **no re-prompt and no re-join** (ledger held); and a freshly-dropped clip was **auto-detected in ~25 s
  and joined via pure background card access** — proving the watcher is genuinely live after relaunch, not
  just UI-restored. Docs only; 455 tests unchanged, shipped 1.0.2/102 untouched.
- **2026-06-23** — Docs only: `/arrive` reconciled a Syncthing split-brain — this Mac was stranded on
  the already-merged-and-deleted `feature/wave5-watch-folder`; its "uncommitted changes" were a pure
  shadow (all 13 files byte-identical to `origin/main`) → discarded, FF'd `main` 16 commits, deleted
  the branch (no duplicate commits). Then a **post-hoc Wave 5 engine code review** (hand-verified):
  9 findings + 1 false positive → see Next. 455 tests unchanged.
- **2026-06-22** — Docs only: slimmed this file **276 → 86 lines** back to the lean digest (no code,
  455 tests unchanged). All decisions confirmed already in `decisions.md` before trimming.
- **2026-06-20** — Finished the multi-folder watch-folder window, eyeballed it on real footage (single
  + dual folders, each writing to its own output, clean run), authored the overlap-rejection policy
  (an offline folder still blocks an overlapping add via its last-known path), then **merged all of
  Wave 5 — engine + UI — to `main`** and deleted the feature branch. 455 tests.
- **2026-06-18** — Built the watch-folder **engine** (file-stability + complete-set gates, FSEvents,
  relaunch resume) and added output-honesty polish: green shows only when a join is **verified
  byte-for-byte**, verify is folded into one progress bar, and the date/timecode write-back is now
  re-read and confirmed after each join.
- **2026-06-17** — **Shipped Sparkle auto-update → 1.0 is publicly live.** Also fixed a whole-queue
  "time left" that swung wildly (now extrapolates from the run's own observed pace) and a console
  freeze on large logs (lazy line-by-line rendering).
- **2026-06-16** — Made the repo **public** under PolyForm Noncommercial; re-cut the notarized DMG;
  fixed light/dark appearance + Dock-icon switching and "undated rows sort last in both directions".

## Backlog (all optional / post-ship)
- **Real-SD-card TCC + relaunch eyeball (5.14)** — see Now/Next; the only thing between current state
  and a fully-closed Wave 5.
- **More camera families = NEXT FOCUS** (engine is already camera-agnostic) — **hardware now in hand:
  DJI Osmo Action 1, GoPro 11, GoPro 7** (footage to be captured). Validate per-brand **filename
  grouping**, **metadata read**, and **telemetry/SRT sidecar** (sidecar may trail the video join per
  brand). On the in-app Roadmap.
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
- **Version 1.0.3 / build 103** — keep monotonic for Sparkle. (1.0.3 shipped 2026-06-25; appcast keeps both
  1.0.3 + 1.0.2 items.)
- **DMG** = current `main`, notarized + double-stapled, `/Applications` drop-link, ~29 MB, installs
  offline. **1.0.3 was cut on the M4 Pro** via `make-dmg.sh` (it holds the Developer ID identity, the
  `conjoyn-notary` profile, and the Sparkle key — the M1 Max is down). The `conjoyn-notary` keychain profile is
  **per-Mac** — recreate via `setup-notary-profile.sh` from `99-AUTH/` (memory
  `notary-credentials-recreation`). Re-cut only when a new build ships. **Ship recipe (verified 1.0.3):** bump
  `project.yml` + `xcodegen generate` → `make-dmg.sh` → `make-appcast.sh` → drop the staged
  `04_Exports/appcast/Conjoyn-<v>.dmg` + `appcast.xml` + `Conjoyn-<v>.html` into `App-Websites`
  `APPS/Conjoyn/01_Source/` (and overwrite `downloads/conjoyn.dmg` for the human button) → its `deploy.sh`.
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
