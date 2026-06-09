# Project State

> **Size limit: <100 lines.** This is a digest, not an archive. Details go in session logs.

## Identity
- **Project:** DJIjoiner
- **One-liner:** macOS app that merges DJI media with its metadata — combining footage with telemetry/SRT/flight-log data and/or muxing audio+video tracks.
- **Tags:** macOS, video, DJI, metadata, ffmpeg
- **Started:** 2026-06-07

## Current Position
- **Funnel:** build (Wave 0+1 slice · Wave 2 2.1/2.5/2.6/2.8 · Wave 3.1+3.2 · Wave 1.5 ·
  **Wave 1.2/1.3 model layer** done)
- **Phase:** implementation — Wave 2 (footage-free) + Wave 3 SRT + DJIClip model layer + **1.8 SpeedTracker** done;
  **Wave 1 queue ports continuing** (1.9 VerificationService next)
- **1.8 SpeedTracker — landed this session:** ported from P2toMXF with three DJI adaptations —
  drop `processingMode` (single join mode), sum `DJIClip.durationInSeconds` directly (exact `CMTime`,
  no edit-unit/frame-rate math), and an **injectable storage dir** (`init(storageDirectory:)`) so tests
  hit a temp dir, not the real `~/Library/Application Support/DJIjoiner`. App-support folder renamed
  `P2toMXF`→`DJIjoiner`. Persistence made **synchronous** (tiny file, job-boundary writes — removes the
  detached-write lifetime race). **16 new tests** (estimate tiers, 50-record cap, slow-speed, on-disk
  round-trip). 121 tests pass.
- **Model layer (1.2/1.3) — landed this session (`fa468af`):** `DJIClip` (Int64+Int32 duration
  backing → exact `CMTime`; embeds `SegmentStreamInfo?`; `from(parsed:)` factory), `ConversionSettings`
  (lean + `OutputContainer{.mp4,.mov}`), `RecordGroup` (transient), `DJIFolder`, `ConversionJob`+
  `JobStatus` (one job = one record group), `VerificationModels`, `ProgressModels` estimation types.
  `StreamParameterGuard` param structs made `Hashable, Codable, Sendable` (additive). **14 new tests**,
  keystone full-`ConversionJob` Codable round-trip green.
- **Focus:** Engine front-end + SRT parse/stitch landed, all unit-testable without footage:
  - **3.1 `SRTParser`** — tolerant structure-only SubRip parser for all 3 DJI layouts (modern
    bracketed, FrameCnt/DiffTime, legacy `<font>`/`GPS()`/`HOME()`). Index + start/end ms +
    **verbatim payload** + embedded wall-clock; tolerates BOM/CRLF/CR/dot-or-comma ms; skips
    malformed blocks. Canonical serializer for 3.2 round-trips. **20 tests.**
  - **3.2 `SRTStitcher`** — splices per-segment sidecars into one continuous track; offset =
    Σ **decoded `format=duration`** of preceding segments (NOT cue math), global renumber,
    missing sidecar still advances offset. Pure core + `FFmpegWrapper.probeDurationMilliseconds`/
    `stitchSRT((video,srt?))`. **11 tests** incl. skippable real-ffprobe end-to-end alignment.
  - **1.5 `TempDirectoryManager` + `DiskSpace`** — model-agnostic queue infra, ported first.
    DiskSpace verbatim; TempDir only renamed its defaults key. **10 tests.**
  - **2.1 `DJIFilenameParser`** — both naming schemes → index/timestamp/variant-suffix/media-kind.
  - **2.5 `FFmpegWrapper+Conversion`** — pure concat-join builders + thin `mergeClips`.
  - **2.6 `StreamParameterGuard`** — ffprobe each segment; refuse `-c copy` on codec/res/pix_fmt/
    fps/timebase/audio mismatch with a field-level reason; wired into `mergeClips`
    (`verifyParameters`, default on).
  - **2.8 `QuickTimeAtomWriter`** — re-mux-free, size-preserving mvhd/tkhd/mdhd date patch
    (1904 epoch, v0/v1) + read path. **Deferred:** size-changing `Keys` creationdate atom
    (needs stco/co64 offset fixups) → flagged for real-footage validation (Wave 6).
- **Status:** **121 tests pass** (105 prior + 16 new SpeedTracker tests; incl. skippable ffmpeg/ffprobe
  integration tests that ran). Remaining Wave 2: **2.2/2.3/2.4 (metadata reader, folder reader,
  grouping) blocked on real DJI footage**; 2.7 TS-remux fallback needs a stubborn set. Wave 3:
  **3.3 wire SRT into join pipeline** is the last SRT task — needs the join/queue path. **Wave 1
  queue ports in progress** (1.5 + model layer + 1.8 SpeedTracker done;
  Verification/Thumbnail/QueueManager next).
