# Project State

> Lean digest. Full history → `docs/sessions/`; rationale → `docs/decisions.md`; sprint
> checkboxes → `docs/TASKS.md`.

## Identity
- **Project:** Conjoyn (brand lowercased **conjoyn**; bundle `com.lucesumbrarum.conjoyn`). Xcode
  project/target/module/.app = `Conjoyn`; source `01_Project/Conjoyn` + `ConjoynTests`; repo root
  folder `Conjoyn` (renamed from the `DJIjoiner` placeholder 2026-06-11).
- **One-liner:** native macOS app that auto-stitches split DJI drone MP4 segments into one lossless
  file, fixes the date/timecode metadata, and re-times the `.SRT` telemetry sidecar.
- **Started:** 2026-06-07 · **Last updated:** 2026-08-10 · **Tags:** macOS, video, DJI, metadata, ffmpeg.
- **Git:** canonical history at `github.com/Xpycode/Conjoyn` (public, **HTTPS via `gh`**, no SSH).
  Code syncs across Macs via **Syncthing, which excludes `.git`** → history travels **only via
  `origin`**. A fresh Mac (no `.git`) → run the **`git-bootstrap` skill**; **never `reset --hard`
  blind**. Commit identity `Luces Umbrarum <87826179+Xpycode@users.noreply.github.com>`.

## Now
- **Phase:** implementation — feature-complete and **shipped public** at **1.0.5 / build 105**
  (2026-08-10). **Tests: 618 app / 0 fail · 10 FeedbackKit pkg.** `main` == the shipped build.
- **Focus:** **GoPro camera-family support is complete** — waves **G0–G8 are closed** bar one
  footage-gated probe. A real recording's chapters group, join with telemetry byte-exact, verify at
  both tiers, keep the camera's own start timecode, the watch-folder knows when a GoPro set has
  finished arriving, and the interface (including the whole in-app Help book) no longer says DJI
  where it means "your camera". Spec `specs/gopro-camera-family.md` is **Implemented**; plan
  `IMPLEMENTATION_PLAN-gopro.md`. Osmo Action 1 + GoPro 7 stay footage-gated.
- **Blockers:** none for shipping. **G8.1 alone is open** and needs hardware: one ~30 s Hero 11 clip
  shot in **H.264** (→ `GH…`). No such file exists on V26 or the boot disk as of 2026-08-09, and
  mediaingest preserves the GoPro stem, so no rename is hiding one.
- **Next:** capture footage — the G8.1 Hero 11 **H.264** clip (~30 s → `GH…`), plus Osmo Action 1
  and GoPro 7 material for the next camera families. Nothing else is owed.
- Both release-note lines owed at 1.0.5 **shipped in its notes** (downgrade-to-1.0.4 clears the
  queue; GoPro joins from ≤1.0.4 carry a start timecode up to ~0.7 s early — re-join to correct).
- **Standing rule for every remaining wave** (both halves proven by deliberate reproduction): a new
  `DJIClip` field needs a `CodingKey`, a `decodeIfPresent` **and** a line in the hand-written
  `encode(to:)` — miss the decoder and a user's queue is silently wiped; miss the encoder and the
  field is silently never saved. A red `QueuePersistenceCompatTests` is stop-the-line, never a test
  to update. → `decisions.md` (2026-08-07).
- **G8.2 is load-bearing coverage, not a final eyeball** — the G4.3 seam fixtures can't match a
  camera original's stream order, so the real-footage join is the only thing that covers it.
  → `decisions.md` (2026-08-07). Related: ch01 of recording 6338 is no longer in the V26 archive
  (user-side clear-out, 2026-08-07); grouping tests are in-memory, so nothing is blocked.

## Recent (newest first — full logs in `docs/sessions/_index.md`)
- **2026-08-10 (latest)** — **Shipped 1.0.5 / build 105.** Suite green pre-cut (618 / 0 fail), both
  notary round-trips Accepted, app + DMG stapled, Gatekeeper OK. Appcast now serves 1.0.5 + 1.0.4 +
  1.0.3 (1.0.2 rotated out) with **two** binary deltas (105→104 264 KB, 105→103 298 KB). Website
  badge, notes page, appcast, DMG and `downloads/conjoyn.dmg` all deployed after a DRY_RUN preview;
  every live check byte-exact — appcast/notes/deltas `cmp`-identical, the DMG hash-identical via all
  three routes (versioned URL, `dl.php`, downloads swap). Release notes carry both owed lines.
