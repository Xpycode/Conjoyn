# GoPro Camera Family Specification

**Status:** Draft — **all 6 open questions resolved 2026-08-07**; ready for `/make-plan`
**Created:** 2026-08-07
**Last Updated:** 2026-08-07

> Second camera family for Conjoyn (shipped 1.0.4/104, 495 tests). Everything in this spec is
> grounded in a **measured 71-file Hero 11 corpus** (2026-08 archive folder, 0 probe failures)
> plus real full-join and seam-slice experiments run 2026-08-06/07. Facts below are labeled
> **measured** (ran against real footage) or **unverified** (inferred, no sample). Corpus detail:
> scratchpad `gopro/grouping-truth.md` + `corpus.csv` (session-local — key numbers are inlined
> here because the scratchpad is ephemeral).
>
> ⚠️ **Corpus drift, noted 2026-08-07:** the archive folder held **71** MP4s when probed on
> 2026-08-06/07; it holds **70** now — `H11--2026-08-03--11-52-11--GX016338.MP4` (chapter 01 of
> recording 6338, 11,497,577,082 bytes) is gone from the volume, with no joined output or trash
> entry to account for it. The user cleared out the (separate) `2026-07` folder the same day —
> see Q6 — so this is plausibly the same clear-out reaching one August file. **All fixture numbers
> in this spec stay as measured on the 71-file corpus** — the grouping tests are file-free
> in-memory fixtures, so they are unaffected. Side effect: the live folder now presents recording
> 6338 as *chapter 02 with no chapter 01*, a real specimen of the incomplete-set case below.

---

## Problem Statement

### What problem does this solve?
GoPro cameras chapter long recordings exactly like DJI drones split theirs — a Hero 11 cuts a
new `GXccnnnn.MP4` every **~10.7–10.85 GiB** (measured band across all 14 non-final chapters:
11,497,577,082–11,646,991,608 bytes — *not* the 4 GB FAT32 story the app's UI copy currently
tells). Conjoyn today rejects every GoPro file at the filename parser, and even if a group were
forced through, the shipped merge args (`-map -0:d`) **verifiably drop the `gpmd` telemetry
track** — the joined file would silently lose GPS/gyro/accelerometer data (measured, finding E).

### Who has this problem?
The user, immediately: a Hero 11 archive with 71 MP4s / 6 chaptered recordings in one month
folder, plus a GoPro 7 (same GX/GH naming). Anyone re-joining chaptered GoPro footage generally.

### How do they solve it today?
Manual concat in an NLE or hand-rolled ffmpeg — which with naive args either fails hard
(`-map 0` errors on the codec-`none` tmcd track and writes a **zero-byte file**, measured,
finding C) or drops telemetry.

---

## Proposed Solution

### One-Liner
Add a **camera-family layer** so the existing engine recognizes, groups, and losslessly joins
GoPro GX/GH chaptered recordings **with the `gpmd` telemetry track preserved verbatim** through
the join — while the DJI path keeps byte-identical behavior.

### Key Capabilities
1. **Parse** GoPro chaptered names `GX`/`GH` + 2-digit chapter + 4-digit file number
   (`GX016338.MP4`), including the archive's rename prefix (`H11--2026-08-03--11-52-11--GX016338.MP4`),
   with the tail anchored so `_joined` output never re-parses as source.
2. **Group** by file number + consecutive chapters + stream-param equality + timecode
   continuity. The DJI wall-clock rule (`gap > 0`) is **inapplicable**: `creation_time` is
   *identical* across all chapters of every measured group. Timecode is the strong signal —
   `tc(N+1) − tc(N) == duration(N)` held **exactly at all 15 measured transitions** (max
   residual 1.1e-11 frames).
