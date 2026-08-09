# Decisions Log

This file tracks the WHY behind technical and design decisions for DJIjoiner.

---

### 2026-06-12 - Ship Conjoyn ONLY with Sparkle auto-update; DMG enclosure, automatic checks, debut as 1.0
**Context:** A `/status` review (2026-06-12c) surfaced that Conjoyn has **no auto-update mechanism** —
a full code search found zero Sparkle/appcast integration; "notarized" had been conflated with
"distribution done." No installed base yet (website not live), so adding it is greenfield. 3-agent
recon → `docs/sparkle-research.md` (2026-06-12d); this session verified it against P2toMXF (verbatim
port source), Penumbra's release runbook, and the live Sparkle **2.9.3** docs, then planned it in
`docs/plans/sparkle-auto-update.md`.
**Decision:** (1) **Ship only with the update function** — the first public download IS the first
Sparkle-enabled build; no update-less interim release. (2) **DMG-only enclosure** — one notarized DMG
serves both the website button and Sparkle's `<enclosure>` (matches the existing `make-dmg.sh`; no
binary deltas, which are pointless with no installed base + a 27 MB app). (3) **Automatic + menu**
checks (`SUEnableAutomaticChecks=true` daily background + a manual "Check for Updates…" item).
(4) **Debut as 1.0 / build 100** — `MARKETING_VERSION=1.0`, `CURRENT_PROJECT_VERSION=100` (monotonic
int, room to grow); the shipped binary is actually `0.1.0/build 1` ("v1.0.1" was narrative naming),
and since it was never publicly distributed this is a clean reset. (5) **Sparkle `from: 2.9.3`**
(upToNextMajor; carries the 2.9.2 security fixes). (6) **Self-host** the appcast at
`conjoyn.lucesumbrarum.com` (Penumbra pattern); enclosure points at the **raw DMG**, not the
counted/302 PHP endpoint.
**Why:** A notarized app that can't update itself silently rots — users never get fixes and there's no
recall path. Doing it now, before any installed base, is the cheapest moment (no orphaned old
versions). Conjoyn is the **simplest case in the app family** because it's non-sandboxed: the existing
FFmpeg entitlements (`cs.disable-library-validation` + `allow-unsigned-executable-memory` +
`allow-jit`) are exactly what Sparkle's XPC needs, so **zero new entitlement, zero new build setting** —
just the SPM dep + 3 base-Info.plist keys (`SU*` in the base plist, not `INFOPLIST_KEY_*`, per cookbook
#89) + a ported `UpdaterController`. **Open at execution:** the `--account` key-isolation flag is
unverified (Penumbra's docs use it; Sparkle's official page doesn't document it) — resolved by checking
`generate_keys --help` and relying on `-x` export + 2× key backup either way. **Load-bearing risk:**
EdDSA private-key loss permanently orphans all users (real incident: SyncthingStatus v1.5→1.5.1), so the
key is generated fresh + backed up twice before the first signed release.

---

### 2026-06-10 - Card-aware folder descent (drop a card root, not just the leaf media folder)
**Context:** Live UI test exposed that dropping/choosing a card **root** (`/Volumes/M4P-1`) reported
"No video segments found" — `DJIFolderReader.read` scanned only the chosen folder
(`.skipsSubdirectoryDescendants`), but DJI clips live in `DCIM/DJI_001`. The user had to drill into
the media folder by hand. CLAUDE.md already said discovery should run "over DCIM/`100MEDIA`" and the
empty-state copy invites "drop a card," so this was a real gap, not new scope.
**Decision:** Chose **shallow, card-shaped descent** over full recursion. New internal
`resolveMediaFolders(startingAt:)`: returns the folder unchanged when it directly holds DJI video
(common fast path); otherwise treats a `DCIM` container (under the folder, or the folder itself when
it *is* DCIM) — and the folder itself for DCIM-less cards — as parents whose *immediate* subfolders
are media folders, and pools those that hold DJI video. **Bounded to one subdirectory level** (card
root → `DCIM` → media folder); falls back to `[folder]` when nothing is found so the empty scan still
names the dropped folder. Multi-folder cards pool sorted (`DJI_001` before `DJI_002`).
**Why:** A "drop a card" affordance must work on the card root, but **full recursion is a footgun** —
dropping a home folder would enumerate tens of thousands of files. Bounding to real camera-card
layouts (the only shape we promise) gets the ergonomics with no deep-walk risk; a `testDescentIsBounded`
case pins it. Grouping is by metadata continuity + the stream-param guard, so pooling clips across
`DCIM/*` subfolders can't wrongly merge distinct recordings. **Caveat:** cross-folder filename-index
collisions only matter when `creation_time` is missing (ordering then falls back to index/stem) — an
existing limitation, not introduced here.

---

### 2026-06-10 - Help window: defer (but adopt the reusable `AppHelp` package when built); no Settings scene
**Context:** User asked whether a **Help menu/window** and a **Settings window** had ever been
scoped for Conjoyn. Audit found **neither was ever discussed** — no session log, decision, spec, or
`ideas.md` entry. Current `ConjoynApp.swift` is a bare `WindowGroup`: **no `Settings` scene, no
`.commands { }`, no Help wiring**, so the app ships only the stock macOS menu bar (default
About/Quit + an empty Help search field; ⌘, is a no-op). User maintains a separate standalone Swift
package at `/1-macOS/AppHelp/` — a drop-in `HelpMenu` library (sidebar + markdown-detail
`HelpWindowController`/`HelpWindowView`, `HelpTopic`/`HelpContent` models, swift-markdown-ui
rendering, **both** `SwiftUIHelpCommands` and `AppKitHelpMenu` integration shims).
**Decision:** (1) **No Settings scene** — Conjoyn has no persistent cross-launch preference to house.
Every tunable is already in-context (output-bar switches + the gear popover for engine knobs; rename
& date-override are deliberately session-only on the ViewModel, kept off the `Codable`
`ConversionSettings`). A Settings window would be hollow today. Revisit only if a persisted default
(output folder, default container) or **watch-folder config** (still unbuilt) lands. (2) **Help —
deferred backlog item, not now.** When done, vendor the existing `AppHelp` package rather than
hand-rolling (it's turnkey; `33_app-minimums.md` lists a Help menu as a baseline for notarized
direct-distribution apps). The real cost is *content*, not wiring: topics for continuity-grouping,
the camera-variant guard, the date/timecode model, SRT stitching, watch-folder.
**Why:** Don't add empty chrome. Settings scenes exist to persist app-global prefs; Conjoyn has
none, and forcing one now contradicts the deliberate "rename/override state is per-run" decision.
Help is genuinely valuable but lower-priority than the owed items (single-file export, DMG, UI-state
eyeballing), and the heavy lifting is writing topic content — so park it with the component already
identified.

---

### 2026-06-10 - Reframe "Preserve timecode" as "Timecode from recording time" + surface it per job
**Context:** The 2026-06-10 design handoff bar still labeled the TC toggle **"Preserve timecode."**
That's misleading: DJI's source `tmcd` is almost always `00:00:00:00`, and the engine has (since the
2026-06-09 "date+timecode stamp model" decision) **derived** the output start TC from a resolved
recording-start wall-clock — it preserves nothing. User flagged the wording and asked to (a) call it
"TC from creation time" and (b) make the source-vs-applied difference visible, with a slow-mo
explanation.
**Decision:** Relabel the toggle **"Timecode from recording time"** (behavior unchanged; internal
`preserveTimecode` symbol kept). Surface the transformation **per job in the queue row** (user's
pick over a toggle popover or always-inline caption): **Source TC** (`00:00:00:00`, inert) vs
**Applied TC** (`HH:MM:SS:FF`) with an **origin tag** (from SRT cue / filename / file date / manual)
and the frame rate, **behind a disclosure caret on the row** (row stays single-line; caret expands
an inline panel — keeps the queue compact, detail on demand). When a group has a slow-mo clip, add a one-line note: TC **starts** at the real
recording instant and **advances at the file's playback fps** — the start is unaffected by slow-mo;
only the frame-rate tag follows the container. **No engine/export change** — expose values the
resolver already computes. See `specs/rename-and-tc-disclosure.md`.
**Why:** Honesty over magic. "Preserve" implied a fidelity we don't (and can't) provide; showing
source→applied with provenance lets the user trust and, if needed, override the stamp.

---

### 2026-06-10 - Rename Joined Files: counter restarts per batch; collisions auto-suffix
**Context:** The rename-popover handoff (`02_Design/design_handoff_rename_popover/`) left two product
questions open: (1) does the `{###}` counter restart or continue across Add-to-Queue batches, and (2)
what happens when two outputs resolve to the same name.
**Decision:** (1) The counter **restarts at "Start at" for each batch** (simple, predictable; matches
the handoff default). (2) Name collisions — within a batch, against the existing queue, or against a
file already in the destination — **auto-suffix** `_2`, `_3`, … until unique (never lose a file;
stays close to the pattern); the `.SRT` sidecar follows the suffixed stem. The output name is decided
**once at Add-to-Queue** and frozen onto the job. Rename bypasses the default namer, so it also
side-steps the doubled camera-variant-suffix bug (tracked separately). See
`specs/rename-and-tc-disclosure.md`.
**Why:** Per-batch restart keeps numbers meaningful per ingest action; auto-suffix favors
no-data-loss over strict pattern purity, consistent with the app's "never destroy footage" posture.

---

### 2026-06-09 - Free-space preflight must not trust `volumeAvailableCapacityForImportantUsageKey` off the boot volume
**Context:** Driving the full GUI pipeline on the real card, every join to the external `2CULL` drive
failed the pre-join disk-space preflight with **"Zero KB free"** — despite 822 GB actually free
(`df`). `DiskSpace.availableCapacity` queried `volumeAvailableCapacityForImportantUsageKey` first and
only fell back to the legacy `volumeAvailableCapacityKey` when the former was **nil**. That key is an
Apple **boot-volume** convenience (it accounts for purgeable space): on external/secondary APFS
volumes it returns **`0`, not `nil`**, so the code accepted `0` as the answer. Confirmed with a Swift
probe — on `2CULL`: importantUsage `= 0`, legacy `= 882 GB`; on the boot volume: importantUsage
`59.8 GB` > legacy `45 GB`. **Impact:** the app could not join to *any* SD card / external SSD — the
overwhelmingly common real-world destination — even though it's where DJI footage lives. Engine-level
tests never caught it because they write to temp dirs on the boot volume.
**Decision:** Keep `importantUsage` as the preferred signal (it's the more accurate "what you can
actually write" figure *on the boot volume*), but treat a **non-positive** value as a miss and fall
back to the legacy raw capacity. Extracted a pure `DiskSpace.usableCapacity(importantUsage:legacy:)`
for that selection so it's unit-tested directly (incl. the exact `0 → 882 GB` external-volume case).
**Lesson:** validate I/O-bound features against the *real* destination medium (external/removable),
not just boot-volume temp dirs. (Fix: `fix/diskspace-external-volume` → `main`, +4 tests.)

---

### 2026-06-09 - Resolved-wall-clock is authoritative for the date+TC stamp; manual override (supersedes "TC authoritative")
**Context:** Two earlier decisions quietly conflict. *"Timecode is authoritative for the metadata
fix"* (2026-06-07) said treat the source start-timecode as ground truth and rewrite the date to
match. But the later research-revised grouping decision (same day) established that DJI's embedded
`tmcd` start timecode is **almost always `00:00:00:00`** and its `creation_time` is **frequently
wrong** (the QuickTime 1904/1951-epoch bug + timezone shifts). So "trust the source TC" has, in
practice, nothing real to trust — there is usually no meaningful source timecode to be authoritative
about. This blocked wiring task 2.8 (`JoinMetadata` stamping), which currently stamps nothing.
**Decision:** Invert the model. The authoritative value is a **resolved recording-start wall-clock**,
derived from a source-priority chain; **both** the date atoms **and** the output `tmcd` start-timecode
track are *derived from that one resolved value*, never read from the (empty) source `tmcd`. Plus a
**manual override** so the user can set the date/time when every automatic signal is missing or wrong.
Resolution order (best DJI signal first):
1. **SRT telemetry first-cue wall-clock** — DJI writes a real timestamp into the `.SRT`; most reliable.
2. **Filename-embedded datetime** — the new scheme `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>` carries it.
3. **Embedded `creation_time`** — corroborating only; used when sane (reject the 1904/1951 epoch + TZ outliers).
4. **Filesystem `creationDate`** — reliable only on a fresh SD-card read (resets on Finder copies).
5. **Manual override** — always available; wins when set. Surfaces as the resolved value otherwise.
Source `tmcd` is honored **only if non-zero** (rare). The resolved wall-clock + frame rate produces
the `-timecode HH:MM:SS:FF` argument; the same date produces ISO-8601 `creation_time` +
`com.apple.quicktime.creationdate`; the native atom writer then patches the header atoms post-mux.
**Rationale:** Uses the signals DJI actually writes correctly, matches the brand-agnostic roadmap
(SRT/filename generalize; a zeroed `tmcd` does not), and keeps one source of truth so the date the
user sees, the date in Finder/Photos, and the start of the TC track can never disagree. Manual entry
covers the genuine "no usable signal" tail without the app guessing.
**Port source — Penumbra (`~/ProgrammingProjects/1-macOS/Penumbra`), proven & shipped:**
- `Utils/DateCorrectionResolver.swift` — the source-priority `Resolution{date, provenance, mismatchDetected}`
  pattern (Penumbra's chain is filename→filesystem; we extend the front with SRT + sane-`creation_time`).
- `Utils/TimecodeFormatter.swift` — `wallClockTimecode(for:frameRate:isDropFrame:)` derives the
  `-timecode` string from a Date; `ISO8601Z.format` for the `creation_time`/`creationdate` values.
- `Utils/SourceTimecodeReader.swift` — TN2310 `tmcd` reader (to detect a non-zero source TC).
- Manual override: Penumbra's per-item `dateOverride: Date?` with `effectiveDate = dateOverride ?? resolvedDate.date`
  (`Models/ExportDialogModel.swift`) + the "Override…" popover (`Views/ExportDialogView.swift`).
- `ExportManager.swift` — the assembly + **critical FFmpeg gotcha**: when emitting `-timecode` you
  MUST drop the source data/`tmcd` track (our join already does `-map -0:d`), else `-c copy` passes
  the old `tmcd` through and FFmpeg silently ignores `-timecode`.
**Consequences:**
- Task 2.8 wiring is now specified: populate `JoinMetadata.timecode` + `.creationTime` from the
  resolver, not from segment-1 `tmcd`. Keep the param guard + `-c copy` lossless path untouched.
- New unit-testable piece: a `DateCorrectionResolver` adapted for DJI (SRT-first), + a "mismatch
  detected" surfacing when sources disagree beyond a threshold (port Penumbra's comparator).
- UI gains a per-group resolved date/TC readout with provenance + an override control (Wave 6).
- Reframes, does not delete, the 2026-06-07 "TC authoritative" entry — "authoritative" now means the
  *resolved wall-clock*, with the TC track derived from it rather than dictating it.

**Implemented 2026-06-09 (s7).** `Services/RecordingStartResolver.swift` (chain: manual override →
SRT first-cue → filename → sane embedded `creation_time` → filesystem, with a 2010-floor/now+1d
sanity gate and a timezone-safe SRT↔filename mismatch flag) + `QueueManager.resolveJoinMetadata`
deriving both `creation_time` (ISO-8601Z) and the `tmcd` start TC (`HH:MM:SS:FF`) from the one `Date`,
gated by `fixCreationDate`/`preserveTimecode` + the new `ConversionSettings.dateOverride`.
`TimecodeFormatter.wallClockTimecode`/`ISO8601Z` ported from Penumbra. Two pragmatic extensions to the
spec: the mismatch comparator is **wall-clock-only** (the absolute embedded/filesystem dates are
excluded so a legitimate UTC offset can't masquerade as a mismatch), and zone-free signals are
interpreted in `Calendar.current` (correct when the editing machine shares the capture zone — the
unambiguous, TZ-carrying Apple `Keys` `creationdate` atom that removes that assumption stays Wave-6 /
task 6.3). **Validated on real footage** (card `DJI_001`, split `0008+0009`): stamped
`creation_time=2026-05-21T17:53:03Z` + `timecode 19:53:03:11` from the SRT first cue at 25 fps, with
DJI's `djmd`/`dbgi` data + `mjpeg` preview tracks dropped and a fresh `tmcd` written (`-map -0:d`
gotcha confirmed handled). UI readout/override control remain Wave 6.

### 2026-06-09 - Chose "Conjoyn" as the product name (rebrand off "DJIjoiner")
**Context:** "DJIjoiner" is a placeholder with two problems: (a) shipping a notarized, directly-
distributed app with "DJI" in the name is a trademark risk independent of the roadmap, and (b) the
join engine is brand-agnostic and the product will add GoPro / DJI Osmo / multi-brand support —
the "DJI" name locks in the one brand we've proven we'll outgrow. Rebrand cost only rises per
release (bundle id, signing, docs), so do it pre-1.0.
**Options Considered (camera-agnostic, coined/evocative; vetted by web/App-Store/domain search):**
1. **Conjoyn** (coined: conjoin+join) — zero collisions found; trademark-strong (coined); clear
   meaning; con of needing to be spelled aloud.
2. Unsplit — crystal-clear to users, `.app` likely free, but *descriptive* → weak/​hard to defend.
3. Reelm (reel+realm) — evocative, brand-clean, but `reelm.app` likely already registered.
4. Seamr — diluted: active "Seamr Labs" data co + taken `seamr.com`/GitHub handle.
   Killed in vetting: Weldr (weldr.dev), Onecut (App Store video apps), Splyce (≈Splice/esports),
   Mendr (photo app), Continua (≈Continuum/Boris FX + Continua Group), Spool (Mac App Store app).
**Decision:** **Conjoyn.** Bundle id `com.lucesumbrarum.conjoyn`. Working tagline: "Split
recordings, made whole."
**Rationale:** Coined → most ownable/trademarkable of the set; transparent "join" meaning; truly
brand-agnostic (fits multi-camera future); no software/App-Store/domain collisions surfaced.
**Consequences:** Rebrand is a deliberate step touching app name, bundle id, signing, scheme,
icon, copy. The Xcode project is **confirmed xcodegen-driven** (`01_Project/project.yml` is the
source of truth, `.xcodeproj` gitignored, sources are directory globs), so the rename is mostly
edit-`project.yml`-then-`xcodegen generate`, not hand-patching the pbxproj.
**EXECUTED 2026-06-09.** Renamed project/targets/module/bundle to `Conjoyn`; source folders
`git mv`'d to `01_Project/Conjoyn` + `ConjoynTests`; 19 test imports, `ConjoynApp`, entitlements,
runtime storage paths, and build scripts updated; `Conjoyn.xcodeproj` regenerated. **Visible brand
is lowercase `conjoyn`** (`CFBundleDisplayName`); binary/module/.app stay PascalCase `Conjoyn` so
`TEST_HOST` + `import Conjoyn` resolve cleanly (a lowercase `PRODUCT_NAME` broke the test host).
**The repo root folder + git were intentionally left `DJIjoiner`** — renaming them would break the
working directory, derived data, and `~/.claude` memory paths for little gain; revisit only if the
project moves. Clean build + full suite green (195/195).
**Clearance — sufficient for a free app, DONE.** USPTO exact-match search returned **no results** for
"Conjoyn" (2026-06-09); web + Mac App Store + the user's own Kagi/Google passes were also clean. For a
free, non-commercial app the realistic exposure is a rename-demand, not damages, so a coined name that
no software product already uses is adequate clearance — no paid search, EUIPO filing, or self-
registration needed. (The famous-mark dilution risk that *did* matter — "DJI" — is exactly what this
rename removes.)

---

### 2026-06-09 - Swapped interim GPL FFmpeg for a from-source static LGPL build (task 6.1)
**Context:** The bundled helpers were OSXExperts 8.1 — a full `--enable-gpl` build (x264/x265/…),
a release blocker (GPL source-distribution burden, MAS-incompatible). A copy-only joiner needs
none of the GPL encoders.
**Decision:** Build `ffmpeg` + `ffprobe` from unmodified FFmpeg 8.1 source via
`01_Project/scripts/build-ffmpeg-lgpl.sh`: `--enable-static --disable-shared`, **no**
`--enable-gpl`/`--enable-nonfree`, `--disable-network --disable-autodetect` (hermetic — won't link
stray Homebrew GPL libs). License defaults to LGPL v2.1+. Kept the full built-in codec/demuxer/
muxer set (no `--disable-everything`) so no DJI container quirk can break a join.
**Rationale:** LGPL = lighter legal burden, smaller app (20 MB vs 52 MB each), self-contained
(only system frameworks linked). Reproducible recipe in-repo, as decisions.md (2026-06-07) required.
**Validation:** `ffmpeg -L` reports LGPL; `otool -L` shows only `/usr/lib` + `/System` frameworks;
real-footage test (card `DJI_001`) — ffprobe JSON read OK, concat `-c copy` join exact-lossless
(426.44 s = 112.28 + 314.16), mjpeg preview dropped, creation_time + timecode stamped.
**Consequences:** `fetch-ffmpeg.sh` (GPL prebuilt) demoted to a dev-only fast-path fallback; the
release path is the LGPL build script. Build needs Xcode CLT only (no nasm on arm64).

---

## Template

### [Date] - [Decision Title]
**Context:** [What situation prompted this decision?]
**Options Considered:**
1. [Option A] - [pros/cons]
2. [Option B] - [pros/cons]

**Decision:** [What we chose]
**Rationale:** [Why we chose it]
**Consequences:** [What this means going forward]

---

## Decisions

### 2026-06-07 - Group segments by metadata continuity, not filenames
**Context:** DJI splits recordings at the FAT32/exFAT 4 GB boundary (~16.8 GB on newer
models). Filenames reset to `DJI_0001` on in-drone format and collide across drones.
**Options Considered:**
1. Filename sequence (`DJI_0001→0002`) — simple but unreliable; resets/collides.
2. Embedded-metadata chaining (`creation_time` + duration adjacency, stream-param match) —
   robust, separates independent recordings, matches Telestream/P2 timecode-first practice.
**Decision:** Metadata-continuity chaining is primary; filename order is a corroborating
secondary signal and tie-breaker only.
**Rationale:** Splits are written back-to-back, so `creation_time[N]+duration[N] ≈
creation_time[N+1]` is a true continuity test; filenames are not.
**Consequences:** Need a reliable AVFoundation/ffprobe metadata reader; must handle DJI's
wrong/zeroed timecode and timezone/epoch bugs defensively.

### 2026-06-07 - FFmpeg concat demuxer with `-c copy` as the join engine
**Context:** Need lossless, fast joining of already-muxed MP4 segments.
**Options Considered:**
1. concat *protocol* — doesn't work for MP4/MOV (MPEG-TS only).
2. concat *filter* — re-encodes (lossy, slow).
3. concat *demuxer* `-c copy` — lossless stream copy, I/O-bound, handles thousands of files.
**Decision:** concat demuxer with `-c copy -fflags +genpts -movflags +faststart`.
**Rationale:** Same-recording DJI splits share identical codec/params (the demuxer
precondition); stream copy is bit-identical and fast. No BMX stage needed (unlike P2/MXF).
**Consequences:** Must re-apply `tmcd`/creation_time on output (concat doesn't preserve
them); refuse joins across mismatched codec/res/fps; handle benign "Non-monotonous DTS".

### 2026-06-07 - Timecode is authoritative for the metadata fix
**Context:** DJI `tmcd` start TC and `mvhd`/creationdate calendar timestamp often disagree.
**Decision:** Treat start timecode as ground truth; rewrite creation-date atoms to match,
not the reverse. Surface the discrepancy in the UI; user confirms (default = TC).
**Rationale:** Broadcast convention; camera clock is the more likely-wrong source.
**Consequences:** Need exiftool/atom write-back to keep all QuickTime date atoms consistent.

### 2026-06-07 - Port architecture from P2toMXF, drop the BMX stage
**Context:** User's own app P2toMXF (Swift 6/SwiftUI, MIT, github.com/Xpycode/P2toMXF)
already implements the subprocess/queue/verify/ETA scaffold and a timecode-continuity grouper.
**Decision:** Clone & port `FFmpegWrapper`, `QueueManager`, `SpeedTracker`,
`VerificationService`, `BundledToolResolver`, `TempDirectoryManager`, `Timecode`,
`ConversionViewModel`+RecordGroups, signing script. Drop `BMXWrapper`, `P2CardParser`,
and bundled `bmxtranswrap`/`mxf2raw` + dylibs. Clone lives at `_reference/P2toMXF/`.
**Rationale:** DJI MP4s are self-contained, so the P2 stage-1 rewrap is unnecessary; the
reusable core is P2toMXF's stage-2 concat engine + grouping brain. Fastest credible path.
**Consequences:** Replace P2CardParser CLIP-XML with ffprobe/AVFoundation DJI reader;
replace `discoverP2Cards` with `discoverDJIMedia` over DCIM folders.

### 2026-06-07 - Direct distribution + notarization (not Mac App Store)
**Context:** FFmpeg is GPL; bundling it makes MAS distribution legally fraught.
**Decision:** Developer ID signing + notarization, App Sandbox **disabled**, Hardened
Runtime **enabled** (with library-validation/JIT entitlements for subprocess exec).
**Rationale:** Matches P2toMXF's proven, shipped configuration; avoids GPL/MAS conflict;
sandbox-disable is required to exec bundled FFmpeg.
**Consequences:** MAS out of scope; need the dylib-path-fix + re-sign packaging dance.

### 2026-06-07 - [research-revised] Grouping key is filename+SRT-wallclock, NOT creation_time
**Context:** Research verified DJI MP4 `creation_time` is frequently wrong (QuickTime 1904
epoch bug → files read as 1951; plus timezone shifts), and the embedded `tmcd` start timecode
is almost always `00:00:00:00`. The original "chain by `creation_time + duration`" plan rested
on metadata DJI doesn't write reliably.
**Decision:** Layered ordering key — (1) filename scheme + index (`DJI_NNNN`, or
`DJI_YYYYMMDDHHMMSS_NNNN_<suffix>`), (2) SRT embedded wall-clock continuity, (3) decoded
segment-duration adjacency. `creation_time`/`tmcd` are corroborating-only. Stream-param
equality (codec/res/fps/timebase/color) is a hard gate. **Never** merge across camera-variant
suffixes (`_W`/`_Z`/`_T`/`_V`/`_D`). Exclude `.LRF` proxies from the concat set.
**Rationale:** Use the signals DJI actually writes correctly; refuse joins that would corrupt.
**Consequences:** DJIFilenameParser + variant guard are first-class; the ported `Timecode`
continuity tier feeds on decoded duration/wall-clock, not tmcd frame math.
**Sources:** SANS ISC DJI metadata; exiftool QuickTime-epoch patch; Pertsev "DJI 1951 bug";
MavicPilots suffix threads; Crear12/Merge_DJI_Video_SRT.

### 2026-06-07 - [research-revised] Native atom writer for the date fix, NOT bundled exiftool
**Context:** exiftool is Perl — bundling means tens of MB, an extra nested binary to
codesign+notarize, and an extra license. The fix only needs a handful of QuickTime atoms.
**Decision:** FFmpeg sets `-metadata creation_time=…` + `-timecode` during the join; a small
(~150-line) native Swift atom writer then patches `mvhd`/`tkhd`/`mdhd` create+modify (1904
epoch) and `Keys:com.apple.quicktime.creationdate` so Finder/Photos AND QuickTime Player's
Movie Inspector agree. No exiftool bundled.
**Rationale:** Lightest path; no Perl runtime, no extra notarized binary, no extra license.
**Consequences:** Must implement + unit-test the 1904-epoch atom patcher; read the
authoritative date/timecode from segment 1 via ffprobe.

### 2026-06-07 - [research-revised] Bundle a static arm64 LGPL FFmpeg + ffprobe
**Context:** GPL FFmpeg (e.g. OSXExperts `--enable-gpl`) imposes full-source-distribution
obligations and is MAS-incompatible. A copy-only joiner needs no GPL encoders (x264/x265).
**Decision:** Bundle a **static arm64** build of `ffmpeg` + `ffprobe`, built **LGPL**
(`--enable-static --disable-shared`, omit `--enable-gpl`/`--enable-nonfree`, only the
demuxers/muxers/bitstream-filters we use). Static = single Mach-O each, no `install_name_tool`
dylib dance. If a GPL prebuilt is used as a stopgap, ship GPL text + same-server source offer.
**Rationale:** Lighter legal burden, simpler bundling/signing, smaller app.
**Consequences:** Need a reproducible FFmpeg build recipe (or vet OSXExperts 8.1 as interim);
sign both helpers inside-out before the app; notarytool + stapler.

### 2026-06-07 - [research-revised] SRT stitch offsets come from decoded duration, not cue math
**Context:** DJI per-segment `.SRT` cue timestamps RESTART at 00:00:00 each segment; cue
cadence (~33 ms at 30 fps) accumulates rounding drift, and the last cue ends before the true
video end. Verified prior art (Crear12) recalculates timestamps.
**Decision:** Stitch in-app: add a cumulative offset = Σ ffprobe `format=duration` of preceding
segments to each cue, renumber indices globally, advance the offset even when a segment's SRT
is missing. Prefer the SRT embedded wall-clock line for ordering/validation. Parse defensively
(modern bracketed, FrameCnt+wallclock, legacy `<font>`/`GPS()` variants).
**Rationale:** Decoded duration is the only drift-free offset; cue arithmetic drifts.
**Consequences:** SRTStitcher needs a tolerant multi-format parser + duration from ffprobe,
not from the SRT itself. This is the app's key differentiator (prior art is sparse).

### 2026-06-07 - v1 scope = full app incl. watch-folder AND SRT stitching
**Context:** Interview offered a staged MVP; user chose the comprehensive first release.
**Decision:** v1 = engine + GUI + watch-folder automation + `.SRT` telemetry stitching
(with cumulative per-segment time-offset correction).
**Rationale:** User's explicit choice; SRT stitching is the community differentiator.
**Consequences:** **Scope-creep risk flagged.** SRT offset-correction is the
highest-uncertainty piece (brief calls it "a known unsolved pain point"); planning must
still stage internally (engine → GUI → watch-folder → SRT) even though all ship in v1.

### 2026-06-07 - Define the DJIClip model layer now (ahead of footage), to unblock the queue ports
**Context:** Wave 1's queue ports (SpeedTracker, QueueManager via ConversionJob) reference the
clip/settings model layer. The plan deferred `DJIClip`/`ConversionSettings`/`ConversionJob`
(1.2/1.3) until Wave 2's grouping (2.4) and folder reader (2.3) "locked the shape" — but those
are blocked on real DJI footage, which isn't in hand. So the queue can't be ported without the
model layer.
**Decision:** Design `DJIClip` / `ConversionSettings` / `ConversionJob` **now from the spec +
CLAUDE.md guidance** (`srtFile:URL?`, `lrfFile:URL?`, `fileIndex`, `timestamp?`, `variantSuffix?`,
`cameraModel?`, exact `CMTime` duration, codec/res/fps/audio stream params, `creationDate?`;
`OutputContainer {.mp4, .mov}`). The footage gates *grouping/validation logic*, not the data
shape, which the spec already determines.
**Rationale:** Keeps the queue ports moving; the shape is spec-derived and stable enough.
**Consequences:** Accept some churn risk when 2.3/2.4 land on real footage. Port order:
1.2/1.3 models → 1.8 SpeedTracker → 1.9 VerificationService → 1.10 ThumbnailManager → 1.7
QueueManager (processing/verification orchestration adapts to drive the ported `mergeClips`,
not BMX). 1.5 (TempDirectoryManager + DiskSpace) already ported.

### 2026-06-08 - DJIClip duration: Int64 value + Int32 timescale backing → computed CMTime
**Context:** The spec wants frame-exact segment durations (continuity math + SRT offsets depend
on them), but `CMTime` isn't `Codable`/`Sendable` and the queue must persist `[DJIClip]` to JSON.
P2toMXF sidestepped this by storing durations as `String` frame counts — lossy and stringly-typed.
**Options Considered:**
1. Store `Double` seconds — loses exactness on NTSC fractions (30000/1001 ≈ 29.97).
2. Store a `CMTime` with a custom Codable shim — works but scatters CoreMedia at the boundary.
3. Store `durationValue: Int64` + `durationTimescale: Int32` backing, expose computed `CMTime`.
**Decision:** Option 3. The clip stores the two integers; `var duration: CMTime` rebuilds the
exact value only at the boundary. Mirrors the existing URL→String storage idiom.
**Rationale:** Trivially `Codable`/`Sendable`, frame-exact (a round-trip test asserts 30000/1001
survives byte-for-byte), and keeps CoreMedia out of the persisted representation.
**Consequences:** Callers read `clip.duration`/`durationInSeconds`, never the backing fields.
The metadata reader (2.2) must supply a real `CMTime` (AVAsset duration or ffprobe rational).

### 2026-06-08 - Embed StreamParameterGuard.SegmentStreamInfo on DJIClip (one source of truth)
**Context:** Both the join's pre-flight param guard (2.6) and the grouping engine (2.4) need each
segment's codec/res/pix_fmt/fps/timebase/audio. Duplicating those fields on `DJIClip` would risk
the two paths disagreeing.
**Decision:** Make `StreamParameterGuard.{Video,Audio}StreamParams`/`SegmentStreamInfo`
`Hashable, Codable, Sendable` (additive change) and embed `SegmentStreamInfo?` directly on
`DJIClip` — no duplicated stream fields.
**Rationale:** Single source of truth: grouping and the join guard read identical data; the param
gate's own structs become the persisted record. `Hashable` keeps `DJIClip` `Hashable` for SwiftUI.
**Consequences:** `StreamParameterGuard` (a Wave 2 service) now carries conformances a model depends
on; that coupling is intentional. `streamInfo` is optional (nil until a segment is probed).

### 2026-06-08 - Lean ConversionSettings; one ConversionJob = one record group
**Context:** Porting P2toMXF's `ConversionSettings`/`ConversionJob` verbatim would import P2-isms
(`processingMode`, `audioMapping`, `generateReport`, `includeChecksum`) and a whole-card job model.
DJIjoiner has no shipped `queue.json`, so backward compatibility doesn't constrain the shape.
**Decision:** Keep `ConversionSettings` **lean** — only `outputDirectory`, `outputFilename`,
`useFolderNameAsFilename`, `outputContainer{.mp4,.mov}`, `preserveTimecode`, `fixCreationDate`,
`stitchSRT`, `reEncodeOnMismatch=false`, `deleteOriginalsAfterVerify=false`. Make **one
`ConversionJob` = one `RecordGroup`** (not a whole folder), and rename P2 fields freely
(`cardName→folderName`, `cardPath→sourceFolderURL`, `cardBookmark→sourceBookmark`).
**Rationale:** One job = one group matches the concat join (one group → one output) and the
watch-folder "join when the group is complete" state machine. Lean settings = add knobs as features
land, not speculatively. Free renames remove P2 vocabulary before the 1.7 QueueManager port.
**Consequences:** UI/ViewModel build jobs per group, not per card. New knobs (re-encode UI, SRT
toggle wiring) get added to `ConversionSettings` as their features land.

### 2026-06-09 - SRT stitching is non-fatal to the join (task 3.3)
**Context:** Task 3.3 wires the per-segment `.SRT` stitch into `processConcatenateJob`, *after* the
lossless concat `-c copy` join has already produced the output video. The brief flags SRT
offset-correction as the **highest-uncertainty v1 item** ("known unsolved pain point"); ffprobe
duration probes or sidecar parsing can fail on odd real-world files.
**Decision:** Treat the `.SRT` stitch as a **best-effort sidecar step that never fails the job.** Any
error (ffprobe failure, unreadable sidecar, write error) is logged and swallowed; the job still
completes on the strength of the verified video join. Run the stitch **off the main actor**
(`Task.detached`) because `stitchSRT` probes each segment's duration synchronously, and emit nothing
when no segment carries a sidecar. The stitched `.SRT` is written next to the output
(`<output-stem>.SRT`) but is **not** added to `actualOutputURLs` (verification targets the video).
**Rationale:** The user's footage is irreplaceable; a flawless lossless join must not be discarded
because telemetry — a secondary convenience track — hit a snag. Decoupling the two also lets SRT
robustness improve against real footage (Wave 6) without risking the core join.
**Consequences:** A telemetry failure surfaces only in the log, not as a job failure — Wave 6 footage
calibration should add a visible per-job "SRT: written / skipped (reason)" indicator so silent
skips are noticeable. Seam-aware SRT/video alignment checks remain a Wave 6 item.

### 2026-06-09 - Group by file-size split-cap + real wall-clock, not playback duration (task 2.4)
**Context:** The first real DJI card (`DJI_001`, 110 clips, 7 days) exposed that **slow-motion clips
report a container/playback duration ~4× their real wall-clock capture time** (e.g. a 100 fps
segment: container 794.84 s, real ~199 s). The spec's planned continuity rule —
`creation_time[N] + duration[N] ≈ creation_time[N+1]` — silently mis-groups slow-mo because
`duration` is playback time, not elapsed. Filename indices also reset on format and collide across a
card, and photos taken mid-flight bump the counter.
**Options Considered:**
1. `creation_time + container duration` adjacency (the spec) — breaks on slow-mo.
2. Real elapsed via `nb_frames / capture_fps` — capture fps isn't in basic ffprobe (`r_frame_rate`
   is the *playback* rate); only derivable from the SRT, which isn't always present.
3. **File-size split-cap + real wall-clock start** — a segment at the ~4 GB byte ceiling continues
   into the next file; the first segment under the cap ends the recording; `creation_time` (real
   wall-clock, confirmed via AVFoundation and ffprobe) confirms adjacency within the prev segment's
   playback length + slack.
**Decision:** Option 3. A clip is "capped" when size ≥ `0.93 × maxSegmentSize` (floor 3 GB);
grouping buckets by variant suffix first (hard no-merge boundary), then within each bucket sorts by
`creation_time` and chains capped→next when params match (`StreamParameterGuard.check`) and the gap
is `0 < gap ≤ prevContainerSeconds + 12 s`. Missing `creation_time` or mismatched params breaks a
chain (defensive). The SRT stitcher's offset stays Σ playback duration — correct for the joined
video even in slow-mo — and is deliberately NOT changed.
**Rationale:** The byte-cap is speed-independent and DJI-specific (it's *why* the next file exists);
`creation_time` is reliable real time. Together they're robust to slow-mo, filename resets, and
photo-interleaving — every trap the real card contained. Hand-traced over all 110 clips → correct
recordings.
**Consequences:** Cap fraction/floor + slack are footage-tuned defaults (`GroupingTolerances`) flagged
for Wave 6 calibration across more drones (exFAT caps differ). Pure file-free core (`groupMetas`) is
unit-tested with real-card fixtures. A pathological false-merge (a capped *final* segment followed by
an unrelated same-params recording within its playback length) is possible but essentially never
occurs; documented.

### 2026-06-09 - Drop DJI's embedded mjpeg preview track from joins (-map 0:v:0)
**Context:** Validating a real join (`0104–0106`) revealed DJI MP4s carry a **second, low-res
1280×720 mjpeg *preview* video stream** (`v:1`) alongside the main HEVC. The concat recipe's
`-map 0:v` mapped *all* video streams, so `-c copy` carried the preview into the output, where it was
mangled into a malformed 3-frame / 0.00003 s stream (the source of `timescale not set` warnings).
**Decision:** Map only the **primary** video stream (`-map 0:v:0`) plus optional audio (`-map 0:a?`);
keep dropping data/telemetry tracks (`-map -0:d`).
**Rationale:** The preview is an internal DJI convenience track, not part of the master; carrying it
produces a phantom, malformed second video track that some players/NLEs mishandle. Re-verified: the
fixed recipe yields a single clean HEVC stream, 933.400 s / 23 335 frames = exact lossless sum.
**Consequences:** Joined masters contain only the real video (+audio when present). If a future need
arises to retain the preview, it would be a separate, explicit output — not the default.

### 2026-06-10 - Notarized direct-distribution signing pipeline (task 6.2)
**Context:** Signing was set up (Developer ID identity present, inside-out helper-signing build
phase) but never exercised end-to-end. The app needs to launch on other Macs without a Gatekeeper
"unidentified developer" block, which requires Apple notarization.
**Decision:** A Release build signed with **Developer ID Application** (Team `FDMSRXXN73`), hardened
runtime + secure timestamp on the app wrapper *and* both bundled helpers (ffmpeg/ffprobe), then
notarized via **App Store Connect API key** (keychain profile `conjoyn-notary`) and **stapled**.
Codified in `01_Project/scripts/notarize.sh` (build → verify → zip → `notarytool submit --wait` →
`stapler staple` → `spctl` verify). Distribution artifact: a stapled zip in `04_Exports/`.
**Rationale:** API key over app-specific password — doesn't expire yearly, no 2FA prompts,
non-interactive. Stapling makes the notarization ticket work offline. Manual signing identity
(not Automatic) because Automatic selects the Apple Development cert, which cannot be notarized.
**Consequences:** First real notarization **Accepted**; `spctl` reports `source=Notarized
Developer ID`. Credentials live only in the keychain (the `.p8` stays outside the repo). A DMG
wrapper (drag-to-Applications, background art) is deferred to the design/icon session — the zip is
sufficient for now. Note: the helper-hardening check originally used `grep -q`, which under
`set -o pipefail` SIGPIPE'd codesign and falsely failed; rewritten to capture-then-match.

### 2026-06-13 - Persistent diagnostic logging (file-backed, rotating)
**Context:** A `/minimums` pass (verified against the code) found one real baseline gap: logging was
in-memory only. `QueueManager.log()` appended to a `consoleLines` buffer shown in the console window
but trimmed to 5000 lines and lost on quit — so a bug reported after a relaunch left nothing on disk
to inspect. No `OSLog`/`NSLog`/`print` either. (One deliberate omission was re-affirmed, not a gap:
**no Preferences window / ⌘,** — appearance lives in its own menu and nothing else is configurable.)
**Decision:** Add `DiagnosticLogger` — a file-backed log at
`~/Library/Application Support/Conjoyn/diagnostic.log`. `@MainActor` singleton with an **injectable**
storage directory (mirrors `SpeedTracker`/`QueueManager` so tests use a temp dir), ISO-8601 stamps, a
per-session banner carrying the bundle version, append via `FileHandle.seekToEnd`, and
**single-generation rotation** to `diagnostic.log.1` at 1 MB (`maxBytes`). Wired through the existing
`QueueManager.log()` chokepoint with **one line**, so all ~56 call sites persist for free; the console
and the file stay in lockstep by construction.
**Rationale:** Route through the one existing `log()` funnel rather than introducing a parallel
logging API — zero call-site churn, no drift between console and file. **Rotate-to-`.1`** over
truncate-front or delete-on-full: it preserves the most relevant case (a bug reported *after* a
relaunch) at a bounded ~2 × `maxBytes` disk cost and is trivial to implement. Synchronous main-thread
writes are fine because every `log()` message is a coarse lifecycle event (job start / SUCCESS /
FAILED / resolution milestones); the high-frequency `speed=`/progress stream deliberately flows
through `activeMetrics`, never `log()`. The whole type is failure-swallowing (`try?` on every
`FileManager`/`FileHandle` call) — a diagnostics facility must never crash the app it diagnoses.
**Consequences:** Closes the last `/minimums` gap. `DiagnosticLoggerTests` (7) cover banner/version,
append, ordering, injected dir, rotation, `.1` replacement, and the no-rotate-below-threshold guard;
rotation is exercised by pre-seeding an oversized log so the test never writes a real megabyte. Full
suite 337 / 1 skip / 0 fail. Owed: one live eyeball that the real file materializes on a join
(verifies the bundle version stamp outside the test host). Shipped in `5a11fc6`.

### 2026-06-16 - Public source under PolyForm Noncommercial 1.0.0

**Decision:** Make `github.com/Xpycode/Conjoyn` **public** and license it under the **PolyForm
Noncommercial License 1.0.0** (`LICENSE.md`), with a `README.md`. Source is visible/forkable for
non-commercial purposes; **commercial use — selling it or shipping it in a paid app — is prohibited.**
Licensor: Luces Umbrarum. Done after a pre-public secrets scan (no keys/secrets in tree or history;
only the Sparkle *public* key is committed; `99-AUTH/` lives outside the repo; the only hardcoded value
is the non-secret Team ID `FDMSRXXN73`).
**Rationale:** The goal was "source-available so people can learn from it, but nobody can build a paid
app from it." That is by definition **not** an OSI open-source license (all of which permit commercial
use). PolyForm Noncommercial is purpose-built for software (unlike CC BY-NC), plain-English, and
simpler than BUSL (no change-date machinery) — it states the non-commercial restriction directly. The
alternatives were rejected: All-Rights-Reserved (too restrictive — bars even non-commercial study),
BUSL (auto-converts to OSS later, not wanted), CC BY-NC (CC advises against it for code).
**Consequences:** The repo and its full history are now publicly visible — irreversible in practice
(caching/indexing). The bundled FFmpeg is LGPL-clean (verified: no `--enable-gpl`/`nonfree`/`version3`),
so the README's licensing claim holds and direct distribution is unaffected. GitHub's license detector
may not show a PolyForm chip; the file is present and binding regardless.

### 2026-06-18 - Watch-folder engine architecture (Wave 5A–5C)

**Decision:** Build the watch-folder as a **pure decision core + thin imperative shell**, with four
load-bearing sub-decisions. **(1) Idempotency via a persisted SHA-256 fingerprint ledger.** Dedup keys
on a process-stable fingerprint of each group's ordered `stem|index|variantSuffix` — *not* the queue's
existing unfinished-job check (`ConversionViewModel.swift:351`, which sees only in-flight jobs) and
*not* `DJIClip.id` (a fresh UUID per parse). The fingerprint is inserted at *enqueue* time and the
ledger loads its set from disk at init. **(2) Pure `WatchFolderReconciler` + `@MainActor
WatchFolderCoordinator`** — all "is this group ready / should it re-enqueue" logic is static and
side-effect-free; the shell only feeds it samples and routes its output to `QueueManager.addJob`.
**(3) Plain `bookmarkData()` + TCC, not security-scoped bookmarks.** App Sandbox is disabled, so
`.withSecurityScope` is a no-op; a plain bookmark remembers the folder, and the real gate for a
background SD-card read is `NSRemovableVolumesUsageDescription` (TCC), which no bookmark can satisfy.
**(4) FSEvents `latency` *is* the debounce, and rediscover ≠ re-sample** — an FSEvents change re-runs
the heavy ffprobe discovery; the poll timer does cheap `stat`-only re-sampling of the cached groups.
**Rationale:** (1) A watch-folder fires repeatedly while a card's joined files stay on disk; without a
*persistent* ledger that survives relaunch it re-joins forever, and keying on the per-parse UUID would
silently fail to match across rescans — the stable fingerprint *is* the mechanism, not an optimization.
(2) Mirrors the codebase's existing instinct (pure `FileStabilityGate`/`CompleteSetGate`, pure
`ordered(_:)` sort helpers) — the brain is unit-testable by replaying a "filling folder" with no
FSEvents, ffmpeg, or `QueueManager`. (3) Sandbox-off changes the access model entirely (memory
`sandbox-off-tcc-is-real-gate`); leaning on scope would be cargo-culted ceremony while the actual
SD-card denial went unaddressed. (4) ffprobe-per-clip every 0.75 s would peg CPU + spin the disk
forever while idle; FSEvents already coalesces, so a second debounce layer is redundant.
**Consequences:** Engine complete on branch `feature/wave5-watch-folder` (5A `3478261`, 5B `87e5de1`,
5C `aa010fb`); full suite **446/1 skip/0 fail** (+86). **Two bugs caught in review + regression-tested:**
the ledger set was first an empty-at-launch in-memory mirror (re-introduced the re-join-forever loop
after relaunch — fixed by sourcing `ProcessedGroupLedger.allFingerprints` from disk), and discovery ran
on every poll (fixed by the rediscover/re-sample split). The policy predicates (`isSettled`,
`isComplete`) ship with a strict-reading default in a flagged `// Policy block — yours to tune`, contract
pinned by tests. **5D UI is designed + approved but deferred** (no build that session): a "Watch Folder"
`CommandMenu`, a footer status readout, and the watch-folder's **own** output-folder picker (replacing
the coordinator's v1 next-to-source `destinationURL` placeholder). 5E real-footage + real-SD-card TCC
eyeball follows 5D. Engine-only; shipped 1.0.2/102 untouched.

### 2026-06-20 - Watch-folder 5D UI = multi-folder list window + "block on last-known path" overlap policy

**Decision:** Ship the watch-folder UI as a **multi-folder list window** (`WatchFoldersPanel`), not the
originally-deferred single-folder menu+footer. Each row is a `WatchFolderEntry` driven by its **own**
isolated `WatchFolderCoordinator` (one FSEvents stream + one `ProcessedGroupLedger` per folder) with an
enable toggle, a live status chip (WATCHING / SETTLING n / QUEUED n), a per-folder output picker, and a
settings popover (quiet window / stable polls / poll interval / split threshold). `WatchFolderManager`
owns the list, persists entries to `UserDefaults`, and resolves the `TODO(5D)` placeholder via
`WatchFolderCoordinator.outputFolderURL`. The **overlap guard** (`rejectionReason(forAdding:existing:)`)
rejects a candidate that is the same as, nested in, or a parent of any existing root; an entry whose
volume is currently **offline** STILL blocks, by falling back to its persisted `rootPath`
(`resolvedRootURL ?? URL(fileURLWithPath: rootPath)`).

**Rationale:** The user upgraded the scope mid-wave — watching multiple cards/folders at once is the real
ingest workflow, and the per-folder isolated ledger (the 5A–5C engine shape) already makes N independent
coordinators cheap and correct. The overlap guard is the price of that isolation: two roots over the same
tree would each enqueue the same clips → a double join. Blocking on the last-known path (rather than
skipping offline entries) closes a real hole — an SD card can be unplugged when you add a second folder,
then re-mount and silently overlap; `rootPath` was already stored for exactly this offline case, so the
guard costs ~2 lines and one regression test (`testRejectionReasonBlocksOfflineEntryViaLastKnownPath`).

**Consequences:** Wave 5D shipped to `main` (merge `c814efc`, feat `41411bb`); full suite **455/1 skip/0
fail**. Eyeballed on real `2CULL` footage: single + two concurrent watch folders, `SETTLING n` → `QUEUED
n` → joined, per-folder outputs, 0 failed on the watch path. **This supersedes the "5D deferred" note in
the 2026-06-18 engine entry above.** The shipped 1.0.2/102 DMG/appcast are untouched (Debug-local) — a
re-cut is owed only if/when a build with watch-folder ships, and the in-app Roadmap help topic keeps
listing watch-folder as a future until such a build ships.

### 2026-06-24 - Watch-folder daemon hardening: bounded discovery, FSEvents context retain, source-identity TOCTOU guard

**Context:** The 2026-06-23 post-hoc engine review flagged three worth-fixing items before the
watch-folder *daemon* use case (long-running, many cards) gets real mileage. The shipped single-card
happy path (5.14, 2026-06-24) is unaffected — these are the hang / use-after-free / time-of-check edge
cases. Implemented on `fix/wave5-watchfolder-hardening`, merged `--no-ff` to `main`.

**Decisions:**
1. **Hung discovery → bounded timeout + split latch** (user-chosen over "split latch only"). `reconcile`
   previously latched a single `isRescanning` flag cleared by `defer`; a `discover()` (ffprobe) that
   hangs on a stalled mount never returns, so the `defer` never fires and the watcher silently dies.
   Fix: split into `isDiscovering` (heavy rediscovery) and `isResampling` (cheap poll cadence) so a
   wedged scan can't freeze the cadence, AND bound `discover()` with `WatchFolderSettings.discoverTimeout`
   (default 90 s, tunable, forward-compatible decode). On timeout the coordinator reuses the last known
   groups and retries next tick. The wedged task is **abandoned, not awaited** — an ffprobe `Process` can
   ignore cooperative cancellation, and awaiting it would re-introduce the deadlock; an orphaned task on a
   rare stuck mount is the acceptable cost. (`withDiscoverTimeout` + a single-resume `ResumeGate` actor.)
2. **FSEvents context retain/release** to close the teardown UAF (`passUnretained`/`nil` callbacks let
   `stop()`/`deinit` free the monitor while a callback was in flight on the GCD queue). The stream now
   holds its own strong ref; `FSEventStreamRelease` (after `Invalidate`) balances it. This is an
   intentional stream↔monitor cycle broken by the explicit `stop()` the coordinator always calls — so
   `deinit` is now a fallback for the unstarted/already-stopped case only. (Verified safe: every
   coordinator routes through `deactivate → disable → stopMonitor → stop()` before release.)
3. **Source-identity TOCTOU guard before the join** (cookbook #127). Clips are captured at enqueue but
   ffmpeg runs minutes later as the queue drains; a card swap / in-camera rotation can repoint a `DJI_NNNN`
   path at different bytes, which ffmpeg would concatenate silently. `FileIdentity` snapshots `(device,
   inode)` via `lstat` at enqueue (in the shared `addJob` funnel, so the manual queue is guarded too) and
   re-verifies immediately before `mergeClips`; a `.mismatch`/`.missingNow` throws the **non-retriable**
   `FFmpegError.sourceIdentityChanged`. **Policy divergence from #127:** `.unverifiable` (a transient
   `stat` error that isn't "gone") does **not** block here — #127's source was *trashing* (delete), where
   refusing on uncertainty is strictly safe; this is a *read-and-produce* (join), so failing a legitimate
   job on a momentary read blip is worse than letting ffmpeg surface a genuine read error. A restored job
   has no baseline → the guard is a no-op (the relaunch is its own time-of-check). Captured identities are
   transient (out of `CodingKeys`).

**Consequences:** Merged to `main` (`d7e05fe` UAF, `e3f9789` hung-discover + #4 stale-key cache eviction,
`3ee5933` TOCTOU). Full suite **468 / 1 skip / 0 fail** (+13). The lower-severity review items (unbounded
ledger, `nil`-vs-`""` fingerprint, decorative `WatchGroupState`, shared GCD label) remain deferred —
cosmetic / debuggability, not reachable failures. Shipped 1.0.2/102 untouched (Debug-local).

---

### 2026-06-24 - Index-gap guard: a missing middle segment must split the chain (closes a slow-mo silent merge)
**Context:** Building the Wave 6.5 missing-middle fixtures (variant-guard and codec-guard were already
unit-tested; missing-middle was not) surfaced that `DJIFolderReader.continues()` had **no index-continuity
check at all** — protection against a dropped/lost middle segment was purely *emergent* from the wall-clock
rule `gap ≤ prev.containerSeconds + 12 s`. That bound uses **playback** duration. For normal speed it's
tight (≈ real elapsed), so a missing segment's doubled ~654 s gap trips it and the chain splits safely. For
**slow-motion** the bound is the playback length (≈ 4× real elapsed, ~794 s for ~199 s of real time) — the
very looseness that lets slow-mo chain correctly — so a single missing segment's ~398 s real gap still fits
inside it and the two survivors are **silently merged across the hole**: a `-c copy` join with a ~3.3-minute
discontinuity and an SRT misaligned after the seam, with no warning (the join-time `ensureJoinable` re-probe
can't catch it either — the survivors are the same recording, identical params). Up to ~3 consecutive missing
slow-mo segments bridge before the bound finally exceeds. Proven by two characterization tests built from the
real May-21 100 fps fixture numbers. User chose **"fix it (index-gap guard)"** over warn-only / accept-and-document.
**Decision:** Add step 3 to `continues()`: adjacent segments must be **index-consecutive**
(`next.index == prev.index + 1`) within their already variant-bucketed, time-ordered run. A jump means a
segment is missing between them → don't bridge. Index is used here strictly as a **negative** signal, never
as a continuity/ordering key (numbering still isn't authoritative — spec unchanged). Flipped the slow-mo
characterization test to assert the split.
**Why:** Directly closes the proven slow-mo hole and is **conservative** — the check can only ever *add* a
split, never cause a merge, so it cannot corrupt a currently-correct group; its worst case is a benign
false-split into two individually-valid outputs (vs. a silent corrupt merge). Hand-traced against all 12
grouping tests: every intra-group link is already `+1`, and the only places it newly fires
(`testCappedSegmentNotChainedWhenNextStartsTooLate` 14→99, `testAllShortClipsAreSingles` 1→3) are already
split by the cap/wall-clock rules → zero assertion changes beyond the intended slow-mo flip.
**Caveat / open:** Assumes **per-variant consecutive numbering** — verified on single-camera `_D` footage
(the only footage that exists; M4P-1). If a multi-lens enterprise drone interleaves a *global* counter
across lenses (W=6,8,10 within one bucket rather than paired W6/T6, which is what the existing variant test
encodes), this would false-split multi-cam recordings. That's **footage-gated (6.5)** and to be re-validated
when a Mavic 3T / multi-lens card is available; a false-split is the safe failure direction meanwhile.
Index wraparound 9999→0001 within a single recording is an accepted rare false-split (favouring safety over
special-case complexity).
**Consequences:** `continues()` step 3 in `DJIFolderReader.swift` (+ comment, steps renumbered). +3 tests
in `DJIFolderGroupingTests` (`testContiguousNormalChainIsOneGroup`,
`testMissingMiddleSegmentSplitsChainAtGap_normalSpeed`, `…_slowMotion`). Full suite **471 / 1 skip / 0 fail**
(+3), no regressions. **Uncommitted, Debug-local; shipped 1.0.2/102 untouched.** Open follow-up: a real-file
end-to-end pass (rename/re-encode M4P clips through `parse → ffprobe → group`) and the user-facing
"segment N appears missing" warning are both still optional (the warning was explicitly deferred in favour
of the engine-only fix).

---

### 2026-06-24 - Close Wave 6.5 variant + mixed-codec guards with synthetic real-tool fixtures (not real footage)
**Context:** With missing-middle closed (above), the two remaining 6.5 items — **variant no-merge** and
**mixed-codec refusal** — were marked "footage-gated: needs a multi-lens drone." The 2026-06-24 web hunt
confirmed real DJI multi-lens *split* video + original filenames + SRT is **undownloadable**, and the
project's only camera (Mini 4 Pro) is single-lens. Both guards were already *unit-tested* on hand-built
params (`StreamParameterGuardTests` ×15, `DJIFolderGroupingTests` variant + param-mismatch cases), but the
**end-to-end path** — real ffprobe JSON → guard → refusal/no-merge — was unproven for these two cases. The
prior real-probe integration test (`testEnsureJoinableAgainstRealProbe`) only varied **resolution**, not the
codec itself or frame rate. User chose **"synthetic ffmpeg integration tests"** over acquiring footage or
deferring.
**Decision:** Add `ConjoynTests/JoinGuardIntegrationTests.swift` — four tests that drive the production guard
path against clips generated by the **bundled LGPL ffmpeg** and probed by the **real ffprobe**:
(1) `mpeg4` + `mjpeg` → `ensureJoinable` refuses naming the **codec** field; (2) 25- vs 30-fps → refused
naming **frame rate**; (3) a matching pair passes (positive control, so refusals trace to the varied field
not the pipeline); (4) `_W`/`_T`-named clips, variant + index extracted by the **real `DJIFilenameParser`**
and params by the **real `probeStreamInfo`**, never share a group through `groupMetas` even though
size/time/index would otherwise chain them. The variant test lowers the cap floor/fraction so the
bytes-tiny synthetic clips read as split-capped and actually *attempt* to chain — without that they'd fall
out as under-cap singles and the assertion would be vacuous; it asserts exactly 2 groups (one per lens,
each `[0006, 0007]`), which can only hold if same-lens chaining occurred **and** the variant boundary held.
**Why:** The guard logic is codec/field-agnostic (it compares ffprobe strings), so `mpeg4`/`mjpeg` exercises
the identical path `h264`/`hevc` would — what's actually unproven is that the **bundled ffprobe's JSON
decodes** and that a real field difference produces a real refusal, which only a real-tool test can show.
This is the most that *can* be proven without footage that does not exist; it's honest about the gap rather
than leaving the items open indefinitely.
**Caveat / still footage-gated (cannot synthesize):** (a) real multi-lens **index numbering** (Mavic 3 Pro /
thermal) — the variant guard is asserted on the single-camera consecutive-numbering model only (same caveat
as the index-gap guard above); (b) the **exact h264/hevc bytes** — the LGPL build ships no x264/x265, so the
codec pair is a stand-in. Both are documented in the test's file header, not hidden.
**Consequences:** New test file only — **no production code changed**. Full suite **475 / 1 skip / 0 fail**
(+4), no regressions. Closes the prior entry's "real-file end-to-end pass" follow-up for variant + codec
(via synthetic clips, since real footage is unobtainable). **Uncommitted, Debug-local; shipped 1.0.2/102
untouched.**

---

### 2026-07-14 - SD-card photo handling: preserve, don't process (roadmap scope guard)
**Context:** Roadmap idea raised by the user — DJI cards routinely carry **stills alongside video**
(single JPG, RAW `.DNG`, panorama source sets, AEB/burst brackets, timelapse frames). Today those files
are not merely ignored: in `DJIFolderReader.read` the scan only classifies `mp4/mov/srt/lrf` as media —
every other extension hits `continue` and does **not** even land in `skippedNonDJI` (`DJIFolderReader.swift`
~L67-83). So a `.JPG`/`.DNG` next to the clips is dropped with **zero trace**. If a user treats Conjoyn as
their card-ingest tool ("get everything off, then format"), that is a latent **data-loss footgun**: they can
wipe the card and lose photos Conjoyn silently saw. No code written yet — this entry locks the *scope
boundary* while it's fresh, per the same discipline that fenced SRT stitching.
**Decision:** If/when built, Conjoyn **preserves** photos; it never **processes** them.
1. **Two modes, different behaviour** — the copy-offer is **SD-card / direct-card-read only** (the card is
   ephemeral and about to be wiped, so preservation earns its keep). In **watch-folder / drag-a-folder**
   mode, photos are already on managed disk → **surface a count, do nothing, don't touch them.**
2. **Tiered scope.** *Tier 0 (detect & surface):* give `DJIFilenameParser` a `.photo` `mediaKind`, add a
   `photos: [DJIPhoto]` collection to `Discovery`, show a passive "also on this card: N photos (M DNG)"
   line — shipped alone this already closes the silent-drop footgun. *Tier 1 (MVP copy):* opt-in "also copy
   photos", byte-for-byte (preserve filename + timestamps) into a `Photos/` sibling of the stitched output,
   checksum-verified via the existing `VerificationService` so it feeds a **"card fully ingested — safe to
   format"** confirmation. *Tier 2:* copy panorama tiles / AEB-burst / RAW+JPG **as coherent sets**, never
   half a set.
3. **Explicitly OUT of scope (the fence):** stitching panoramas, merging HDR/AEB brackets, RAW development,
   any editing — DJI Fly and third-party tools own that. Conjoyn is not a photo app.
**Why:** Framing this as **card safety** rather than "photo support" gives it a coherent product story *and*
tells us exactly how far to build: nothing on the card should be lost, but Conjoyn stays a stitcher. Every
piece rides seams that already exist — the `.other`/`mediaKind` enum has a latent `.photo` slot, the DCIM
`resolveMediaFolders` descent already handles a dropped card root, and `VerificationService` already does
checksum verification — so there are **no new subsystems**, only a new classification branch + a copy step.
**Caveat / footage-gated:** Confident about DJI photo **filenames** (same grammar as video — the stem parser
already handles `DJI_0001.JPG` / `DJI_20230813102011_0008_D.JPG`). **Not** confident about **panorama
folder layout** — DJI stores pano source tiles in a subfolder whose exact path varies by model
(Mini/Air/Mavic differ); Tier 2 must be verified against a **real card with photos** before it's designed,
not asserted from memory.
**Consequences:** No code this session — captured as a post-v1 roadmap item (PROJECT_STATE Backlog) with the
scope guard locked. Natural next step is a `/spec` stub once a real photo-bearing card is on hand. Ties into
the "more camera families" focus (GoPro/Osmo also shoot stills), so the `.photo` classification should be
designed camera-agnostic from the start.

### 2026-07-18 - Saved rename templates: pattern-only, self-labelled, no naming UI

**Context:** The Rename popover offered three built-in preset chips, but a user's own pattern lived
only in session-state (`renameOptions` deliberately resets each launch — 2026-06-10), so a custom
pattern had to be retyped every session. User asked for storable rename templates.
**Decision:** A template is a **bare pattern string**, persisted as a Codable blob under one
UserDefaults key (`RenameTemplates`, the `WatchFolderSettings` idiom). Three deliberate narrowings:
1. **Pattern only** — counter start/digits are *not* captured. They stay per-batch settings, so a
   template tap behaves exactly like a built-in preset tap; capturing them would make templates
   silently change counter behaviour and diverge from the 2026-06-10 counter-restarts-per-batch call.
2. **The chip's label IS the pattern** (monospace, like the token pills) — no naming step, so saving
   is one click on the ＋ chip. Alternative (user-named templates) was offered and declined: compact
   labels weren't worth an in-popover naming flow.
3. **The ＋ chip only exists while the current pattern is savable** (non-empty, not a built-in
   preset, not already saved) — a visible ＋ always does something; dedup falls out of visibility.
**Why:** Selection/recall mechanics already existed — preset chips highlight via
`renameOptions.pattern == chip.pattern` string equality — so a stored pattern needs no "active
template" state, no IDs, no reverse references. The whole feature is a string array + chips.
**Consequences:** New `Models/RenameTemplates.swift` + a "Saved:" row and `ChipFlowLayout` (wrapping
`Layout`, first in the codebase) in `RenamePopover.swift`; +13 tests (488/1/0). Session-only
`renameOptions` semantics unchanged. If per-template counter settings are ever wanted, that's a
schema evolution of the blob (decodeIfPresent keeps old blobs valid), not a redesign.

### 2026-08-06 - Filename parser tolerates a rename prefix, but keeps the tail anchored

**Context:** A user pointed Conjoyn at a folder of their own archived M4P footage and it reported
"No video segments found" for 9 intact clips + 9 `.SRT` sidecars. The files had been renamed by an
archiving tool — `M4P--2026-05-21--19-43-29--DJI_20260521194329_0001_D.MP4` — leaving the DJI name
verbatim but prefixed. Both parser regexes were anchored to the whole stem (`^DJI_…$`), so every
file failed to parse and discovery produced zero clips. Renamed source footage was never considered
when the parser was written (Wave 2): the assumption was that source files arrive straight off a
card with untouched names, which stops holding the moment footage is archived off the card.
**Decision:** Allow an optional prefix — `(?:.*[^A-Za-z0-9])?` — before `DJI_` in **both** schemes,
while leaving the tail anchored to `$`. Two constraints make this safe rather than a general
loosening:
1. **The prefix must end in a non-alphanumeric separator**, so it can only attach *ahead of* the DJI
   name and can never eat into a word. `MYDJI_0001` stays rejected; the index, timestamp and variant
   suffix are still extracted from exact-width, fully-anchored fields.
2. **The tail stays anchored**, so a *trailing* addition is still not a DJI name.
**Why the asymmetry is the point:** a **prefix** is how third-party renamers and archive conventions
mark files (date/camera/shoot in front, original name preserved); a **suffix** is how *this app*
names its own output — `WatchFolderCoordinator` writes `<stem>_joined.mp4`. Accepting prefixes
recovers real user footage; continuing to refuse suffixes is exactly what keeps a watch folder from
re-ingesting its own joined output as fresh source. Rejected alternatives: (a) a user-configurable
filename pattern — far more surface for a problem one regex fragment solves; (b) matching `DJI_…`
anywhere in the stem — would also match the app's own output and any trailing junk, reintroducing
the re-ingest loop; (c) leaving it and telling users to un-rename — the footage is legitimate and
the parser is the thing being wrong.
**Consequences:** +7 tests (495/1 skip/0 fail). Grouping is untouched and provably unaffected: the
archived, renamed copy of the 2026-05-21 M4P footage produced **6 groups from 9 clips with
0006→0009 as a 4-segment split** — identical to the June hand-verified run on the same footage under
its original card names. `stem` still carries the whole filename, so a renamed video and its
identically-renamed `.SRT` continue to pair, and output names derived from `{name}` simply inherit
the longer stem. Paired with a UI fix: the empty state now names the cause when files were skipped,
because `skippedNonDJI` only ever rendered in the recordings-list header — which is off-screen
precisely when the scan finds nothing, so this class of bug reported as silence.

### 2026-08-07 - GoPro camera family: no absolute split-size constant, and a hand-written `DJIClip` decoder
**Context:** `specs/gopro-camera-family.md` (2026-08-07) shipped with 6 open questions. Two were
answered by measurement against the real Hero 11 corpus, four needed a call. The two with lasting
architectural weight are recorded here; the full table with all six lives in the spec.

**Decision 1 — the GoPro path consults no absolute byte cap.**
**Options Considered:**
1. A GoPro constant (~10.7 GiB) mirroring DJI's `capSizeFloorBytes`/`capSizeFraction` — matches all
   14 measured non-final chapters, one line of code.
2. A per-camera-model cap table (Hero 11 ~10.7 GiB, Hero 5–7 ~4 GB, DJI 4 GB) — precise, but needs
   model detection and goes stale with every camera generation.
3. No absolute constant: group on chapter numbering + stream-param equality + timecode continuity;
   make the watch-folder "expect a continuation" signal **relative** (non-final chapters of one
   recording are near-equal in size, the final one is smaller) plus the existing quiet window.
**Decision:** Option 3. DJI's split-cap gate is **skipped entirely** on the GoPro path, not
re-parameterised.
**Rationale:** The measured cap is not a fixed byte count — recording 6349 at 25 fps capped at
10.8471 GiB while the 100 fps recordings capped at ~10.718 GiB — so any constant is a fit to one
camera *and* one firmware *and* one frame rate. The user's own **Hero 7 is a generation that splits
near 4 GB**, so a Hero 11 constant would be wrong for hardware already in the drawer. Chapter
numbering carries the grouping signal that size was standing in for on DJI, and the relative rule
degrades gracefully on any future camera. Acceptance criterion added: the relative rule must
reproduce the absolute rule's verdict on all 6 corpus groups.
**Consequences:** No GoPro cap constant enters the codebase; `capSizeFraction`/`capSizeFloorBytes`
stay DJI-only. The empty-state copy loses its file-size figure entirely (no number is true across
DJI, Hero 11 and Hero 7 at once) — camera-neutral wording, so no mixed-folder variant is needed.

**Decision 2 — `DJIClip` gets a hand-written `init(from:)` + `CodingKeys` before any new field.**
**Options Considered:**
1. Keep the synthesized `Codable` and make every new field `Optional` — smallest diff.
2. Hand-write `init(from:)`/`CodingKeys` with `decodeIfPresent` throughout, following the
   `ConversionJob`/`JobStatus` precedent (`Models/ConversionJob.swift:51-85`).
**Decision:** Option 2, in a fixed order: **checked-in 1.0.4-shaped `queue.json` fixture test first
(green against today's model), then the custom decoder, then any new field.**
**Rationale:** The hazard is severe and silent — `DJIClip` is fully synthesized-`Codable`, so a new
**non-Optional** stored property *even with a default value* makes a 1.0.4-era blob throw
`keyNotFound` at `QueueManager.swift:256`, and the catch at `:301` discards a shipped user's
**entire** persisted queue. Option 1 disarms it for exactly one change and leaves it armed for
whoever adds the next field. The explicit `CodingKeys` is also the key-mapping layer the deferred
DJI→neutral rename will need, so the work is done once rather than twice.
**Consequences:** New per-clip fields (camera family, gpmd index) may be non-Optional with defaults.
No existing test decodes an older-shaped `DJIClip` blob today (the only forward-compat test is
`SourceTargetModelsTests.swift:160`), so the fixture is new coverage, not a re-run.

**Measured, for the record (closes spec Q1):** verbatim `gpmd` concatenation is **semantically**
correct, not merely byte-exact. Walking the joined seam fixture's gpmd stream as raw GPMF KLV
(parser checked in at `01_Project/scripts/gpmf-dump.py`): all 50 `DEVC` payloads parse clean with no
desync at the seam, `GPSU` UTC is continuous across it, container packet PTS step exactly 1.000 s
throughout — and decisively **`STMP` is recording-relative, not chapter-relative** (chapter 02's
first payload reads 1,536.014 s, continuing chapter 01's clock instead of resetting). The feared
failure mode — a consumer re-basing time per chapter — cannot occur because the camera never
re-bases it.

---

### 2026-08-07 - GoPro plan: five implementation-level design calls

**Context:** Writing `IMPLEMENTATION_PLAN-gopro.md` from the decision-complete spec required reading
the real integration points, which surfaced five questions the spec had left to implementation. All
five are structural — they decide what the code looks like, not just what it does — so they belong
here rather than only in a plan file, which is disposable by design.

**Decision 1 — the chapter number rides in `DJIClip.index`; a new `recordingNumber` carries identity.**
GoPro's `GXccnnnn` gives a 2-digit chapter and a 4-digit file number. The natural-looking mapping
(`index` = file number, the recording's identity) breaks two existing consumers that read `index` as
*position within the recording*: `WatchFolderCoordinator.swift:402` picks a group's last segment via
`max(by: index)`, and `continues()` checks `next.index == prev.index + 1`. Mapping **chapter →
`index`** keeps both correct with no change, and the file number becomes `recordingNumber` (GoPro
only, `nil` for DJI), used for bucketing.
**Consequences:** `index` is no longer unique across GoPro recordings, so the cross-group sort
tie-break (`ConversionViewModel.swift:204/247`) degrades to arbitrary order for two recordings that
share a `creationDate` — cosmetic. `ProcessedGroupLedger.fingerprint` is unaffected (it includes
`stem`, `:92`).

**Decision 2 — the grouping bucket key becomes `family|variantSuffix|recordingNumber`.**
`groupMetas` buckets on `variantSuffix ?? ""` (`DJIFolderReader.swift:180`). Every GoPro clip has a
`nil` suffix, so without this change all GoPro recordings would share one bucket with the legacy
DJI clips. Bucketing on the recording number is also what makes "different file number ⇒ different
recording" hold for free, independent of temporal adjacency.

**Decision 3 — the gpmd `-map` index is probed from segment 1 at join time, never from persisted state.**
The concat demuxer presents the **first file's** stream layout, and the measured index differs by
source (3 in a camera original, 2 after a remux — spec finding D). `streamInfo.dataStreamIndex`
persisted on a clip is therefore a grouping/verification signal only; the join resolves its own.
**Consequences:** `mergeClips` gains a data-stream policy and does the probe itself; a group whose
segments disagree on gpmd presence is refused before ffmpeg runs.

**Decision 4 — nothing selects the telemetry stream as `d:0`.**
ffprobe reports `tmcd` with `codec_type=data`, so `-select_streams d:0` can resolve to the timecode
track instead of gpmd. That failure is silent and *worse than a crash*: it would yield a **passing**
telemetry check that had verified the wrong stream. Every gpmd selection — merge args, Tier 0/1
parity, Tier 2 hash — uses the resolved absolute index with `codec_tag_string == "gpmd"` as the
predicate.

**Decision 5 — a GoPro chain requires timecode on both sides, or it doesn't chain.**
GoPro chapters share one `creation_time`, so the DJI wall-clock rule is inapplicable and timecode
continuity is the continuity signal. With timecode missing on either side we cannot confirm, so we
split into singles rather than guess — the same "can't confirm ⇒ don't chain" stance step 5 of the
DJI rule already takes. Safe failure (an unjoined recording the user can see), never a wrong join.
All 71 corpus files carry `tmcd`, so it should never fire in practice.

**Also decided (process, not architecture):** the GoPro plan lives in its own file rather than
overwriting `IMPLEMENTATION_PLAN.md` — the v1 file documents the shipped waves 0–6 that
`PROJECT_STATE` still cites, and a feature plan for a shipped app doesn't replace it. `docs/TASKS.md`
was introduced (the project had none) for sprint checkboxes only; execution detail stays in the plan.

---

### 2026-08-07 - Queue persistence: an explicit-key decoder, and every persisted enum decodes tolerantly

**Context (Wave G0, implemented).** Everything in the queue — jobs, clips, verification results —
round-trips through one `decode([ConversionJob].self)` in `QueueManager.loadQueue`
(`QueueManager.swift:253`). Its `catch` at `:301` logs to the debug console and moves on, so *any*
decode failure anywhere in the blob doesn't degrade one job: it silently discards the user's entire
queue on the first launch after an update. The GoPro pass adds fields to `DJIClip` and a check kind
to `VerificationCheck`, so this had to be closed before either landed.

**Reproduced before fixing, not assumed.** A probe `var hazardProbe: Int = 0` on `DJIClip` failed all
10 compat tests with `keyNotFound … Path: [0].clips[0]`, and the app's own "Failed to load queue"
line appeared in the output. Worth recording the near-miss: the *first* probe used
`let hazardProbe: Int = 0` and everything stayed green — Swift omits an immutable property with an
inline default from Codable synthesis entirely. That exemption is invisible at the call site and
evaporates the moment the property becomes a `var`, so it is not something to rely on. The plan's
"even with a default value" is right for the case that matters.

**Decision 1 — `DJIClip` gets hand-written `CodingKeys` + `init(from:)`.** Explicit keys for all 13
stored properties; `decodeIfPresent` for every Optional; plain `decode` only for the six fields that
existed in 1.0.4 and make a clip meaningless when absent (`id`, `videoFilePath`, `index`, `stem`,
and the duration backing pair). `encode(to:)` stays synthesized — it uses the same keys and writes
Optionals with `encodeIfPresent`, so the on-disk shape is byte-identical to 1.0.4's. The rejected
alternative was "just make every new field Optional": it works, but it leaves the trap armed for
whoever adds the next field, and the failure is invisible until a user loses their queue.

**Decision 2 — the safety net is a real blob, not a synthetic one.** The fixture is the actual
`queue.json` the shipped 1.0.4 wrote on 2026-07-18, trimmed to four jobs. Two are verbatim (a 4- and
a 5-segment split, verified, with bookmarks and SRT sidecars); two are the same real job hand-edited
to carry `pending` and `failed(String)` — the only statuses `loadQueue` actually restores, and
neither occurs in a queue whose jobs all finished. A hand-built fixture would have encoded today's
assumptions about the format, which is exactly what it exists to test.

**Decision 3 — the tolerant fallback is a new `unknown` case, not a remap to an existing one.**
`VerificationCheck.Kind` gains `unknown`; an unrecognised raw value decodes to it. Mapping to
`.readability` (or any real kind) would have been less code but would assert a check that never ran.
Nothing switches exhaustively on `Kind` — all four consumers do equality lookups — and `label` /
`detail` are plain strings that survive intact, so an unknown check still displays correctly; only
its identity is coarsened.

**Decision 4 — the same tolerance extends to `Tier` and `CheckSeverity`.** The plan named only
`Kind`, but both siblings are `RawRepresentable` and sit in the same blob, so either one defeats the
protection on its own. `Tier` falls back to `.fast` (the weaker claim — a rollback must never
over-state what was verified); `CheckSeverity` clamps to `.warning` (a value this build doesn't
understand is worth surfacing, not hiding).

**The limit, stated plainly:** all of this protects builds from here forward. A blob written by a
future build and read by the *shipped* 1.0.4 still throws — 1.0.4 has no fallback, and nothing here
can change that retroactively. The practical consequence is that a user who rolls back to the 1.0.4
DMG after running a newer build may lose a pending queue.

**Also found, deferred:** `QueuePanel.swift:660` renders flagged checks with
`ForEach(flagged, id: \.kind)`. That assumes kind is unique per result — which G5.1 breaks the moment
it emits a per-stream telemetry check alongside the existing per-stream packet checks (two would
share `packetCount`), and which two `.unknown` checks would also break. Not touched here (it's a UI
change and G0 is engine-only); noted on the G5.1 row of the plan.

### 2026-08-07 - The persisted-clip encoder is hand-written too, and that needs its own guard
**Context:** Wave G1 added `family` (a `CameraFamily`) to `DJIClip`, the first non-Optional field
added since G0 hand-wrote the *decoder*. `DJIClip` is persisted in `queue.json`. A synthesized
`encode(to:)` writes every non-Optional property unconditionally, so it would have emitted
`"family":"dji"` into every DJI clip on disk — the overwhelming majority of clips users have — which
changes the on-disk shape shipped 1.0.4 writes and trips G0.1's pinned key set
(`testReEncodingAClipProducesTheSameKeysAsShipped104`). That test exists precisely so a *downgrade*
or rollback DMG isn't handed a shape it never wrote.
**Options Considered:**
1. Make `family` Optional (`CameraFamily?`) — the synthesized encoder would then use
   `encodeIfPresent` and omit it when nil. Rejected: it pushes `nil`-vs-`.dji` ambiguity into every
   read site forever, to dodge a one-time encoder problem. The model fact is that every clip *has* a
   family.
2. Accept the new key on disk and update the pinned key set. Rejected: that is exactly the
   "edit the stop-the-line test to go green" move G0 forbids, and it silently widens what an older
   build must tolerate.
3. **Hand-write `encode(to:)`, omitting `family` at its `.dji` default.** Chosen.
**Decision:** `DJIClip.encode(to:)` is hand-written. A DJI clip's JSON stays byte-identical to what
1.0.4 wrote; a GoPro clip writes `family` explicitly; `init(from:)` maps an absent key back to `.dji`,
so missing-key and default converge. `CameraFamily` carries a `String` raw value (not an integer
ordinal, which would shift under existing blobs when a third family — Osmo — is inserted) and decodes
tolerantly to `.dji` on an unrecognised value, following G0.3's pattern for the verification enums.
**Rationale:** The default-omission keeps the *shape* stable, which is the thing old builds and
rollback DMGs actually depend on, without deforming the model to suit its serializer.
**Consequences — the important half.** Hand-writing the encoder trades G0's hazard for its **mirror
image**, and the mirror is quieter. G0's failure was a `keyNotFound` throw that discarded the queue:
catastrophic but detectable. This one is a field added to `CodingKeys` and to `init(from:)` but
**forgotten in `encode(to:)`** — it is simply never written, reloads as its default every launch, and
*no test goes red*. So the G0 standing rule now has three parts, not two: **a new `DJIClip` field
needs a `CodingKey`, a `decodeIfPresent`, and a line in `encode(to:)`.** Enforced by making
`CodingKeys` `CaseIterable` and pinning the encoded key set against `allCases`
(`QueuePersistenceCompatTests.testEncoderWritesEveryCodingKeyForAFullyPopulatedClip`), which lives in
the G0 stop-the-line file where the next contributor will already be looking. Per the G0 precedent the
guard was **verified by reproduction, not assumption**: a `probeFutureField` key injected into
`CodingKeys` made it fail naming exactly the missing key, and was then reverted. A guard never
observed to fail is not yet a guard.

---

### 2026-08-07 - The telemetry probe keeps synthesized Codable, and its two "harmless" assumptions were not

**Context:** Wave G2.1 had to make `StreamParameterGuard.parse(ffprobeJSON:)` retain three new facts
about a GoPro file — the `gpmd` telemetry stream's index, its codec tag, and the file's start
timecode — so Wave G4 can hand the index to `-map`. The struct that carries them,
`SegmentStreamInfo`, is embedded on `DJIClip` and therefore lives in the user's `queue.json`, which
is exactly the blast radius waves G0 and G1 spent themselves protecting.

**Decision 1 — `SegmentStreamInfo` keeps *synthesized* `Codable`; it does NOT follow `DJIClip`'s
hand-written treatment.** The three new properties are declared as Optionals with `= nil` defaults.
Under synthesis that yields `decodeIfPresent` on the way in (a shipped-1.0.4 blob lacking the keys
still decodes) and `encodeIfPresent` on the way out (nil fields are omitted), plus a
source-compatible memberwise initializer so the six existing test files that construct
`SegmentStreamInfo(video:audio:)` needed no edits.

**Why:** The G0/G1 rule is often mis-stated as "hand-write the Codable conformance." That is the
remedy, not the rule. The actual rule is *decode leniently and encode completely*, and Optionals
under synthesis already satisfy both — `DJIClip` only needed hand-writing because it has
non-Optional fields (`family`) whose synthesized encoding would have changed the on-disk shape.
Hand-writing `SegmentStreamInfo` would buy nothing and would newly arm G1's encoder-omission hazard
here, where it currently cannot exist. Applying the remedy where the disease is absent is how a
safety rule becomes cargo cult.

**Decision 2 — select the data stream by `codec_tag_string`, never by `codec_name` or position.**
Measured on real Hero 11 footage before writing any code: gpmd sits at index **3** in an original
with audio, index **2** in a no-audio original, and index **2** in a remux where ffmpeg regenerated
`tmcd` *after* gpmd. `codec_name` is unusable as a predicate because `tmcd`'s is `null`, and
position is unusable because it moves for two independent reasons. This is the concrete evidence
behind the plan's standing rule never to resolve telemetry as `d:0`.

**Two assumptions in the task description that turned out false — both corrected, neither absorbed
silently:**
1. **The specified fallback was unreachable.** The task said to read the timecode from the `tmcd`
   stream's tags, "falling back to format tags". But `probeStreamInfo` invoked ffprobe with
   `-show_streams` only, so no `format` object was ever returned and the fallback could never have
   run. `-show_format` is now passed and `FFProbeStreams.format` is Optional, so existing tests whose
   fixtures are streams-only literals still decode. A fallback that cannot execute is worse than no
   fallback: it reads as coverage.
2. **"DJI's persisted shape is unchanged" is only two-thirds true.** It holds for the two gpmd
   fields, which stay nil on DJI footage. It does **not** hold for `startTimecode` — DJI files carry
   a `tmcd` track, so a DJI clip probed by this build now writes a `startTimecode` key it did not
   write before. This is additive and safe in both directions (Codable ignores unknown keys, so
   shipped 1.0.4 still reads such a blob) and G3.2 needs the value, so it was kept — but it is a
   shape change, and the round-trip test that "proves DJI's shape is unchanged" only proves it for
   the nil case.

**Consequences:** `check(_:)` is untouched, so join-compatibility verdicts are byte-for-byte the
decisions 1.0.4 made; refusing a mixed telemetry layout is deferred to G4.2 with its own message.
Suite 525 → 531, 0 fail, with **0 deletions** in the test diff. Three fixtures are real
`-show_streams -show_format` captures from actual Hero 11 files (`format.filename` sanitized to a
basename — the repo is public); the DJI case is an inline literal explicitly labelled hand-built,
because no DJI card was mounted and a fabricated fixture presented as a capture would be worse than
an honest one.

---

### 2026-08-07 - The seam fixture cannot be camera-shaped, which makes G8.2 load-bearing
**Context:** Wave G4.3 needed a checked-in fixture proving a GoPro chapter seam joins with its
`gpmd` telemetry intact. Cutting one from real Hero 11 footage runs into a hard tool constraint:
ffmpeg **cannot copy GoPro's source `tmcd` track**. Attempting it (`-map 0`) fails with *"Could not
find tag for codec none in stream #2"* and leaves a **zero-byte output** — the same finding that
forces the production join to map streams explicitly. So any cut must map streams by hand, and
ffmpeg then drops the source `tmcd` and regenerates one **after** `gpmd`.
**Consequence discovered:** the fixtures carry `hvc1 | mp4a | gpmd | tmcd` — **gpmd at index 2** —
whereas every camera original carries `hvc1 | mp4a | tmcd | gpmd` — **gpmd at index 3**.
**Options Considered:**
1. Ship the fixture and call G4 fully proven — **rejected as a false claim**. The end-to-end path
   would be proven only for the stream order the fixture happens to have, which is *not* the order
   any real card produces.
2. Synthesize a fixture with `tmcd` ahead of `gpmd` — not possible with this toolchain; the
   constraint above is exactly what prevents it.
3. Ship the fixture, state the limit precisely, and name the task that closes it. **Chosen.**

**Decision:** Accept the index-2 fixture, and record that **index 3 — the shape of every camera
original — is covered only by `FFmpegConcatArgsTests`' exact-vector assertions and by the join-time
probe, never end-to-end.** **Task G8.2 (a real full join of an unsliced GoPro group) is therefore
the only thing that closes the gap**, and is promoted from "final eyeball" to load-bearing coverage.
**Rationale:** This is written to `decisions.md` rather than left in `IMPLEMENTATION_PLAN-gopro.md`
because that plan declares itself disposable ("regenerate if the trajectory diverges"). A regenerated
plan would silently lose the fact that the wave's end-to-end proof has a hole in it — and the hole is
invisible: the test is green, the numbers are byte-exact, and nothing about the passing run hints
that the stream order under test is not the one users have.
**Consequences:**
- G8.2 must not be skipped or deferred as ceremony; it is the coverage.
- The limit is stated in three places that a future contributor will actually hit:
  `Fixtures/gopro-seam/README.md`, the test's own header doc comment, and PROJECT_STATE's `Now`.
- If a later change makes the join index-sensitive again, the fixture will **not** catch it.
- Related: the byte-total assertions carry the weight over packet counts — gpmd runs at 1 packet per
  second against a 1.04 s keyframe floor, so each slice holds exactly one telemetry packet. That
  thinness is a measured floor of `-c copy`, not a shortcut.

---

## 2026-08-08 — An incomplete GoPro chapter set warns, but still joins

**Context.** The spec (`specs/gopro-camera-family.md`, Grouping criteria) said a folder holding
chapters 02..N with no chapter 01 should be "flagged incomplete **and not joined**", and the G3.4
plan row repeated it as "**not joinable** (excluded from enqueue)".

**Decision (user's, at G3.4 sign-off).** Flag it, but leave it joinable and enqueueable. No
exclusion gate, no confirmation dialog.

**Why.**
- A joined chapters-02..N output is a **valid, playable, correct MP4** — it just isn't the whole
  recording. Nothing corrupts, so there is no correctness argument for the block, only a
  did-you-mean one; a chip says that just as well.
- The measured corpus contains a **real specimen**: recording 6338's chapter 01 left the V26
  archive in the user's own 2026-08-07 clear-out, leaving chapter 02 alone. A hard block would
  permanently lock those files out of the app.
- This is the mirror of the index-gap guard's reasoning (2026-06-24) but lands the other way, and
  the difference is the point: that guard prevents a **silent corrupt merge** — a real
  data-integrity failure the user cannot see. This one would prevent a **correct join the user
  asked for**. Refusing to act is only the safe default when acting can produce a wrong artefact.

**Consequences.**
- `RecordGroup.completeness` is **display-only**. The rationale lives on that property's doc
  comment so the next reader doesn't "fix" the code back to the spec text, and a test
  (`testIncompleteGroupIsStillReturnedAndJoinable`) pins it.
- The spec's acceptance criterion and the G3.4 plan row are now **superseded on this point**; both
  carry an amendment note rather than being rewritten, so the change of mind stays visible.
- If a "don't let me do this by accident" signal is ever wanted, it should be a confirmation, not
  an exclusion — the group must stay reachable.

## 2026-08-08 — GoPro chapters chain on timecode, and the 1 ms slack was measured against the right clock

**Context.** DJI chains segments on the **file-size split cap + wall-clock `creation_time`**. Neither
signal works for GoPro: the split cap is not a constant (6349 capped at 10.8471 GiB @25 fps vs
~10.718 GiB for the 100 fps recordings), and recording 6338's two chapters carry an **identical**
`creation_time`, so DJI's wall-clock rule would refuse a real, valid chain.

**Decision.** `continues()` dispatches on `family`. `continuesDJI` is the shipped body, untouched.
`continuesGoPro` chains on same recording number + consecutive chapter + stream-param compatibility
+ **timecode continuity**: `tc(N+1) − tc(N)` must equal chapter N's container duration within
`timecodeContinuitySlackSeconds` (1 ms). No size-cap gate, no wall-clock gate.

**The part worth writing down.** The slack was first derived from ffprobe's `format.duration` in the
corpus CSV — but production feeds this check `DJIClip.durationInSeconds`, i.e. **AVFoundation's
`CMTime`**. Those are not the same number in general: ffprobe's own `format` and `video` stream
durations already disagree by up to **0.667 ms** on this corpus, which would have eaten most of a
1 ms budget while every unit test still passed, because the fixtures carry CSV numbers rather than
the production source. Re-measured on all 13 non-final chapters via `asset.load(.duration)`:
AVFoundation reports the format duration **exactly** (768.000000000 s and 2063.360000000 s at
timescale 90000), so every residual is zero and the ~9 orders of margin is real. Recorded in the
tolerance's doc comment.

**Also locked:** timecode→seconds divides `totalFrames` by the **actual** fps, never the rounded one.
`Timecode.totalFrames` deliberately decomposes `HH:MM:SS:FF` at the rounded rate (correct — non-drop
counts 30 frames per timecode-second at 29.97), but converting that count to real elapsed seconds
needs the true rate: 1800 frames of 29.97 non-drop is **60.06** real seconds, not 60.00. The error is
invisible on this integer-fps corpus (25/50/100/200) and silently wrong on the NTSC rates a Hero 11
can also shoot.

## 2026-08-09 — The telemetry check is verified by absolute index, and its new kind is a one-way door

**Context.** Wave G5 taught verification to check GoPro's in-container `gpmd` telemetry stream, at
Tier 0/1 (packet-count and byte parity) and Tier 2 (byte-exact MD5). Before it, a join could lose or
corrupt telemetry and still seal green at every tier.

**Decision — absolute index, never `d:0`, resolved separately per side.** `d:0` selects whichever
data stream comes first, which on a GoPro camera original is the `tmcd` timecode track. The failure
mode is silent and the worst kind: a *passing* check that verified the wrong stream. Both sides
therefore select by absolute index matched on `codec_tag_string == "gpmd"`, and the Tier 2 map-arg
vector is built **twice** — the join re-orders streams, so one shared vector would hash two different
streams and compare them. A `nil` index (every DJI job) reproduces the shipped argument vector
exactly, pinned by exact-vector assertions rather than a fuzzy check.

**Reversed mid-wave: the output index is probed, not derived.** It was first computed as
`hasAudio ? 2 : 1` from the join's `-map 0:v:0 -map 0:a? -map 0:<i>` order. A cold review disproved
the premise by experiment: **`-map 0:a?` maps *all* audio streams**, so a two-audio-track source puts
gpmd at output index 3 while the formula says 2 — the check would then compare gpmd against audio and
hard-fail a byte-perfect join. The formula was also only "tested" tautologically (the test restated
it) and the fixtures happen to put gpmd at index 2 on both sides, so nothing could have caught it.
The output is now probed directly, which also turns "the join dropped gpmd" into a *named* failure
instead of a skipped check.

**Also closed: a GoPro job whose layout is unknown must not seal green.** `streamInfo` is populated
with `try?` at discovery, while the join resolves the index freshly at join time. So a probe hiccup
let a job join **with** telemetry and then verify with **no telemetry check at all**, reporting "All
checks passed" — the exact hole the wave exists to close. A GoPro job that cannot resolve its layout
now emits a `.warning` ("telemetry not verified — stream layout unknown"), which also auto-escalates
to Tier 2. DJI jobs stay silent.

**Also closed: the Tier-2 seal no longer forgives a telemetry failure.** `mapStatus` lets a passing
byte-exact hash forgive Tier-1 deltas, on the sound reasoning that the hash proves the media
identical — but that only holds for streams the hash actually covered, which is why `tmcd` already
had a carve-out. When telemetry is missing, Tier 2 falls back to hashing video+audio only, so without
a matching carve-out a GoPro join that dropped telemetry would fail Tier 1 loudly, escalate, and then
seal `.verified`. `gpmd` now shares `tmcd`'s carve-out for the same stated reason.

**Accepted, with eyes open: the new `Kind` case is a one-way door.** `gpmdParity` is the first new
`VerificationCheck.Kind` since shipping. G0.3 gave `Kind` a tolerant decoder, but **1.0.4 predates
it** — so a queue written by a build carrying this wave and then read by a *reinstalled* 1.0.4 throws
at `QueueManager.swift:256` and the catch at `:301` discards the user's entire queue. G0.3 recorded
this limit at the time ("nothing here can change that retroactively"); this entry is where the cost
is actually incurred. The downgrade-safe alternative was to reuse `packetCount`/`packetBytes` and
carry gpmd-ness only in the label, which 1.0.4 already tolerates as a plain string. Rejected: it
would make the telemetry verdict indistinguishable from a video verdict in code, for a rollback path
that only occurs on a manual reinstall of an older DMG. **Owed at release:** a line in the 1.0.5
release notes that downgrading to 1.0.4 clears the queue.

**Named, not fixed.** The case name is `gpmdParity`, not `telemetryParity`, because
`QueuePersistenceCompatTests` already uses the literal `"telemetryParity"` as its unknown-kind
fixture — the obvious name would have turned a protected test's placeholder into a real decodable
case. And a **camera-original layout (gpmd at index 3) still has no end-to-end coverage** at either
tier: the seam fixtures are remux-shaped with gpmd at 2 on both sides, GoPro's source `tmcd` cannot
be `-c copy`'d, and so the positive fixture test cannot by itself catch a shared-vector regression.
The unit tests and the wrong-stream negative tests carry that coverage until G8.2 runs on real
footage.

---

## 2026-08-09 — GoPro's complete-set gate goes relative, but keeps an absolute floor for the first chapter

**Context.** Wave G6 is the watch-folder's "has this recording finished arriving — safe to join?"
gate. The shipped rule is DJI-shaped: the last segment is final when it is below an absolute
`splitThreshold` (3.9 GB), ANDed with a quiet window. G3 established that GoPro has **no constant
split size** — the cap moves with fps (10.8471 GiB @25 fps vs ~10.718 @100 fps) — so an absolute
threshold is wrong in both directions for it.

**Decision — a relative rule when a reference exists.** A GoPro chapter is final when its size is
below `0.94 ×` the smallest **preceding** chapter of the same recording. Measured on the real
71-file corpus, the two clusters are cleanly separated but the band is narrower than it looks:
final chapters run **0.0762–0.8850** (tightest: recording 6348 chapter 03 at 0.88495) and non-final
chapters run **0.99989–1.00015**. Two consequences are pinned by tests: 0.94 is roughly centred in
that ~11-point gap, and the comparison must be a strict `<` because a non-final ratio can **exceed
1.0** — a later chapter can be marginally larger than the smallest earlier one.

**The plan was wrong about the no-reference case, and following it would have been a regression.**
The task text said "with only one member and no reference, the quiet window alone decides". That is
right for a genuine single-chapter recording, but mid-copy a 4-chapter recording *is* a one-member
group — only chapter 01 has landed. Under the plan's rule an 11.5 GB chapter 01 would pass the gate
after 45 s of quiet and be joined **alone**, producing a truncated output plus an orphan group for
the remaining chapters. The shipped absolute rule blocks that correctly today (11.5 GB > 3.9 GB), so
the plan as written would have made GoPro watch-folder behaviour *worse* than 1.0.4.

**Resolution — a 9.5 GB no-reference floor** (user decision). With no usable reference, a lone
chapter at or above 9.5 GB still expects a continuation; below it, the quiet window decides. The
corpus leaves a wide empty band to place this in: the largest genuine single-chapter recording is
**7.66 GB** (GX016350) and the smallest cap-filled chapter is **11.4976 GB** (6338 ch01), so 9.5 GB
clears both by ~2 GB. This does reintroduce a constant, which decision Q3 wanted to avoid — accepted
knowingly, because the alternative is a premature join. Rejected alternatives: *follow the plan
literally* (regression above); *fall back to the existing `splitThreshold`* (3.9 GB is far below
GoPro's cap, so a real 7.66 GB single-chapter recording would stall and never auto-enqueue).

**Hardened past the task text: a stray zero must not poison the reference.** Non-positive preceding
sizes are filtered out **before** `min()`. A bare `min()` would do two bad things at once — make the
ratio comparison `x < 0`, never true, stalling the group forever; and discard a genuine reference
sitting beside the zero, falling to the floor branch, which for a 9 GB last chapter flips the verdict
from "wait" to "join now". Filtering keeps the real reference and so errs toward "expect
continuation", the safe direction. Defensive only: `FileStabilityGate.isSettled` requires
`samples.count >= requiredStablePolls`, so an unsampled clip fails Gate 1 before this gate runs.

**Shape.** The existing 4-argument `isComplete` is left byte-for-byte untouched and the new
family-aware overload **delegates to it verbatim** for `.dji`, so the DJI verdict is unchanged by
construction rather than by assertion. The existing `CompleteSetGateTests` needed **zero edits**,
which is the evidence.

**Verified by falsification, both branches.** The corpus test walks all 6 multi-chapter recordings
at every prefix length `k = 1...N`, asserting complete iff `k == N`, plus all 51 singles complete
once quiet. Ratio → 0.5 fails the three tightest finals (6345 ch04, 6346 ch04, 6348 ch03); floor →
20 GB fails all six recordings at **chapter 1/N** — precisely the premature-join regression the floor
exists to prevent. 590 → 605 tests, 0 fail.
