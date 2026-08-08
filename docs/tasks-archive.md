# Tasks Archive

Completed sprint tasks, newest first. Execution detail lives in the plan the task came from;
rationale lives in `decisions.md`. Sprint checkboxes are in `TASKS.md`.

**Total archived:** 14 · **Last updated:** 2026-08-08

## Completed

### Wave G3 — grouping (`IMPLEMENTATION_PLAN-gopro.md`)

- [x] **G3.1** `SegmentMeta` gains `family`/`recordingNumber`/`startTimecodeSeconds`; bucket key
      becomes `family|variantSuffix|recordingNumber` — a 1:1 relabel for DJI (`recordingNumber`
      always nil there), so DJI verdicts are unchanged. Fields are `var` with defaults, not `let`:
      Swift drops a `let`-with-inline-default from the synthesized memberwise init entirely.
      (2026-08-08)
- [x] **G3.2** `continues()` dispatches on family. `continuesDJI` = the shipped body, verbatim.
      `continuesGoPro` chains on same recording number + consecutive chapter + stream-param
      compatibility + timecode continuity within 1 ms — no size-cap gate, no wall-clock gate,
      because GoPro's cap isn't a constant and 6338's two chapters share a `creation_time`.
      (2026-08-08)
- [x] **G3.3** All 71 measured corpus files pinned as fixtures: 6 multi-chapter groups + 51 singles;
      6347 = one group of 5 (3195.780 s / 47,889,205,619 B); 6338 chains despite identical
      `creation_time`; `GX016350` never merges into 6349; a withheld chapter 02 is never bridged.
      Transcribed by script, re-verified field-by-field (781 comparisons, 0 mismatches). (2026-08-08)
- [x] **G3.4** `RecordGroup.completeness` (non-persisted — `RecordGroup` is never `Codable`)
      surfaced through the **existing** `IntegrityChip` via two new `Flag.Kind` cases;
      `RecordingsList.swift` needed no edit. **Warns but does not block the join** — a user decision
      overturning the spec's "not joined"; see `decisions.md` (2026-08-08). Completeness is decided
      per bucket, not per run. (2026-08-08)

### Wave G4 — join with telemetry (`IMPLEMENTATION_PLAN-gopro.md`)

- [x] **G4.1** `buildMergeArguments` learns a gpmd index — `nil` reproduces the 1.0.4 DJI vector
      byte-for-byte; non-`nil` emits `-map 0:v:0 -map 0:a? -map 0:<i> -c copy -copy_unknown`
      (2026-08-07)
- [x] **G4.2** `dataStreamPolicy` on `mergeClips` — resolves the index from segment 1 at join time
      (never from persisted state) and refuses a presence mismatch before ffmpeg runs, naming the
      segment; `.drop` does no extra probing at all (2026-08-07)
- [x] **G4.3** Real seam-slice fixtures + end-to-end join test through the production path — gpmd,
      video and audio all byte-exact across a genuine chapter boundary; verified by falsification
      (2026-08-07)

### Wave G2 — probe extension (`IMPLEMENTATION_PLAN-gopro.md`)

- [x] **G2.1** Retain gpmd stream index, codec tag and start timecode from ffprobe — three Optionals
      on `SegmentStreamInfo`, selected by `codec_tag_string`; `check(_:)` untouched; `-show_format`
      added to make the specified format-tags fallback reachable (2026-08-07)

### Wave G1 — GoPro filename parsing (`IMPLEMENTATION_PLAN-gopro.md`)

- [x] **G1.1** `CameraFamily` + tail-anchored GoPro `GX`/`GH` regex in `DJIFilenameParser` (2026-08-07)
- [x] **G1.2** Parser acceptance tests, incl. all 71 corpus filenames (2026-08-07)
- [x] **G1.3** Thread family + `recordingNumber` through `DJIClip` and folder discovery — folder scan
      needed no code change; added the encoder-completeness guard (2026-08-07)

### Wave G0 — persistence safety net (`IMPLEMENTATION_PLAN-gopro.md`)

- [x] **G0.1** Check in a 1.0.4-shaped `queue.json` fixture + decode test (must pass against today's model) (2026-08-07)
- [x] **G0.2** Hand-write `DJIClip` `CodingKeys` + `init(from:)` with `decodeIfPresent` (2026-08-07)
- [x] **G0.3** Tolerant decode for `VerificationCheck.Kind` (unknown-case fallback) (2026-08-07)
