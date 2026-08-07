# Conjoyn — GoPro Camera-Family Implementation Plan

> Generated **2026-08-07** from `specs/gopro-camera-family.md` (all 6 open questions resolved the
> same day) plus a gap analysis of the shipped 1.0.4 engine. Sibling of the v1 plan in
> `IMPLEMENTATION_PLAN.md` (waves 0–6, closed). Plans are disposable — regenerate if the
> trajectory diverges rather than patching this file.

## Goal
Conjoyn recognises, groups and losslessly joins **GoPro GX/GH chaptered recordings** with the
in-container **`gpmd` telemetry track preserved verbatim** — while the DJI path stays
byte-identical to 1.0.4.

## Strategy
Add a **camera-family layer around** the existing `DJI*` types (locked decision — the neutral
rename is a separate, later change). Every GoPro-specific rule is a *branch* inside a shared
function, never a parallel pipeline: one parser, one grouping core, one arg builder, one verifier.
The DJI branch keeps its exact current code path so the 495-test suite passes unchanged.

**Order is not negotiable at the start:** the `DJIClip` Codable hazard is armed *today*. Wave G0
lands the queue-decode safety net **before any model gains a field**, per spec decision Q5.

## Backpressure (every task)
- **Compiles:** `xcodebuild -project 01_Project/Conjoyn.xcodeproj -scheme Conjoyn -configuration Debug -destination 'platform=macOS,arch=arm64' build`
- **Tests:** `xcodebuild test …` — full suite green, **≥ 495 + the task's new tests, 0 fail**.
  Per-task iteration may filter with `-only-testing:ConjoynTests/<Class>`, but a task is not done
  until the **full** suite is green.
- Never mark a task done on "build succeeded" alone.

## Assets needed
| Asset | Needed by | Status |
|---|---|---|
| Hero 11 corpus on `/Volumes/V26/…/PHOTOS H11 - 2026-08` | G4.3 fixture cut, G8.2 | **On hand** (70 files; ch01 of 6338 gone — cut fixtures from an **intact** group, e.g. 6347) |
| One ~30 s **H.264** Hero 11 clip (→ `GH…`) | G8.1 | **Owed — user capture** (camera setting: video compression → H.264) |
| Osmo Action 1 / GoPro 7 footage | *not this pass* | out of scope |

---

## Locked design decisions (made during this planning pass)

These resolve ambiguities the spec left to implementation. **Recorded in `docs/decisions.md`
(2026-08-07, "GoPro plan: five implementation-level design calls")** — they outlive this plan file.

