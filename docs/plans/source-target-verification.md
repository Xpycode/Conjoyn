# Source↔Target Verification

## Context

After Conjoyn joins N split DJI MP4 segments into one file (ffmpeg concat demuxer, `-c copy`,
lossless; mjpeg-preview + DATA tracks dropped; `creation_time`+`tmcd` stamped; `+faststart`), there
is currently **no check that the output actually matches the sources**. The verification code already
ported from Penumbra/P2toMXF (`VerificationService`, `QueueManager+Verification`) does something
*different and weaker*: a **decode-only** check ("does the output decode without errors, frame count
within 5% of an estimate") that never looks at the source clips — so it can't catch a dropped, wrong,
or truncated segment if the broken result still happens to decode. It also has **zero callers**.

This change builds **true source↔target verification**, exploiting the fact that the join is lossless:
the output's kept streams should be *byte-identical* to the concatenation of the sources (already
proven manually once: `source v:0 MD5 == output v:0 MD5`). User-confirmed scope:

1. **True source↔target comparison** (not the decode-only check).
2. **Auto + manual** — a fast check runs automatically after every join; the user can manually run a
   deeper byte-exact check on any completed row.
3. **Fast default + opt-in hash** — cheap container-index comparison by default; byte-exact packet-MD5
   hash on demand or auto-escalated when the fast check finds an anomaly.

Outcome: every join gets a green/orange/red seal in the queue proving (cheaply) nothing was lost, with
a one-click cryptographic proof available when it matters.

## Verification tiers (the techniques to implement)

Always restrict ffmpeg/ffprobe `-map` to the **kept streams** — `v:0` and `a:0` only — so the dropped
mjpeg-preview/DATA tracks never pollute the comparison. `hasAudio = job.clips.first?.streamInfo?.audio
!= nil`; when false, omit `a:0` everywhere.

- **Tier 0 — readability gate** (always, ~ms–s): `ffprobe -v error -select_streams v:0 -count_packets
  -show_entries stream=nb_read_packets -of csv=p=0 OUTPUT` must exit 0. Catches faststart/moov
  corruption + truncation for free.
- **Tier 1 — fast source↔target** (always, ~1–5s), per kept stream:
  - packet count: output == Σ(sources), **exact** (`-count_packets`, `nb_read_packets`).
  - packet bytes: output == Σ(sources), **exact** (`-show_entries packet=size`, summed).
  - duration: output ≈ Σ(source durations), tolerance **±1 frame interval**; ≥ a whole segment short →
    fail "missing trailing segment".
  - codec-param identity across all N segments + output (reuse `StreamParameterGuard`).
  - A/V drift: output `v:0` vs `a:0` duration within tolerance.
- **Tier 2 — thorough byte-exact hash** (opt-in / on Tier-1 anomaly, tens of s–min): per-stream packet
  MD5 must match —
  - sources: `ffmpeg -f concat -safe 0 -i list.txt -map 0:v:0 -map 0:a:0 -c copy -hash md5 -f streamhash -`
  - output:  `ffmpeg -i OUTPUT -map 0:v:0 -map 0:a:0 -c copy -hash md5 -f streamhash -`
  - compare per-stream lines. On mismatch, this is the definitive failure.

Tolerances pinned by tests: `durationToleranceFrames = 1.0`; `frameInterval = 1/fps` (fps from
`clips.first?.streamInfo?.video.framesPerSecond ?? 30.0`); whole-segment shortfall = `Σsource − output
≥ shortestSegment × 0.9`. Packet count, packet bytes, codec params, and hash are **exact** (any diff =
fail). Duration within tolerance = info; beyond but < whole-segment = warning (escalate to hash); ≥
whole-segment = fail.

## Implementation

### New files

- **`01_Project/Conjoyn/Models/SourceTargetModels.swift`** — result types:
  - `CheckSeverity: Int { pass=0, info=1, warning=2, fail=3 }` (Comparable, Codable, Sendable; worst-wins).
  - `CheckOutcome { pass, info(String), warning(String), fail(String) }` (comparator return).
  - `VerificationCheck { kind, severity, label, detail }` with `Kind { readability, packetCount,
    packetBytes, duration, avDrift, codecParams, hashMatch }`.
  - `SourceTargetResult { tier(.fast/.thorough), checks, verifiedAt, duration }` with computed
    `overall` (worst-wins), `passed` (≤ .info), `hasWarning`, `firstFailureReason`, `summary`.

