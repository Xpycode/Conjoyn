# Project State

> Lean digest. Full history → `docs/sessions/`; rationale → `docs/decisions.md`; sprint
> checkboxes → `docs/TASKS.md`.

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
- **Phase:** implementation — feature-complete and **shipped public** at **1.0.4 / build 104**
  (2026-07-18). **Tests: 531 app / 0 fail · 10 FeedbackKit pkg.**
  ⚠️ **`main` is ahead of the shipped build** — the renamed-footage parser fix (2026-08-06) and the
  GoPro parser are on `main` but not in 1.0.4, so renamed folders still scan empty in the installed
  app until the next version bump.
- **Focus:** **GoPro camera-family support** — spec `specs/gopro-camera-family.md` (all 6 open
  questions resolved 2026-08-07), plan `IMPLEMENTATION_PLAN-gopro.md` (waves G0–G8). **G0
  (queue-persistence safety net), G1 (filename parsing) and G2 (probe extension) are closed**; G4 is
  next. Osmo Action 1 + GoPro 7 stay footage-gated — hardware in hand, nothing shot.
- **Blockers:** none.
- **Next:** **`/execute` Wave G4** (G4.1–G4.3) — teach the ffmpeg arg builder a gpmd `-map` index,
  resolve that index at join time, and prove a **real** GoPro seam joins with telemetry intact. Taken
  before G3 deliberately (the plan's vertical slice **G1 → G2.1 → G4.1/G4.3**), because it retires the
  two highest technical risks: whether `-map 0:<i>` works against the concat demuxer at all, and
  whether the index is resolved from the right file. Seam slices must come from recording **6347 or
  6345**, not 6338 (its ch01 left the archive). One ~30 s Hero 11 clip in **H.264** is still owed from
  capture (G8.1).
- **Standing rule for every remaining wave** (both halves proven by deliberate reproduction): a new
  `DJIClip` field needs a `CodingKey`, a `decodeIfPresent` **and** a line in the hand-written
  `encode(to:)` — miss the decoder and a user's queue is silently wiped; miss the encoder and the
  field is silently never saved. A red `QueuePersistenceCompatTests` is stop-the-line, never a test
  to update. Rationale → `decisions.md`, 2026-08-07.
- **Source-footage note (2026-08-07):** ch01 of recording 6338 (11.5 GB) is no longer in the V26
  archive folder — user-side clear-out, no Conjoyn run touched it. Spec fixture numbers keep the
  71-file measurements (grouping tests are in-memory), so nothing is blocked.

## Recent (newest first — full logs in `docs/sessions/_index.md`)
- **2026-08-07 (latest)** — **The app now keeps track of where GoPro's telemetry lives inside a
  file.** Nothing uses it yet; this only stops the information being thrown away when a file is
  inspected. Worth doing carefully because the position moves — it sits in a different slot when a
  clip has no sound, and different again in a re-wrapped file — so anything assuming a fixed slot
  would quietly point at the wrong track. Checked against real Hero 11 footage rather than invented
  examples. Two things the plan had wrong turned up: a fallback it specified could never have run,
  and the change isn't quite invisible to existing DJI footage the way it assumed — both written
  down rather than papered over. 525 → 531 tests.
- **2026-08-07** — **The app can now read GoPro filenames.** It recognises GoPro's numbered
  chapters alongside DJI's naming, including footage an archiving tool has renamed; checked against
  all 71 real Hero 11 files. The folder scan needed no change — worth checking rather than assuming.
  One real catch: storing which camera a clip came from forced the save-to-disk code to be written by
  hand, quietly creating the mirror of last session's bug, now guarded. 512 → 525 tests.
- **2026-08-07** — **Built the safety net that had to exist before GoPro support touches saved data.**
  Adding one new piece of information to a recording would have made the whole saved queue unreadable,
  at which point the app throws the queue away silently. Reproduced first, then made lenient, with a
  real shipped-version queue checked in as a permanent test. 495 → 512 tests.
- **2026-08-07** — **Wrote the plan for GoPro support: 20 tasks, 9 waves.** Reading the real code
  first turned up five decisions the spec had left open, two of them traps — where the chapter number
  gets stored, and how the telemetry track is identified. Both written down so they can't be
  re-discovered the hard way. Nothing built yet.
- **2026-08-07** — **Settled every open question about GoPro support.** The one that mattered:
  telemetry in a joined file is still *readable*, not merely byte-identical — the camera's clock runs
  from the start of the whole recording, not each chapter, so a joined file is coherent end to end.
## Backlog (all optional / post-ship)
- **More camera families** — GoPro is specced and in progress (above); **Osmo Action 1 + GoPro 7**
  remain footage-gated. The empty state's "4 GB card limit" figure (`RecordingsList.swift:501`) will
  **drop the number** rather than name a per-camera one (no camera splits at a printable figure).
  On the in-app Roadmap.
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
- **Version 1.0.4 / build 104** — keep monotonic for Sparkle. The appcast keeps 1.0.4 + 1.0.3 + 1.0.2
  items **+ a 104→103 binary delta**. `generate_appcast` emits a `Conjoyn<new>-<old>.delta` whenever
  the previous DMG is still in `04_Exports/appcast/` — **deploy it with the DMG**, else updaters on
  the previous version 404 before falling back to the full download.
- **DMG** = current `main`, notarized + double-stapled, `/Applications` drop-link, ~29 MB, installs
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
  `docs/TASKS.md` — sprint checkboxes · `IMPLEMENTATION_PLAN-gopro.md` (repo root) — **the active
  plan**, waves G0–G8 · `specs/gopro-camera-family.md` — GoPro spec · `IMPLEMENTATION_PLAN.md` +
  `specs/dji-auto-stitcher.md` — the shipped v1 plan and spec.
</content>
</invoke>
