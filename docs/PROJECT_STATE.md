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
  appcast + 104→103 binary delta live). **Tests: 512 app / 0 fail · 10 FeedbackKit pkg.**
  ⚠️ **`main` is AHEAD of the shipped build** since 2026-08-06: the renamed-footage parser fix is on
  `main` but not in 1.0.4, so renamed folders still scan empty in the installed app until the next bump.
- **Focus:** **Wave 5 (watch-folder ingest) is fully closed AND daemon-hardened** — engine + multi-folder
  UI merged to `main` (`c814efc`), the **real removable-SD-card eyeball (5.14) PASSED 2026-06-24**, and the
  **3 worth-fixing engine-review items are now fixed + merged** (2026-06-24, `fix/wave5-watchfolder-hardening`
  → `main` `2905b38`). **Wave 6 is now effectively closed; current focus = GoPro camera-family
  support** — spec written 2026-08-07 at `specs/gopro-camera-family.md`, grounded in 71 real
  Hero 11 clips; **all 6 open questions resolved the same day**. Scope locked: preserve the in-container
  `gpmd` telemetry track through the join · add a camera-family layer but **keep** the DJI type
  names (rename deferred) · GX/GH chaptered naming only. Osmo Action 1 + GoPro 7 remain
  footage-gated (hardware in hand, nothing shot yet).
- **Blockers:** none. 🎉 1.0-public is live; the last gate (Sparkle auto-update) is closed.
- **Wave G0 — DONE (2026-08-07, merged `38752f8`).** The queue-persistence safety net is in: a real
  shipped-1.0.4 `queue.json` checked in as a fixture, a hand-written `DJIClip` decoder (explicit
  `CodingKeys` + `decodeIfPresent`), and tolerant decode for the three persisted verification enums.
  The hazard was **reproduced against the net before fixing** — a probe `var` on `DJIClip` failed all
  10 fixture tests with `keyNotFound` at `[0].clips[0]`. **Tests: 512 app / 0 fail** (495 → +17).
  Rationale in `decisions.md` (2026-08-07, "Queue persistence"). Standing rule for every later wave:
  a new `DJIClip` field goes in `CodingKeys` **and** uses `decodeIfPresent`; a red
  `QueuePersistenceCompatTests` is stop-the-line, never a test to update.
- **Next:** **`/execute` Wave G1** (`G1.1`/`G1.2` — `CameraFamily` + tail-anchored GoPro `GX`/`GH`
  regex, then parser tests over all 71 corpus filenames), continuing the thin vertical slice
  **G1.1/G1.2 → G2.1 → G4.1/G4.3**: prove a real GoPro seam joins with telemetry intact before
  building grouping/gate/copy on top — that retires the two highest technical risks (does
  `-map 0:<i>` actually work against the concat demuxer, and is the index resolved from the right
  file). Five further design calls were locked while
  planning (recorded in the plan, to `decisions.md` at close-out): chapter number rides in `DJIClip.index`
  (so "last segment" and the consecutive check keep working) while a new `recordingNumber` carries
  recording identity; the grouping bucket key becomes `family|variant|recordingNumber`; the gpmd `-map`
  index is probed from **segment 1 at join time**, never from persisted state; nothing selects telemetry as
  `d:0` (ffprobe calls `tmcd` a data stream too, so `d:0` can silently verify the timecode track instead);
  and a GoPro chain without timecode on both sides simply doesn't chain. Already proven on real footage:
  the concat join carries `gpmd` byte-exactly (6338 pair → 165,299 video / 77,484 audio / 1,653 gpmd
  packets, all exact sums), and `-map 0` fails outright because the `tmcd` track has codec `none`. Only
  capture still owed: one ~30 s Hero 11 clip shot in **H.264** (G8.1).
  ⚠️ **Source-footage note (2026-08-07):** `H11--2026-08-03--11-52-11--GX016338.MP4` (ch01 of recording
  6338, 11.5 GB) is no longer in the V26 archive folder — 71 files at the 2026-08-06/07 probe, 70 now.
  User-side clear-out (the separate `2026-07` folder was deleted the same day); no Conjoyn run touched it.
  Spec fixture numbers keep the 71-file measurements (grouping tests are in-memory), so nothing is blocked.