3. **Join** with explicit stream mapping that carries `gpmd` through `-c copy`:
   `-map 0:v:0 -map 0:a? -map 0:<resolvedGpmdIndex> -c copy -copy_unknown` (+ existing
   `+genpts`, `+faststart`, `creation_time`, `-timecode`). tmcd stays unmapped and is
   regenerated. The gpmd index is **resolved by probing** `codec_tag_string == "gpmd"`, never
   positional (measured: index 3 in camera originals, index 2 after a remux — finding D).
4. **Verify** the gpmd stream in the source-vs-target pass (packet-count parity; tier-2 hash).
5. **Locked architecture decision:** the family layer is added *around* the existing
   DJI-prefixed types (`DJIClip`, `DJIFilenameParser`, `DJIFolderReader`). The neutral rename
   is explicitly a later, separate change — do not re-litigate.

### User Flow
1. User points Conjoyn (picker, drag-drop, or watch folder) at a folder of GoPro footage.
2. Scan detects GoPro names alongside DJI ones; chaptered recordings appear as groups with the
   same continuity report DJI groups get.
3. User confirms; join runs; output is `<stem>_joined.mp4` with video, audio, gpmd, corrected
   creation_time and regenerated timecode.
4. Verification reports per-stream parity including telemetry; originals untouched.

**UI impact is copy-only** (empty-state text, skipped-file wording, the wrong "4 GB card limit"
pitch). No new controls or panes → no conflict with the project UI conventions
(no `NavigationSplitView` in the primary window, etc.; `47_project-ui-conventions.md`).

---

## Acceptance Criteria

Measured corpus = the 71-file 2026-08 folder (the only folder holding MP4s — see Q6): 6 multi-chapter groups
(6338, 6345, 6346, 6347, 6348, 6349), 51 single-chapter files, all `GX`, all hevc/`hvc1`.

### Parsing
- [ ] Given `GX016338.MP4`, when parsed, then it yields family GoPro, chapter 1, file number
      6338, and is accepted as video source.
- [ ] Given the renamed archive form `H11--2026-08-03--11-52-11--GX026338.MP4`, when parsed,
      then it yields chapter 2, file number 6338 — the existing optional rename-prefix rule
      (prefix must end in a separator) applies to GoPro names too. (All 71 corpus files carry
      this prefix; the prefix timestamp equals `creation_time` at +02:00 on all 71 — measured.)
- [ ] Given `GX016338_joined.mp4`, when parsed, then it is **rejected** — the GoPro regex is
      tail-anchored exactly like the DJI one, so the app never re-ingests its own output.
- [ ] Given `GH010123.MP4`, when parsed, then it is accepted with the same structure as `GX`
      (chaptered AVC naming). Decision Q2 (2026-08-07): ship **GX-validated**, and close the
      biggest part of the GH risk with **one short H.264 capture** (below) rather than a ~30 min
      chaptered one.
- [ ] **Footage-gated pre-req (cheap):** a single ~30 s clip shot on the Hero 11 with video
      compression set to **H.264**, when probed, confirms the GH file name, the
      `avc1|mp4a|tmcd|gpmd` stream layout, gpmd presence, and the TC↔creation_time relation. Only
      *chapter-level* GH behaviour is then taken as symmetric with GX (no 11 GB capture needed).
- [ ] Given legacy `GOPR0123.MP4` or `GP010123.MP4`, when scanned, then it is *not* parsed as
      GoPro (out of scope this pass) and lands in the existing skipped-file count.
- [ ] Given all 71 corpus filenames, when parsed, then 71/71 succeed with the correct
      (chapter, file number) pairs and zero misclassifications.

### Grouping
- [ ] Given the 71-file corpus, when scanned, then exactly **6 multi-chapter groups and 51
      single-chapter recordings** are produced, with 0 probe failures.
- [ ] Given the 5 chapters of recording 6347, when scanned, then exactly one group of 5
      segments totalling **3195.780 s / 47,889,205,619 bytes** is produced, ordered ch01–05.