- **`01_Project/Conjoyn/Services/SourceTargetVerifier.swift`** — `final class … @unchecked Sendable`,
  modeled on `VerificationService.swift` (NSLock-guarded `_currentProcess`/`_isCancelling`,
  `cancel()`/`resetCancellation()`, `BundledToolResolver.shared` for ffmpeg/ffprobe paths).
  - API: `verifyFast(_ input, progress, logHandler) async -> SourceTargetResult` (Tier 0+1);
    `verifyThorough(…) async -> SourceTargetResult` (Tier 0+1+2). **Both return a result, never throw**
    — an errored verifier (missing tool, ejected source) is a `.fail` check, never a queue crash.
  - `struct SourceTargetInput: Sendable { sourceSegments: [URL]; outputURL: URL; hasAudio: Bool;
    sourceParams: [SegmentStreamInfo?] }`.
  - Private `runCapturingStdout(at:arguments:) async -> (stdout, exitCode)` — **dedicated** stdout/exit
    runner (do NOT reuse `FFmpegWrapper.runFFmpeg`, which is encode/progress-shaped). Pattern after
    `VerificationService.runProcess` but return the exit code; register in `currentProcess` so `cancel()`
    can kill a minutes-long Tier-2 hash.
  - **Reuse** `FFmpegWrapper.buildConcatList(for:)` (`FFmpegWrapper+Conversion.swift:38`) for the Tier-2
    source list (guarantees byte-identical ordering/escaping vs the join), written to a temp file with
    the `mergeClips` temp idiom + `defer` cleanup. **Reuse** `FFmpegWrapper.probeStreamInfo` /
    `probeDurationMilliseconds` for codec params + durations.
  - **Pure comparators** (factored out, non-private, unit-tested): `compareCounts`, `compareByteSizes`,
    `compareDuration`, `compareAVDrift`, `compareCodecParams` (delegates to `StreamParameterGuard.check`),
    `classifyHashLines`. All arithmetic/classification is process-free.

- **`01_Project/ConjoynTests/SourceTargetVerifierTests.swift`** — see Verification section.

### Modified files

- **`Models/VerificationModels.swift`** — add `VerificationStatus.warning(String)` (the existing enum is
  pass/fail-only; we need a first-class orange "flagged-but-passed" state). Add `displayName` "Flagged" /
  `iconName "exclamationmark.seal.fill"` / `isFinished = true` and a `"warning"` Codable tag in the
  existing `init(from:)`/`encode(to:)` switches (lines ~60–86). Additive + default-case fallback → old
  `queue.json` still decodes.
- **`Models/ConversionJob.swift`** — add `var sourceTargetResult: SourceTargetResult?` (+ CodingKey ~L291).
  Leave the old `verificationResult` field alone.
- **`Services/QueueManager.swift`** — add `let sourceTargetVerifier = SourceTargetVerifier()` (~L55).
- **`Services/QueueManager+Processing.swift`** — insert `await autoVerifyJoin(jobId:)` right after the
  completion update (`j.status = .completed`, ~L139), before the speed-record/log block. The hook sits
  **before** the source-scope `defer` stops (L105–112) fire, so auto-verify inherits live source access.
- **`Services/QueueManager+Verification.swift`** — repurpose the dead decode-only wiring:
  - `autoVerifyJoin(jobId:)` — build input, set `.verifying`, run `verifyFast`, write
    `sourceTargetResult` + map status, log one-line verdict, `saveQueue()`. If `hasWarning || !passed`,
    auto-escalate to `runThoroughVerify`. Heavy ffprobe runs inside the verifier's async `Process`
    (off the main actor); the `await` keeps strict job ordering (a few seconds between jobs is
    acceptable — note the unstructured-`Task` alternative in a comment).
  - `runThoroughVerify(jobId:reason:)` — `verifyThorough`, progress → `job.verificationProgress`. For the
    **manual** path, re-resolve source access via the existing `resolveSourceBookmark()` +
    `startAccessingIfNeeded`/`stopAccessingIfNeeded` (`QueueManager.swift:323`) since scope may have
    lapsed since the join.
  - `verifyJobThorough(jobId:)` — `Task { await runThoroughVerify(…, reason: "manual") }` for the button.
  - `makeVerifierInput(for:)` + `mapStatus(_:)` `@MainActor` helpers. Point `cancelVerification()` at
    `sourceTargetVerifier.cancel()`.