1. **`index` carries the *chapter* for GoPro; a new `recordingNumber` carries the file number.**
   `DJIClip.index` is consumed as "position of this segment within its recording" by
   `WatchFolderCoordinator.swift:402` (`max(by: index)` = the group's last segment) and by
   `continues()`'s `next.index == prev.index + 1`. Mapping chapter→`index` keeps both correct for
   free. The 4-digit file number becomes `recordingNumber` (GoPro only, `nil` for DJI) and is the
   **recording identity** — it drives bucketing, which is what makes `GX016350` never merge into
   recording 6349. Known, accepted cost: `index` is no longer unique across GoPro recordings, so
   the cross-group sort tie-break (`ConversionViewModel.swift:204/247`) degrades to arbitrary
   order for two recordings sharing a `creationDate` — cosmetic, and the ledger fingerprint is
   unaffected (it includes `stem`, `ProcessedGroupLedger.swift:92`).
2. **Bucketing key becomes composite.** `groupMetas` currently buckets on
   `variantSuffix ?? ""` — every GoPro clip has `nil`, so all GoPro recordings would land in one
   bucket alongside legacy DJI clips. New key: `family | variantSuffix | recordingNumber`.
3. **The gpmd stream index is resolved from *segment 1 at join time*, never from persisted state.**
   The concat demuxer presents the first file's stream layout, so the `-map 0:<i>` index must come
   from that file, probed in the same run (finding D: 3 in a camera original, 2 after a remux).
   `streamInfo.dataStreamIndex` persisted on the clip is a *grouping/verification* signal only.
4. **Never select the telemetry stream as `d:0`.** ffprobe reports `tmcd` as `codec_type=data`
   too, so `-select_streams d:0` can resolve to the timecode track. Everything that touches gpmd
   selects by **resolved absolute index** with `codec_tag_string == "gpmd"` as the predicate.
5. **Missing timecode on either side blocks a GoPro chain.** TC continuity is the GoPro
   continuity signal; without it we cannot confirm, so we do not chain (safe split into singles,
   never a wrong join). All 71 corpus files carry `tmcd`, so this never fires in practice.

---

## Wave G0 — Persistence safety net (**CLOSED 2026-08-07**)

Serial. Nothing may add a field to `DJIClip` until G0.2 is merged. **All three tasks are done and
merged** — suite **512 / 0 fail** (495 → +17). The hazard was reproduced against the net before the
fix: a probe `var` on `DJIClip` failed all 10 G0.1 tests with `keyNotFound` at `[0].clips[0]`.
Rationale in `decisions.md` (2026-08-07, "Queue persistence"). **Standing rule for later waves:**
a new `DJIClip` field must be added to `CodingKeys` *and* decoded with `decodeIfPresent`; a red
`QueuePersistenceCompatTests` is stop-the-line, never a test to update.

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G0.1 | Check in a **1.0.4-shaped `queue.json` fixture** + decode test | `ConjoynTests/Fixtures/queue-1.0.4.json`, `ConjoynTests/QueuePersistenceCompatTests.swift` | Fixture is a real blob produced by shipped 1.0.4 (or a faithful hand-transcription of one) holding ≥2 jobs with ≥2 clips each. Test decodes `[ConversionJob]` with the **same decoder config as `QueueManager.loadQueue`** (`.iso8601`) and asserts job count, clip count, paths, durations, and `streamInfo` survive. **Must pass against today's unmodified model** — that is the point of writing it first. | new test green; suite 495+1 |
| G0.2 | Hand-write `DJIClip` `CodingKeys` + `init(from:)` | `Models/DJIClip.swift` | Explicit `CodingKeys` for all 13 stored properties; `decodeIfPresent` for every field a 1.0.4 blob may lack, with documented defaults; required fields (`id`, `videoFilePath`, `index`, `stem`, duration backing) still `decode`. Precedent: `ConversionJob.swift:51-85`. Encoder stays synthesized-compatible (round-trip test). G0.1's fixture still green **unchanged**. | G0.1 + a new round-trip encode→decode test |
| G0.3 | Tolerant decode for `VerificationCheck.Kind` | `Models/SourceTargetModels.swift:51-59` | `Kind` gains an unknown-case fallback (`init(from:)` mapping an unrecognised raw value to a benign case, mirroring `VerificationStatus`), so a future/foreign case can never throw and take the whole persisted blob with it. Test: a JSON blob with `"kind":"somethingNew"` decodes instead of throwing. | new test green |

---

## Wave G1 — Parsing (**CLOSED 2026-08-07**)

All three tasks done and merged (`faae069` + `83e878f`) — suite **525 / 0 fail** (512 → +13).
Folder scan needed **no code change**: `containsDJIMedia` only asks the parser about filenames and
`resolveMediaFolders` special-cases only `DCIM` as a container, so `DCIM/100GOPRO` resolved for
free — covered by a test rather than an invented fix.

**New standing rule (the encoder half of G0's).** `DJIClip.encode(to:)` is now hand-written, because
a non-Optional `family` under a synthesized encoder would write `"family":"dji"` into every DJI clip
and change the on-disk shape 1.0.4 wrote. That trades G0's `keyNotFound` hazard for its mirror: a
field added to `CodingKeys` and `init(from:)` but **forgotten in the encoder** is silently never
persisted and reloads as its default, with nothing red. Closed by making `CodingKeys` `CaseIterable`
and pinning the encoded key set against `allCases`
(`QueuePersistenceCompatTests.testEncoderWritesEveryCodingKeyForAFullyPopulatedClip`) — the guard was
verified by injecting a probe key and watching it fail, not assumed.

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G1.1 | `CameraFamily` + GoPro regex in the parser | `Services/DJIFilenameParser.swift` | New `enum CameraFamily { case dji, goPro }`. `Parsed` gains `family`, `recordingNumber: Int?`, keeps `index` (= chapter for GoPro, decision 1). New regex reusing the existing `optionalPrefix` fragment `:85` and **tail-anchored to `$`**: `^<prefix>?G[XH](\d{2})(\d{4})$`, case-insensitive. DJI regexes tried first, unchanged. `GOPR…`/`GP0…` deliberately do **not** match. | `DJIFilenameParserTests` + new cases |
| G1.2 | Parser acceptance tests | `ConjoynTests/DJIFilenameParserTests.swift` | Covers every Parsing criterion in the spec: `GX016338`→(GoPro, ch 1, rec 6338); the renamed archive form `H11--…--GX026338`→(ch 2, rec 6338); `GX016338_joined` **rejected**; `GH010123` accepted with GX-identical structure; `GOPR0123`/`GP010123` rejected; **all 71 corpus filenames** parse with correct (chapter, recordingNumber) and zero misclassification; existing 16 DJI cases unchanged. | full suite |
| G1.3 | Thread family through the clip model + folder scan | `Models/DJIClip.swift`, `Services/DJIFolderReader.swift` | `DJIClip` gains `family` + `recordingNumber` (Optional-decoding via G0.2's decoder; `family` defaults to `.dji` when absent so 1.0.4 blobs restore as DJI). `DJIClip.from(parsed:)` carries them. `containsDJIMedia` (`:313`) and `resolveMediaFolders` now see GoPro video, so a GoPro-only card/folder resolves instead of reading empty. The `["mp4","mov","srt","lrf"]` skip filter `:71` is **unchanged** (`.LRV`/`.THM` stay out of scope). | G0.1 fixture still green + a GoPro-folder resolve test in `DJIFolderResolveTests` |

---

## Wave G2 — Probe extension (parallel with G1; depends G0)

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G2.1 | Retain data-stream + timecode from ffprobe | `Services/StreamParameterGuard.swift` | `SegmentStreamInfo` gains **Optional** `dataStreamIndex: Int?`, `dataCodecTag: String?`, `startTimecode: String?` (all `decodeIfPresent`-safe under synthesized Codable). `parse(ffprobeJSON:)` picks the stream whose `codec_tag_string == "gpmd"` for the first two, and reads the timecode from the `tmcd` stream's `tags.timecode` (falling back to format tags). `FFProbeStreams.Stream` gains `index`, `codec_tag_string`, `tags`. **`check(_:)` is not extended** — the new fields must not change join-compatibility verdicts (a mixed-layout refusal is G4.2's job, with its own message). | new `StreamParameterGuardTests` cases over checked-in ffprobe JSON for a GoPro original (gpmd idx 3), a remux (gpmd idx 2), a no-audio GoPro file, and a DJI file (all three new fields `nil`) |

---

## Wave G3 — Grouping (depends G1, G2)

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G3.1 | Extend `SegmentMeta` + composite bucket key | `Services/DJIFolderReader.swift:133-146, 180` | `SegmentMeta` gains `family`, `recordingNumber: Int?`, `startTimecodeSeconds: Double?` (derived from `streamInfo.startTimecode` + `framesPerSecond`, using the existing `Timecode`/`TimecodeFormatter` types). Bucket key becomes `family|variantSuffix|recordingNumber` (decision 2). `group(_:)` adapter fills the new fields from `DJIClip`. DJI bucketing verdicts unchanged. | existing `DJIFolderGroupingTests` **pass unmodified** |
| G3.2 | Family-dispatched `continues()` | `Services/DJIFolderReader.swift:208-238` | `continues()` splits into `continuesDJI` (**current body verbatim** — steps 1–5 untouched) and `continuesGoPro`: (a) same `recordingNumber`; (b) `next.index == prev.index + 1` (consecutive chapters); (c) `StreamParameterGuard.check` compatible when both known; (d) **timecode continuity** — `tc(next) − tc(prev)` equals `prev.containerSeconds` within a new `timecodeContinuitySlackSeconds` tunable (default ≤ 1 frame; measured residual 1.1e-11 frames); (e) **no size-cap gate, no wall-clock `gap > 0` gate** (decision Q3/spec §Grouping). Missing TC on either side ⇒ no chain (decision 5). | new `DJIFolderGroupingTests` GoPro cases; all DJI cases green |
| G3.3 | Corpus grouping fixtures | `ConjoynTests/DJIFolderGroupingTests.swift` | In-memory `SegmentMeta` fixtures transcribed from the 71-file corpus (factory pattern `:32-36`). Asserts: **6 multi-chapter groups + 51 singles**; recording 6347 = one group of 5, ordered ch01–05, **3195.780 s / 47,889,205,619 bytes**; recording 6338 = one group of 2 totalling 1652.992 s **despite identical `creation_time`**; `GX016350` never merges into 6349; no cross-recording merge across the 25/50/100/200 fps and 3 resolutions present; a chapter-01+03 fixture produces **no** spanning group. | full suite |
| G3.4 | Incomplete-set flag | `Models/RecordGroup.swift`, `Services/DJIFolderReader.swift`, `Views/RecordingsList.swift` | `RecordGroup` gains a non-persisted `completeness` signal (`.complete` / `.missingFirstChapter` / `.chapterGap`). Set when a GoPro run starts above chapter 01, or when the bucket contains chapters the run could not bridge. Surfaced in the recordings list as a warning chip with plain-language text; such a group is **not joinable** (excluded from enqueue). DJI groups always `.complete` — behaviour unchanged. | new tests for both flag cases + a DJI-unchanged assertion |

> **UI note (G3.4):** the warning chip is a new visible element → follow
> `36_ui-changes-protocol.md`: locate the comparable existing chip in `RecordingsList.swift`
> (the integrity/`+ N telemetry .SRT` row, `:262-270`), state the exact insertion point, and get
> user confirmation **before** implementing. No new control, no new pane.

---

## Wave G4 — Join with telemetry (depends G2; G4.1 may start alongside G3)

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G4.1 | `buildMergeArguments` learns a gpmd index | `Services/FFmpegWrapper+Conversion.swift:58-84` | New parameter `gpmdStreamIndex: Int? = nil`. **`nil` ⇒ byte-identical arg vector to 1.0.4** (`-map -0:d` retained) — this is what protects DJI. Non-`nil` ⇒ `-map 0:v:0 -map 0:a? -map 0:<i> -c copy -copy_unknown` (finding F), `-map -0:d` dropped, tmcd left unmapped and regenerated by the existing `-timecode`. Function stays pure. | `FFmpegConcatArgsTests`: existing DJI assertions **unmodified**, plus exact-vector assertions for the GoPro shape |
| G4.2 | Resolve the index + refuse mixed layouts | `Services/FFmpegWrapper+Conversion.swift` (`mergeClips`), `Services/QueueManager+Processing.swift:270` | `mergeClips` gains a `dataStreamPolicy` (`.drop` default / `.preserveTelemetry`). Under `.preserveTelemetry` it probes **segment 1** at join time for the gpmd index (decision 3) and passes it to G4.1. If any segment's gpmd presence disagrees with segment 1's, the join is **refused** before ffmpeg runs, with a layout-mismatch message naming the segment (spec Error State). Caller derives the policy from the group's `family`. | unit test for the refusal path (synthetic `SegmentStreamInfo`s); DJI callers unchanged |
| G4.3 | Real seam-slice fixtures + end-to-end join test | `ConjoynTests/Fixtures/gopro-seam/`, `ConjoynTests/GoProJoinIntegrationTests.swift` | Two ~1 s `-c copy` slices cut from **adjacent chapters of an intact group** (6347 or 6345 — *not* 6338, whose ch01 left the volume), carrying video+audio+**gpmd**, **≤ 12 MB total** in git (pick the lowest-bitrate intact recording). Test drives the **production** path (`mergeClips` → real bundled ffmpeg/ffprobe), asserts: output has exactly one `codec_tag_string == "gpmd"` stream plus a regenerated tmcd; gpmd packet count and byte total equal the sum of the sources; video/audio parity likewise. `XCTSkip` when tools are absent (pattern `JoinGuardIntegrationTests.swift:36`). | test green with the real tools |

---

## Wave G5 — Verification (depends G4)

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G5.1 | gpmd in the Tier 0/1 per-stream pass | `Services/SourceTargetVerifier.swift:141-220`, `Models/SourceTargetModels.swift`, `Services/QueueManager+Verification.swift:261` | `SourceTargetInput` gains `sourceGpmdIndex: Int?` + `outputGpmdIndex: Int?` (resolved separately — the output's index differs from the source's). When present, the `streams` tuple array `:159-162` gains a telemetry entry **selected by absolute index, never `d:0`** (decision 4), so packet-count and packet-bytes parity run for gpmd exactly as for video/audio. New `VerificationCheck.Kind` case for the telemetry check (safe under G0.3). `makeVerifierInput` fills the new fields from the job's family/streamInfo. Audio still gated by `hasAudio` — a no-audio GoPro file runs video+gpmd only. **Found during G0 — fix here:** `QueuePanel.swift:660` renders flagged checks with `ForEach(flagged, id: \.kind)`, which assumes one check per kind. A per-stream telemetry check emitted alongside the existing per-stream `packetCount`/`packetBytes` breaks that (duplicate SwiftUI IDs), as would two `.unknown` checks. Give `VerificationCheck` a stable identity, or make the telemetry kinds distinct. | `SourceTargetVerifierTests` + the G4.3 fixtures (6338 reference: 1,536+117 = 1,653 packets) |
| G5.2 | gpmd in the Tier 2 hash | `Services/SourceTargetVerifier.swift:245-265` | `mapArgs` is built **twice** — source side uses the concat-presented index, output side the probed output index — so the hash compares like with like. Absent gpmd ⇒ current args verbatim. | Tier-2 test over the G4.3 fixtures |

---

## Wave G6 — Watch-folder complete-set rule (depends G3)

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G6.1 | Relative "expect continuation" signal | `Services/CompleteSetGate.swift`, `Services/WatchFolderReconciler.swift:73-79`, `Models/WatchFolderSettings.swift` | GoPro groups stop consulting the absolute `splitThreshold` (3.9 GB — wrong in both directions for a camera that caps near 10.7 GiB, decision Q3). New relative rule: a group's last chapter is **final** when it is meaningfully smaller than the near-equal non-final chapters of the same recording; with only one member and no reference, the quiet window alone decides. `isComplete` stays pure — the caller injects the comparison sizes. **DJI keeps the absolute rule unchanged.** | New `CompleteSetGateTests` cases; the corpus criterion: **the relative rule reproduces the absolute rule's verdict on all 6 corpus groups** (every non-final chapter "expect continuation", every final chapter closes the set); existing DJI gate tests green |

---

## Wave G7 — UI copy (parallel; depends G1 for naming only)

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G7.1 | Camera-neutral empty-state + scan copy | `Views/RecordingsList.swift:499-502`, `ConversionViewModel.swift:343-347` | The split-recording pitch **names no file size** (decision Q4) — user-approved wording: *"Long recordings get split into several files on the card. Conjoyn finds those pieces and joins them back into one."* "No DJI recordings found … didn't match a DJI filename" becomes camera-neutral so GoPro files are never misnamed as non-recordings, while keeping the 2026-08-06 *why-is-it-empty* improvement. The `+ N telemetry .SRT` line `:266` stays DJI-only (GoPro has no `.SRT`; its telemetry is in-container). **Copy-only — no new control.** | build + visual check; no test asserts these strings today, so confirm by eye |

---

## Wave G8 — Real-footage validation & close-out (final gate)

| # | Task | Target | Success criteria | Backpressure |
|---|---|---|---|---|
| G8.1 | GH (H.264) probe — *footage-gated* | — | User shoots **one ~30 s clip** with the Hero 11 set to H.264. Probe confirms: `GH…` filename, `avc1\|mp4a\|tmcd\|gpmd` layout, gpmd present, TC↔`creation_time` relation as measured on GX. Chapter-level GH behaviour is then taken as symmetric with GX (decision Q2). | ffprobe output recorded in the session log |
| G8.2 | Real full join of a GoPro group | — | An **intact multi-chapter recording** from the corpus joins end-to-end through the app: correct grouping, lossless `-c copy`, gpmd present and packet-exact in the output, `creation_time` + regenerated tmcd correct, originals untouched, verification seal green. User eyeballs the result. | manual, on real footage |
| G8.3 | Suite + docs | `docs/decisions.md`, `docs/PROJECT_STATE.md`, `docs/sessions/`, `specs/gopro-camera-family.md` | Full suite green (≥ 495 + all new tests, 0 fail). `decisions.md` records the 5 locked decisions above plus the spec's own (family layer over rename; gpmd preserved-not-extracted; GX/GH only; no absolute split constant). Spec status Draft → Implemented. PROJECT_STATE `Now`/`Recent` updated. Session log written via `/log`. | `xcodebuild test` all green |

---

## Dependency graph

```
G0 (persistence)  ─┬─► G1 (parse) ─┬─► G3 (group) ─┬─► G3.4 (incomplete flag)
                   │               │               └─► G6 (watch-folder gate)
                   └─► G2 (probe) ─┴─► G4 (join) ──────► G5 (verify)
                                   
G7 (copy) — independent after G1        G8 — final gate, needs all of the above
```

Parallelisable: **G1 ∥ G2** after G0; **G4 ∥ G3** after G2; **G7** any time after G1.
Serial spine: **G0 → G2 → G4 → G5**.

## Risk register
- **Queue wipe on update (highest).** A non-Optional field on `DJIClip` throws `keyNotFound` at
  `QueueManager.swift:256`, and the catch at `:301` silently discards a shipped user's **entire**
  queue. Mitigated by G0 landing first and by G0.1's fixture staying green through every later wave
  — treat a red G0.1 as a stop-the-line failure, not a test to update.
- **`-map 0:<i>` against the concat demuxer.** The index is positional into the first file's
  layout; nothing but G4.3's real-tool test proves the vector actually works. Do not ship G4 on
  unit tests alone.
- **`d:0` selecting tmcd instead of gpmd.** Silent — it would produce a *passing* telemetry check
  that verified the timecode track. Guarded by decision 4 and asserted in G5.1's fixture test.
- **DJI regression.** Every wave has "existing tests pass unmodified" as an explicit criterion; the
  `nil`-index default in G4.1 is the structural guarantee. If a DJI test needs editing to go green,
  the change is wrong.
- **Fixture size in git.** G4.3 caps both slices at ~12 MB total; if the lowest-bitrate intact
  recording still overshoots, shorten the slices before reaching for LFS.
- **GH by symmetry.** Chapter-level GH behaviour is inferred, not measured (accepted, decision Q2).
  A GH chaptered recording appearing later is the first thing to re-test.

## Sequencing note
Recommended thin vertical slice: **G0 → G1.1/G1.2 → G2.1 → G4.1/G4.3** — i.e. prove a real GoPro
seam joins with telemetry intact *before* building grouping, flags, gate and copy on top. That
retires the two highest technical risks (the arg vector and the index resolution) at minimum cost.

---
*Next: `/execute` to run Wave G0, or start the vertical slice above. Update `docs/PROJECT_STATE.md` as waves land.*