- [ ] Given recording 6338 (ch01 1536.000 s + ch02 116.992 s), when scanned, then one group of
      2 totalling 1652.992 s — even though both chapters share the **identical**
      `creation_time` `2026-08-03T11:52:11Z`. The GoPro chain rule must not require the DJI
      `gap > 0` wall-clock condition (identical creation_time across chapters holds in **all
      6 measured groups**).
- [ ] Given any two adjacent chapters in the 6 groups, when continuity is evaluated, then
      timecode continuity passes: `tc(N+1) − tc(N)` equals chapter N's container duration
      (measured exact at all 15 transitions).
- [ ] Given single-chapter `GX016350` recorded minutes after group 6349 finished, when scanned,
      then it is **not** merged into 6349 (different file number ⇒ different recording,
      regardless of temporal adjacency).
- [ ] Given the corpus-wide mix of 25/50/100/200 fps and 3840x2160 / 2704x1520 / 5312x2988,
      when scanned, then no cross-recording merge occurs and every produced group is internally
      uniform in codec/resolution/fps/stream-layout (true of all 6 measured groups).
- [ ] Given chapters 01 and 03 of a recording with 02 absent, when scanned, then **no group
      spans the gap** — chapters must be consecutive (camera writes 01..N with no skips;
      measured across all 6 groups) — and the incomplete set is flagged, not silently joined.
- [ ] Given any GoPro group, when the split-cap/complete-set logic runs, then **no absolute byte
      constant is consulted** (decision Q3, 2026-08-07). Grouping is decided by chapter numbering
      + stream-param equality + timecode continuity alone; the "expect a continuation" signal for
      the watch-folder complete-set gate is **relative** — non-final chapters of one recording are
      near-equal in size and the final one is smaller — plus the existing quiet window. DJI's
      `capSizeFloorBytes` / `capSizeFraction` are **not** reused, and no GoPro constant replaces
      them. Rationale: the measured cap is *not* a fixed byte count (6349 @25 fps capped at
      10.8471 GiB vs ~10.718 GiB for the 100 fps recordings), it is calibrated on one
      camera+firmware, and the user's own Hero 7 is a generation that splits far lower (~4 GB).
      A relative rule holds for all three without a table.
- [ ] Given the 14 measured non-final chapters (11,497,577,082–11,646,991,608 bytes) and their
      smaller final chapters, when the relative rule is applied to each of the 6 groups, then
      every non-final chapter is classified "expect continuation" and every final chapter closes
      the set — i.e. the relative rule reproduces the absolute rule's verdict on the whole corpus.

### Join + telemetry
- [ ] Given group 6338, when joined with the new args, then the output contains **exactly**
      165,299 video frames (153,600+11,699), 77,484 audio frames (72,000+5,484), 1,653 gpmd
      packets (1,536+117), duration 1652.990 s — all measured on a real full join (finding A;
      output 12,369,183,128 bytes against 12,373,524,901 measured in (11,497,577,082 + 875,947,819)
      — 4,341,773 bytes smaller, one saved set of container headers).
- [ ] Given the joined output, when probed, then exactly one data stream with
      `codec_tag_string == "gpmd"` is present, plus a regenerated tmcd from `-timecode`.
- [ ] Given a camera original (gpmd at stream index 3) and a remuxed copy (gpmd at index 2),
      when merge args are built for each, then the gpmd `-map` argument reflects the **probed**
      index in both cases — never a hardcoded position (finding D).
- [ ] Given any GoPro source, when merge args are built, then the tmcd track is **not** mapped:
      `-map 0` is a hard failure ("Could not find tag for codec none in stream #2" → zero-byte
      output file, finding C). The arg shape is
      `-map 0:v:0 -map 0:a? -map 0:<gpmdIndex> -c copy -copy_unknown` (finding F).
- [ ] Given a seam between two chapters, when joined, then gpmd is preserved **byte-exactly**
      across it (measured on a 25 s + 25 s seam slice: 25+25 = 50 packets, 219,220+219,236 =
      438,456 bytes; verifiable as a fixture-based test).