- **Wave 6 (previous focus, closed):** **6.3 (legacy *and* timestamped + slow-mo) + 6.4 SRT alignment
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
- **2026-08-07 (latest)** — **Built the safety net that had to exist before GoPro support can touch
  the app's saved data.** The app remembers its queue between launches, and the way it re-reads that
  file was strict enough that adding a single new piece of information to a recording would make the
  whole file unreadable — at which point the app quietly throws the user's entire queue away and says
  nothing. Rather than assume that, it was reproduced first: adding a dummy field broke the read
  exactly as predicted. It's now read leniently, so anything it doesn't recognise is skipped instead
  of discarded, and a real saved queue from the shipped version is checked in as a permanent test —
  if a future change would break someone's queue, that test goes red before the change ships. One
  surprise worth keeping: the failure only happens for *some* ways of declaring a field, and the
  other way looks identical and is silently safe, which is exactly how this would have been missed.
  495 → 512 tests.
- **2026-08-07** — **Wrote the plan for GoPro support: 20 tasks, 9 waves.** Reading the
  actual code before planning turned up five decisions the spec had left open, and two of them were
  traps. The chapter number has to be stored in the field the app already uses for "which piece of the
  recording is this" — the more obvious choice would have quietly broken how the watch-folder finds a
  recording's last piece. And the telemetry track can't be picked by asking for "the first data
  stream", because the timecode track answers to that name too — the check would have passed while
  looking at the wrong thing. Both are now written down so they can't be re-discovered the hard way.
  The plan's first task is the safety net: prove a queue saved by the shipped version still loads,
  *before* anything touches the file format, because getting that wrong silently empties a user's
  queue. Nothing built yet.
- **2026-08-07** — **Settled every open question about GoPro support, so it can be planned.**
  The one that actually mattered: we already knew the telemetry track survives a join byte-for-byte,
  but not whether anything could still *read* it afterwards — a camera that restarts its clock in each
  chapter would produce a file that looks perfect and reads as nonsense. It doesn't: the timestamps run
  from the start of the whole recording, not the chapter, so a joined file is coherent end to end. Also
  decided: no hard-coded file-size limit for GoPro (the cameras don't agree on one — the Hero 11 splits
  near 11 GB, the older Hero 7 near 4), the "4 GB card limit" line in the empty state loses its number
  because no number is true for every camera, and the saved-queue file gets a proper reader before any
  new field is added, so an update can't wipe a user's queue. Nothing built yet — next step is the plan.
- **2026-08-06** — **Fixed: a folder of renamed footage scanned as completely empty.** The
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
*(older entries trimmed per the lean-digest rule — full history in
`docs/sessions/_index.md` and dated logs under `docs/sessions/`.)*

## Backlog (all optional / post-ship)
- **Real-SD-card TCC + relaunch eyeball (5.14)** — see Now/Next; the only thing between current state
  and a fully-closed Wave 5.
- **More camera families — GoPro is now SPECCED** (`specs/gopro-camera-family.md`, 2026-08-07); the
  engine generalises better than expected (the size-cap and stream-param rules already fire correctly
  on GoPro; only the time rule inverts — GoPro chapters share one `creation_time`, so continuity comes
  from **timecode**, exact at all 15 chapter transitions measured). Still footage-gated: **Osmo Action 1
  + GoPro 7** (hardware in hand, nothing shot) and one ~30 s H.264 clip to sanity-check GH naming. The
  Hero 11 splits at **~10.7–10.8 GiB**, not the 4 GB the empty-state copy claims
  (`RecordingsList.swift:501`) — but that copy will **drop the figure** rather than name a per-camera one
  (decision 2026-08-07: no camera splits at a number worth printing). On the in-app Roadmap.
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
  `specs/dji-auto-stitcher.md` — spec + acceptance criteria · `specs/gopro-camera-family.md` — GoPro
  camera-family spec (2026-08-07, Draft) · `IMPLEMENTATION_PLAN-gopro.md` (repo root) — **the active
  plan**, waves G0–G8 · `IMPLEMENTATION_PLAN.md` — the shipped v1 7-wave plan · `docs/TASKS.md` —
  sprint checkboxes · **2026-06-20 log Resume block** — exact SD-card (5.14) test steps.
