# Tasks Archive

Completed sprint tasks, newest first. Execution detail lives in the plan the task came from;
rationale lives in `decisions.md`. Sprint checkboxes are in `TASKS.md`.

**Total archived:** 10 · **Last updated:** 2026-08-07

## Completed

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
