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
- **Phase:** implementation — **100% feature-complete + SHIPPED PUBLIC**, version **1.0.2 / build 102**.
  **Tests: 455 app / 1 skip / 0 fail · 10 FeedbackKit pkg.**
- **Focus:** Watch-folder ingest (Wave 5) is **fully built — engine + multi-folder UI — and merged to
  `main`** (`c814efc`); only the **real-SD-card permission + relaunch-persistence eyeball (5.14)**
  remains before Wave 5 is formally closed.
- **Blockers:** none. 🎉 1.0-public is live; the last gate (Sparkle auto-update) is closed.
- **Next:** bring a **real removable SD card** (verify `diskutil` reports `Removable Media: Removable`
  first — the `2CULL` test drive reads as *Fixed*, so it never trips the TCC prompt) → confirm the
  `NSRemovableVolumesUsageDescription` prompt fires and watch folders survive a relaunch. Exact steps
  in the **2026-06-20 log Resume block**. On pass, Wave 5 closes and **Wave 6** (packaging /
  real-footage 6.3–6.5) is next.
- **Open follow-ups (deferred, from the 2026-06-23 engine review — verified, not blocking):** a
  `fix/wave5-watchfolder-hardening` branch covering **(1)** hung-`discover` deadlock (ffprobe hang ⇒
  `isRescanning` never clears ⇒ watcher silently dies — needs a timeout), **(2)** FSEvents teardown
  UAF race (`WatchFolder` `passUnretained`+`Invalidate` — add retain/release context callbacks), and
  **(3)** TOCTOU between enqueue and FFmpeg (cookbook #127 — capture+re-verify clip inode before
  `mergeClips`). Full table + 6 lower-severity items in the **2026-06-23 log**. Pairs naturally with
  the 5.14 eyeball before the watch-folder *daemon* use case gets real mileage.

## Recent (newest first — full logs in `docs/sessions/_index.md`)
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
- **More camera families** (engine is already camera-agnostic) — user's test set to be collected:
  GoPro 11 / 7 / 5 + DJI Osmo Action. On the in-app Roadmap (telemetry/sidecar may trail the video
  join per brand).
- **Localization / i18n** — app is English-only; future work is extract UI strings →
  `Localizable.xcstrings` + target languages.
- Optional DMG polish (custom background image).
- Footage-gated engine items: 2.2/2.3 reader polish, 2.7 TS-remux fallback, Apple `Keys`
  creationdate atom (6.3).
- Owed eyeballs (low-risk, unit-tested only): adaptive ETA in a current build; live AppCitizenshipKit
  menu/About surfaces; slow-mo + SRT-mismatch integrity chips (no such clip seen on cards yet).

## Risks
- **SRT offset-correction stitching** = highest-uncertainty v1 item (per brief). Engine implemented +
  footage-validated; scope-creep flagged but user-chosen.
- ~~FFmpeg GPL~~ **RESOLVED** — reproducible static arm64 **LGPL** FFmpeg 8.1 (no GPL/nonfree),
  validated lossless on real footage; build via `01_Project/scripts/build-ffmpeg-lgpl.sh`
  (binaries gitignored).

## Infrastructure (operational reference)
- **Version 1.0.2 / build 102** — keep monotonic for Sparkle.
- **DMG** = current `main`, notarized + double-stapled, `/Applications` drop-link, ~29 MB, installs
  offline. Cut on the **M1 Max** via `make-dmg.sh`. The `conjoyn-notary` keychain profile is
  **per-Mac** — recreate via `setup-notary-profile.sh` from `99-AUTH/` (memory
  `notary-credentials-recreation`). Re-cut only when a new build ships (Debug-local work since 1.0.2
  has not changed the shipped artifact).
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