- [ ] Given the joined seam fixture, when its gpmd stream is walked as GPMF KLV, then **all 50
      `DEVC` payloads parse clean with no desync at the seam**, `STMP` is strictly increasing
      across the boundary with the same ~0.9985 s step as everywhere else, `GPSU` wall clock is
      continuous (…12:17:56.400 → …12:17:57.400), and the container packet PTS run 0.003 s →
      49.003 s with every delta exactly 1.000 s (measured 2026-08-07, finding G — this is what
      closes open question Q1; parser checked in at `01_Project/scripts/gpmf-dump.py`).
- [ ] Given the joined output, when its metadata is written, then `creation_time` and start
      timecode follow the existing resolveJoinMetadata path (chapter 01's TC is the group's
      start TC; TC = creation_time+02:00 + sub-second residual held on all 71 files — measured).

### Verification
- [ ] Given a joined GoPro output, when Tier 0/1 verification runs, then a **gpmd stream check**
      is included: sum of source gpmd packet counts equals output gpmd packet count (6338:
      1,536+117 = 1,653).
- [ ] Given a joined GoPro output, when Tier 2 (per-stream hash) runs, then the gpmd stream is
      hashed alongside video/audio.
- [ ] Given one of the 4 no-audio sources (`hvc1|tmcd|gpmd`), when verified, then the audio
      check is skipped (existing `hasAudio` gate) and video+gpmd checks still run.

### No regression to DJI
- [ ] Given the existing 495-test suite and DJI fixtures, when GoPro support lands, then all
      existing tests pass unchanged.
- [ ] Given a DJI group (no gpmd stream), when merge args are built, then the resulting ffmpeg
      invocation is **behaviorally identical** to 1.0.4's for DJI inputs (no data stream mapped;
      output byte-identical on the existing DJI regression footage).
- [ ] Given a `queue.json` persisted by shipped 1.0.4, when the new build launches, then the
      **entire queue decodes** — no job is dropped by the decode-failure catch. (See the
      Codable hazard below; this criterion needs a checked-in old-shape JSON fixture test.)

### Edge Cases
- [ ] Given the 4 no-audio 5312x2988@25 files (GX014617/4621/4622/4629 — all single-chapter,
      measured), when scanned, then each appears as a healthy single-chapter recording; absence
      of an audio stream is not an error.
- [ ] Given file-number gaps between recordings (measured: 4613→4616, 4637→6317, 6321→6330,
      6330→6332), when scanned, then no warning — gaps between *recordings* are normal (deleted
      or elsewhere; unknowable from headers). Only gaps between *chapters of one recording*
      block grouping.