- **`Views/QueuePanel.swift`** (`QueueRow`) — follow the `IntegrityChip`/`folderMismatch` language:
  - **Seal badge** in the action HStack (~L290) for `.completed`, driven by `verificationStatus`:
    `.verified`→`checkmark.seal.fill` `Theme.ok`; `.warning`→`exclamationmark.seal.fill` `Theme.acc1`;
    `.failed`→`xmark.seal.fill` `Theme.bad`; `.verifying`→animated `arrow.triangle.2.circlepath`;
    `.unverified`→greyed `questionmark.circle`. Each with `.help(reason)`.
  - **Disclosure detail** in `TimecodeDisclosurePanel` (~L427): a chip row from `result.checks`
    rendered by a new `VerificationChip(check:)` (near-copy of `IntegrityChip` — orange/red for
    warning/fail, capsule, `.help(detail)`); show only non-`.pass` checks (green seal communicates
    all-passed).
  - **Manual button** `Button("Thorough verify (byte-exact)")` `.cjGhost`, disabled while `.verifying`,
    calling `queue.verifyJobThorough(job.id)`; caption "Hashes kept streams (v:0/a:0) end-to-end."
    Show `CJProgressBar(fraction: job.verificationProgress)` while the hash runs.
  - Extend `statusText` (~L369) to surface "Verifying…" on a *completed* row during auto/manual check.
  - Console logging via `logHandler` → `QueueManager.log`: `✓`/`⚠`/`✗` glyphs (the console already tints
    `✓` green, `✗`/error red).

### Edge cases (handled in the design)

- **N=1 single-file export** — no special case; `sourceSegments=[oneClip]`, sums over one element.
- **Renamed/collision-suffixed output** — always read `actualOutputURLs.first ?? destinationURL`.
- **Ejected/locked source** — affected check → `.fail("source unavailable — <name>")`, never a crash;
  manual path re-resolves the security-scoped bookmark first.
- **Audio-less clips** — drop `a:0` from every probe/hash and the compared set.
- **VFR / `0/0` fps** — fall back to 30 fps for the tolerance, matching the rest of the app.
- **Old decode-only `VerificationService`** — left in place, unwired; not deleted (its tests +
  `passesFrameCheck` calibration still referenced). `deleteOriginalsAfterVerify` gating on the new
  result is a noted follow-up, out of scope.

## Verification (how to test)

- **Unit tests** (`SourceTargetVerifierTests.swift`, no ffmpeg): exact equality for counts/bytes;
  duration ±1-frame tolerance vs warning vs whole-segment fail; codec-param mismatch fail; A/V drift;
  `classifyHashLines` equal/differing/line-count cases; worst-wins `overall`/`passed`/`hasWarning`;
  pin the tolerance constants; `VerificationStatus.warning` Codable round-trip.
- **Integration test** (skips without ffmpeg, guard idiom from `VerificationServiceTests.swift:105`):
  generate two `lavfi testsrc` clips, join via `mergeClips`/`buildMergeArguments`, assert
  `verifyThorough().passed` and all Tier-1 checks pass + hash matches. **Negative case:** swap the last
  source for a shorter clip after the join, assert the duration check fails "missing trailing segment"
  (or hash mismatches) — proving the verifier catches a bad target.
- **Live** (clean build cycle: kill → clean → build → launch): run a real split-group join on a card;
  confirm the green seal appears automatically within a few seconds; open the row disclosure, click
  **Thorough verify**, confirm the byte-exact hash passes with progress. If a known-good vs tampered
  output is available, confirm the red/orange seal + specific reason.

## Notes

- Project is **xcodegen-driven**: after adding the 3 new files run `cd 01_Project && xcodegen generate`
  (existing-file edits need no regen).
- **Commit breakdown** (each compiles + green; branch off `main` first, solo-dev local merge, no PR):
  1. Models — `SourceTargetModels.swift` + `VerificationStatus.warning` + `ConversionJob` field + Codable tests.
  2. `SourceTargetVerifier` (Tier 0/1/2) + pure comparator unit tests + xcodegen.
  3. Trigger wiring — auto fast-verify on completion + manual thorough verify + integration test.
  4. UI — `QueueRow` seal, chips, thorough button, progress.