- **2026-08-09** — **A real GoPro recording went through the finished app, and the check
  that mattered was the one nobody had written.** Recording 6349 (two chapters, 12.6 GB) joined
  perfectly: picture, sound and sensor data all came out byte-for-byte identical to the originals,
  the originals themselves were untouched, and the app's own seal passed at both depths. But the
  joined file's **start time was stamped a quarter-second early** — the app rebuilds that stamp from
  the recording's date, which is only accurate to the whole second, and throws away the camera's own
  frame-exact clock. That was the right call for DJI, whose clock is unreliable and usually blank;
  it's the wrong one for GoPro, whose clock the app *already* relies on to work out which pieces
  belong together. The app's seal couldn't have caught it, because that check asks "did we write
  what we meant to write", not "is what we meant right". Now the camera's own start time is kept
  whenever it agrees with the recording date, while DJI is left exactly as it was. Measuring the
  archive first changed the fix twice — every one of the 57 recordings agrees, so this corrects
  nearly every GoPro file, by up to 0.7 s; and the fastest recordings write the frame number in a
  padded three-digit form that had to be handled. Confirmed on two real clips. 605 → 618 tests.
- **2026-08-09** — **The app stopped saying "DJI" where it means "your camera".** The
  empty state no longer quotes a 4 GB card limit — no camera splits at a printable number, so the
  figure is simply gone — and a folder of unrecognised files now names both DJI and GoPro instead of
  calling GoPro footage a non-recording. The change was written as two strings and turned out to be
  far more: the **in-app Help book** still described a DJI-only app in 8 topics, so it was rewritten
  to cover GoPro's naming, how its chapters are recognised, and that its sensor data lives inside the
  video file rather than in a sidecar. Two things in the Help were simply wrong and were fixed: it
  listed the wrong order for how the recording date is worked out, and it still promised the
  watch-folder feature as "planned" three versions after it shipped. Copy-only; tests unchanged at 605.
- **2026-08-09** — **The watch folder now knows when a GoPro recording has finished
  landing on the card.** It was using DJI's rule — a recording is still growing while its last piece
  is bigger than about 4 GB — and GoPro's pieces are nearly three times that, with no fixed size at
  all. GoPro pieces are now judged against *each other*: the last one is smaller than the ones
  before it. The trap was the first moments of a copy, when only one piece exists and there is
  nothing to compare it against; the plan said to let the quiet period decide, which would have
  joined an 11.5 GB opening piece on its own and left the rest orphaned — worse than the shipped
  app. A size floor, measured from the real footage, keeps that case correct. Both halves were
  deliberately broken first to confirm the checks notice. 590 → 605 tests.
- **2026-08-09** — **The app now checks that GoPro's sensor data survived the join.** Both
  depths of the after-the-join check — the quick count and the exhaustive byte-for-byte one — were
  counting only picture and sound, so a recording could have lost its sensor data and still come out
  marked green. The obvious way to point the checker at the right piece of data quietly points it at
  the *clock* track instead on real camera files. A cold review then found three more routes to a
  false green, all closed. Proven on real Hero 11 footage, each check broken first to confirm it
  notices. 561 → 590 tests.
- **2026-08-08** — **GoPro recordings split across several files now get put back together as one.**
  DJI's rule — full at a size limit, next one continues by the clock — doesn't work for GoPro: there
  is no fixed limit, and one real recording writes the *same* start time onto both its parts. The
  camera's internal timecode is the signal that does work. All 71 archive files pinned as a permanent
  check. A recording missing its first part is flagged but **still joinable** — a user decision
  against the written spec, because the archive holds exactly such a recording. 542 → 561 tests.
- **2026-08-07** — **A real GoPro recording now joins with its telemetry intact.** GoPro hides its
  sensor data in a track *inside* the video file, and the timecode track looks like the same kind of
  track — so a natural-looking shortcut would have carried the wrong one and still looked like it
  worked. Proven on Hero 11 footage cut across a genuine chapter boundary, and checked by deliberately
  breaking the feature. 531 → 542 tests.

## Backlog (all optional / post-ship)
- **Search / filter in the recordings list** — user-raised 2026-08-09 while driving the G8.2 gate.
  A card folder can surface dozens of recordings (the H11 archive holds 70 videos among ~6,400
  files) and there is no way to jump to one. Deliberately not done mid-gate. Needs the UI-changes
  protocol: find the comparable control, trace its wiring, propose a location before editing.
- **Output name re-ingest guard** — with no rename template applied, the output takes the first
  segment's stem verbatim (`ConversionViewModel.swift:407-425`), so `…GX016349.mp4` still parses as
  a valid GoPro chapter 01 and could be re-ingested as source. The watch-folder path always appends
  `_joined` (`WatchFolderCoordinator.swift:503`); only the GUI-with-rename-off path doesn't. The
  same-folder overwrite case looks covered by the queue's collision counter (`QueueManager.swift:493`
  via `fileExists`, which catches `.MP4`/`.mp4` on a case-insensitive volume) — read, not tested.
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
- **Version 1.0.5 / build 105** — keep monotonic for Sparkle. The appcast keeps a rolling 3-item
  window (now 1.0.5 + 1.0.4 + 1.0.3; `generate_appcast` drops the oldest itself) **+ binary deltas**
  (105→104, 105→103). It emits a `Conjoyn<new>-<old>.delta` for every older DMG still in
  `04_Exports/appcast/` — **deploy them with the DMG**, else updaters on those versions 404 before
  falling back to the full download.
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