- [x] Given a folder containing chapters 02..N but no 01, when scanned, then the set is flagged
      incomplete ~~and not joined~~ (a recording never starts above chapter 01 on camera —
      measured; ch01 elsewhere means the user split the copy).
      **Amended 2026-08-08 (G3.4 sign-off): flagged but STILL JOINABLE.** The "not joined" clause is
      superseded — a joined chapters-02..N file is a valid, playable, correct MP4, and this very
      corpus holds a specimen (6338's chapter 01 left the archive) that a hard block would lock out
      permanently. Implemented as `RecordGroup.completeness` → a warning chip; no enqueue gate.
      Rationale → `docs/decisions.md` (2026-08-08).
- [ ] Given the archive's month-folder split, when a recording's chapters are looked for, then
      they are assumed co-located: all chapters share `creation_time`, so the rename-then-file
      workflow puts a whole recording in **one** month folder (**assumption** — holds for all 6
      corpus groups; a hand-moved chapter degrades to the incomplete-set flag above, never a
      wrong join).
- [ ] Given the two files whose header `nb_frames` disagrees with duration×fps by >1.5 frames
      (GX014616: −1.87, GX014623: −3.00 — both single-chapter, measured), when scanned, then
      they still probe and list cleanly.
- [ ] Given a folder mixing DJI and GoPro footage, when scanned, then each family groups under
      its own rules and no cross-family group is ever formed.

### Error States
- [ ] Given a candidate group where some chapters have a gpmd stream and others don't, when the
      join is attempted, then the existing stream-param gate **refuses** the merge with a clear
      layout-mismatch message (never a silent partial-telemetry join). (**Unverified** — never
      observed; every measured group is layout-uniform.)
- [ ] Given ffmpeg exiting non-zero or producing a zero-byte output (the `-map 0` failure
      mode), when the join runs, then the job fails with the ffmpeg stderr surfaced and the
      originals are untouched.
- [ ] Given a GoPro folder scanned by a build without GoPro support -- i.e., today, when the
      user scans, then the empty state must explain *why* (the 2026-08-06 renamed-footage fix
      pattern); after this feature, the "No DJI recordings found" copy at
      `ConversionViewModel.swift:346` must not misname GoPro files as non-recordings.
- [ ] Given any empty state, when the split-recording explanation is shown
      (`RecordingsList.swift:501-502`), then it names **no file-size figure** (decision Q4,
      2026-08-07) — e.g. *"Long recordings get split into several files on the card. Conjoyn
      finds those pieces and joins them back into one."* No number is true across DJI (~4 GB),
      Hero 11 (~10.7 GiB) and Hero 7 (~4 GB) at once, and the empty state is the wrong surface
      to teach card mechanics. The copy is therefore camera-neutral and needs no mixed-folder
      variant. **Copy-only change — user-approved wording, no new control** (UI-changes protocol).
- [ ] Given an old persisted verification blob and a new `VerificationCheck.Kind` case, when
      decoded, then decoding must not fail — `Kind` has **no** unknown-case fallback today
      (unlike `VerificationStatus`), so adding the gpmd case needs a tolerant decode path.

---

## Technical Considerations

### ⚠️ THE persistence hazard — `DJIClip` is synthesized-Codable (highest-risk item)
`DJIClip` (`Models/DJIClip.swift:16`) has **no custom `init(from:)`/`CodingKeys`** — fully
synthesized. The queue persists `[ConversionJob]` (owning `[DJIClip]`) to
`~/Library/Application Support/Conjoyn/queue.json` (decode `Services/QueueManager.swift:256`,
encode `:234`). Adding a **non-Optional stored property — even with a default value** — makes
decode of a 1.0.4-era blob throw `keyNotFound`, and the catch at `QueueManager.swift:301` then
**drops the entire persisted queue** of a shipped user. Any new per-clip field (camera family,
gpmd index, …) must be either `Optional`, or `DJIClip` gets a hand-written
`init(from:)`/`CodingKeys` using `decodeIfPresent` (precedent:
`Models/ConversionJob.swift:51-85`, JobStatus). No existing test decodes an older-shaped
`DJIClip` blob (the only forward-compat test is `SourceTargetModelsTests.swift:160`) — **write
that fixture test first**, before touching the model.

**Decision Q5 (2026-08-07): hand-write `init(from:)` + `CodingKeys` on `DJIClip` now**, using
`decodeIfPresent` for every field that a 1.0.4 blob may lack, following the
`ConversionJob`/`JobStatus` precedent. Not the Optional-only shortcut: Optional-only leaves the
hazard armed for the next contributor who adds a non-Optional field, and the explicit
`CodingKeys` is exactly the mapping layer the deferred DJI→neutral rename will need, so the work
is done once. Order is fixed: **checked-in 1.0.4-shaped `queue.json` fixture test first (must
pass against today's model), then the custom decoder, then any new field.**

### Integration points (verified file:line)
- **Parser** — `Services/DJIFilenameParser.swift:98` (`parse`), timestamped regex `:87-90`,
  legacy regex `:91-94`, the optional rename-prefix fragment `:85` (reuse for GoPro),
  `kind(forExtension:)` `:147-154`. Only 4 call sites total. The GoPro regex **must stay
  tail-anchored** — `WatchFolderCoordinator.swift:496` hardcodes the output name
  `"\(stem)\(suffix)_joined.mp4"`, and the anchor is the only thing stopping
  `GX016338_joined.mp4` from re-parsing as source. Load-bearing.
- **Discovery/grouping** — `Services/DJIFolderReader.swift:50` (`read`), parse gate `:68`,
  hardcoded `["mp4","mov","srt","lrf"]` skip filter `:71` (GoPro adds no extensions this pass;
  `.LRV`/`.THM` stay skipped — see Out of Scope), `resolveMediaFolders` `:284`,
  `containsDJIMedia` `:313/:319` (must learn GoPro names or GoPro-only folders resolve empty),
  `groupMetas` `:174`, `continues()` `:208`. DJI-specific assumptions inside `continues()` that
  the GoPro path must override: split-cap gate `:215` (DJI `capSizeFraction` 0.93 `:154`,
  `capSizeFloorBytes` 3 GB `:157` — per decision Q3 the GoPro path **skips this gate entirely**
  instead of substituting a GoPro constant; chapter numbering already carries the signal, and the
  relative near-equal-then-smaller rule serves the complete-set gate), variant-suffix guard
  `:217` (no GoPro equivalent), `next.index == prev.index+1` `:227` (maps to consecutive
  chapters), stream-param match `:229-232` (keep), and the **wall-clock `gap > 0` rule
  `:235-237` which GoPro violates by design** (identical creation_time; use timecode
  continuity instead, `continuationSlackSeconds` `:161` re-tuned or bypassed).
  `read()` callers: `ConversionViewModel.swift:326`, `WatchFolderCoordinator.swift:120`,
  `WatchFolderManager.swift:193`. Already camera-agnostic, no change:
  `CompleteSetGate.swift`, `FileStabilityGate.swift`, `WatchFolderReconciler.swift`.
- **Join args** — `Services/FFmpegWrapper+Conversion.swift:58-62` (`buildMergeArguments`), the
  `-map -0:d` line `:69` (**this is what drops gpmd** — finding E), `JoinMetadata` `:19-30`
  (not Codable/Sendable), sole production caller `mergeClips` `:149-153`, invoked from
  `QueueManager+Processing.swift:270` with metadata from `resolveJoinMetadata` `:411-463`.
- **gpmd index resolution** — `Services/StreamParameterGuard.swift:219` (`probeStreamInfo`)
  already runs `ffprobe -show_streams` (`:226`) and **discards** the full stream list; extend
  `SegmentStreamInfo` (`:71`) to retain the data stream's index + `codec_tag_string`. Small.
- **Verifier** — `Services/SourceTargetVerifier.swift:141-220` (`runTier0And1`); the
  per-stream extension point is the tuple array `:158-162`
  (`var streams: [(select: String, label: String)]`), threaded to `-select_streams` at
  `:318/:341/:370`; Tier-2 hashes streams separately at `:246` (second edit needed). `hasAudio`
  at `QueueManager+Verification.swift:265`. `VerificationCheck.Kind`
  (`Models/SourceTargetModels.swift:51-59`) gains a case — see the decode-fallback error state.
- **Timecode** — GoPro clips **always** carry tmcd (71/71), unlike DJI
  (`RecordingIntegrity.swift:14` skips the reader for that reason). Caveat: AVFoundation's
  `SourceTimecodeReader` (`Services/SourceTimecodeReader.swift:22`, `read(from:)` `:97`)
  **chokes on muxed tmcd** ("sample buffer lacks a format description" —
  `SourceTargetVerifier.swift:391`); use the verifier's ffprobe route
  (`readOutputTimecode` `:419-435`, `stream_tags=timecode`) for GoPro TC reads. The tmcd
  `avg_frame_rate` equals video `r_frame_rate` on all 71 files, so the TC frame field counts
  at video fps (measured).
- **UI copy** — `ConversionViewModel.swift:343` ("No video segments found"), `:346-347` ("No
  DJI recordings found … didn't match a DJI filename"), `RecordingsList.swift:94-96` (skipped/
  unreadable counters), `:501-502` (empty-state "split at the 4 GB card limit" — **wrong for
  GoPro**, see Open Questions), `:266` ("+ N telemetry .SRT" — GoPro has none).

### Testing strategy (the gpmd constraint)
The bundled **LGPL ffmpeg cannot encode h264/hevc** (`JoinGuardIntegrationTests.swift:20-22`)
and **nothing in the suite synthesizes a gpmd track**. Plan: (1) parser tests = pure string I/O
like `DJIFilenameParserTests` (16 existing); (2) grouping tests = file-free in-memory
`SegmentMeta` fixtures **transcribed from this corpus** (factory pattern:
`DJIFolderGroupingTests.swift:32-36` — all the numbers in this spec are the fixture data);
(3) gpmd join/verify tests = check in **tiny real seam-slice fixtures** cut from the corpus
(the measured 25 s slices prove the technique; re-cut at ~1–2 s / a few MB) — ffmpeg can
`-c copy` remux gpmd even though it can't encode video, so the real join path runs end-to-end
against them, `XCTSkip` when tools absent (pattern: `JoinGuardIntegrationTests.swift:36`);
(4) the 1.0.4 `queue.json` decode fixture (see hazard).

### Performance / Security
- Join stays stream-copy, I/O-bound; gpmd adds ~430 KB/25 s — negligible.
- No new trust boundaries; same bundled-tool invocation and sandbox posture as DJI.

---

## Out of Scope

Explicitly excluded from this pass:
- **Legacy `GOPR`/`GP0` naming** (Hero 5 and earlier). GX/GH covers Hero 6–13 including the
  user's Hero 11 and GoPro 7.
- **The 6,328 JPGs** sitting next to the corpus / photo preservation generally — separate
  backlog item, already scoped in `decisions.md` (2026-07-14).
- **`.LRV`/`.THM` sidecars.** Note `.LRV` uses a **different prefix** — `GL010123.LRV` for
  `GX010123.MP4` — so it will *not* pair by stem the way DJI's `.LRF` does; supporting it means
  a cross-prefix pairing rule, deliberately deferred.
- **The DJI→neutral type rename** (`DJIClip` et al.). Locked decision: family layer now,
  rename later, separately.
- **Osmo Action validation** — hardware in hand, zero footage probed; own pass.
- **GPMF telemetry parsing or re-timing** — we preserve the track **verbatim**; we do not
  interpret, re-base, or extract it (no sidecar export either — locked decision).
- **SRT stitching for GoPro** — GoPro has no `.SRT`; telemetry rides in-container.

---

## Open Questions

All six resolved **2026-08-07** — Q1 and Q6 by measurement, Q2–Q5 by user decision.

| # | Question | Status | Answer |
|---|----------|--------|--------|
| Q1 | Is verbatim gpmd concatenation **semantically** correct for GPMF consumers, not merely byte-exact? Each payload might carry internal timestamps a consumer re-bases per chapter. | **Resolved — measured** | **Yes.** The joined seam fixture's gpmd stream was walked as raw GPMF KLV (parser written for this: `01_Project/scripts/gpmf-dump.py`, finding G): all **50 `DEVC` payloads parse clean, zero desync**, including the one at the seam byte 219,220. Decisively, **`STMP` is recording-relative, not chapter-relative** — chapter 02's first payload reads 1,536.014 s, continuing chapter 01's clock rather than resetting; the seam step (0.9985 s) equals every other step. `GPSU` UTC is continuous across the boundary, and container packet PTS run 0.003→49.003 s with every delta exactly 1.000 s. Both time sources a consumer can use stay coherent. A named third-party tool (gpmf-parser / Telemetry Extractor) opening the file is still not *formally* run, but the only two failure modes it could expose — framing desync and per-chapter time rebase — are the ones ruled out. **Closed.** |
| Q2 | Does GH (AVC) footage behave identically? Zero GH samples held. | **Resolved — decision** | Ship **GX-validated**; parse GH by symmetry (everything downstream is codec-agnostic). Close the bulk of the risk with **one ~30 s H.264 clip** on the Hero 11 (compression set to H.264) to confirm the GH name, `avc1|mp4a|tmcd|gpmd` layout, gpmd presence and TC↔creation_time relation. No 11 GB chaptered GH capture; *chapter-level* GH behaviour is taken as symmetric with GX. See the footage-gated pre-req under Parsing. |
| Q3 | Is the ~10.7–10.85 GiB cap band stable enough to gate on? | **Resolved — decision** | **No — use no absolute constant.** Grouping rests on chapter numbering + stream params + timecode; the complete-set "expect continuation" signal becomes **relative** (non-final chapters near-equal, final smaller) plus the quiet window. Evidence against a constant: the cap is not a fixed byte count (6349 @25 fps → 10.8471 GiB vs ~10.718 GiB at 100 fps), it is calibrated on one camera+firmware, and the user's own **Hero 7 splits far lower (~4 GB)** — a Hero 11 constant would misjudge it. The relative rule must reproduce the absolute rule's verdict on all 6 corpus groups (acceptance criterion added). |
| Q4 | Should the "split at the 4 GB card limit" empty-state copy become camera-aware? | **Resolved — decision** | **Neither — drop the number.** Camera-neutral wording, e.g. *"Long recordings get split into several files on the card. Conjoyn finds those pieces and joins them back into one."* No figure is true across DJI (~4 GB), Hero 11 (~10.7 GiB) and Hero 7 (~4 GB) simultaneously, and a neutral sentence needs no mixed-folder variant. Copy-only; wording approved by the user. |
| Q5 | `DJIClip` forward-compat: Optional-only fields, or hand-written `init(from:)`/`CodingKeys`? | **Resolved — decision** | **Hand-write `init(from:)` + `CodingKeys` now**, `decodeIfPresent` throughout (precedent `ConversionJob`/`JobStatus`). Optional-only leaves the queue-wipe hazard armed for whoever next adds a non-Optional field, and the explicit keys are the mapping layer the deferred DJI→neutral rename needs anyway. Fixed order: **1.0.4-shaped `queue.json` fixture test → custom decoder → new fields.** |
| Q6 | Does the 2026-07 folder's extra file imply cross-month chapter splits? | **Resolved — premise gone** | **There is no 2026-07 folder** — the user deleted it and its single file on 2026-08-07 (nothing of value in it). The whole H11 tree now contains MP4s under `PHOTOS H11 - 2026-08` only (verified by `find`), so the question is moot either way. Co-location is guaranteed by construction: all chapters share `creation_time`, so the rename workflow stamps them with an identical prefix and files them together. A hand-moved chapter still degrades only to the incomplete-set flag, never a wrong join. |

---

## Related

- **Sibling spec:** `specs/dji-auto-stitcher.md` — the v1 engine this extends.
- **Decisions:** `docs/decisions.md` — photo-preservation scope (2026-07-14); log the locked
  choices from this spec (family layer over rename; gpmd preserved-not-extracted; GX/GH only)
  on approval.
- **State:** `docs/PROJECT_STATE.md` — "More camera families = NEXT FOCUS" backlog entry;
  2026-08-06 renamed-footage parser fix (the rename-prefix rule GoPro reuses).
- **Ground truth:** session scratchpad `gopro/grouping-truth.md` + `corpus.csv` (2026-08-06/07
  probes of `/Volumes/V26/…/PHOTOS H11 - 2026-08`); join experiments A–F summarized inline
  above.