- **Last updated:** 2026-06-09 (1.8 SpeedTracker landed)

## Funnel Progress (Ralph-style)

| Funnel | Status | Gate |
|--------|--------|------|
| **Define** | done | Spec written, edge cases enumerated, decisions logged |
| **Plan** | done | IMPLEMENTATION_PLAN.md: waves, atomic tasks, backpressure |
| **Build** | ready | Start Wave 0 / vertical slice |

## Phase Progress
```
[##############......] 70% - Wave 2 footage-free + Wave 3.1/3.2 SRT + Wave 1.5/model layer/1.8 SpeedTracker done
```

| Phase | Status | Tasks |
|-------|--------|-------|
| Discovery | done | ✓ interview, spec, decisions |
| Planning | done | ✓ IMPLEMENTATION_PLAN.md (7 waves) |
| Implementation | **in progress** | ✓ Wave 0 (scaffold+toolchain) · Wave 1 next (port) |
| Polish | pending | — |

## Readiness
- Directions installed in `docs/`
- Spec: `specs/dji-auto-stitcher.md`
- Reference codebase cloned: `_reference/P2toMXF/` (Swift 6/SwiftUI, port source)
- Tech stack: macOS 14+, SwiftUI/Swift 6, Apple Silicon, AVFoundation + bundled FFmpeg +
  exiftool; direct distribution + notarized (sandbox off, hardened runtime on)
- No app code yet (`01_Project/` empty)

## Blockers
- _none_

## Flags (load when relevant)
- `22_macos-platform.md` — sandbox/notarization/bookmarks/FSEvents
- `20_swiftui-gotchas.md` — GUI build
- `21_coordinate-systems.md` — not expected (no image cropping)
- `32_git-workflow.md` — git init pending

## Risks
- **SRT offset-correction stitching** = highest-uncertainty v1 item ("known unsolved pain
  point" per brief). Scope-creep flagged but user-chosen.

## Next Action
- **Now ~all footage-free Wave 2 work is done (2.1/2.5/2.6/2.8).** Remaining engine tasks need
  real DJI input or a stubborn set:
  - **2.2 `DJIMetadataReader`, 2.3 `DJIFolderReader`, 2.4 grouping** — **blocked on real footage**
    (legacy + timestamped split sets with `.SRT`/`.LRF`, plus one multi-camera set).
  - **2.7 TS-remux fallback** — needs a set that fails the direct concat (`Non-monotonous DTS`).
- **In progress — Wave 1 queue ports (unblocked).** Model layer (1.2/1.3) + **1.8 SpeedTracker
  done** (121 tests). Remaining order: **1.9 VerificationService → 1.10 ThumbnailManager →
  1.7 QueueManager** (core + Operations + persistence; Processing/Verification adapts to drive the
  ported `mergeClips`, not BMX). These unblock 3.3 wire-into-join + the whole queue path.
- **Next up — 1.9 VerificationService:** port from P2toMXF (`Services/VerificationService.swift`);
  the `VerificationModels` types (`VerificationStatus`/`VerificationResult`/`VerificationMode`) already
  exist. Quick (container + head/tail decode) + Full (full decode via VideoToolbox) modes over the
  joined MP4/MOV; cancellation + progress. Then 1.10 ThumbnailManager, then 1.7 QueueManager.
- **Design calls now locked in code** (see `docs/sessions/2026-06-08.md`): `Int64`+`Int32` duration
  backing → exact `CMTime`; `SegmentStreamInfo?` embedded on `DJIClip`; lean `ConversionSettings`;
  one `ConversionJob` = one record-group.
- Vertical slice can join end-to-end once 2.2/2.3 land; `mergeClips` (2.5) + guard (2.6) ready.
- **2.8 follow-up:** add the Apple `Keys` `com.apple.quicktime.creationdate` atom (size-changing,
  offset fixups) — defer until real footage so it's validated in Finder/QuickTime Inspector.
- **Wave 0 carryover:** interim FFmpeg is **GPL** (osxexperts 8.1) — must swap to LGPL static
  before release (task 6.1). FFmpeg binaries are gitignored; run `01_Project/scripts/fetch-ffmpeg.sh`.
- **Build gotcha:** incremental builds skip re-signing the app wrapper, leaving a stale seal
  when the post-build phase adds helpers → always **clean build** (already house rule).
- **Blocking input (Wave 2+ validation):** real DJI split-recording test sets (legacy +
  timestamped naming, with `.SRT`/`.LRF`), plus one multi-camera set for the variant guard.
