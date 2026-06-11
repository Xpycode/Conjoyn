import XCTest
@testable import Conjoyn

/// Unit tests for the **pure comparators** of `SourceTargetVerifier` (Wave 2, Commit 2).
///
/// These exercise only the process-free arithmetic/classification (`compareCounts`,
/// `compareByteSizes`, `compareDuration`, `compareAVDrift`, `compareCodecParams`,
/// `classifyHashLines`) plus the pinned tolerance constants — **no ffmpeg/ffprobe spawned**. The
/// ffmpeg-backed integration test (generate clips → join → `verifyThorough`) is a later commit.
final class SourceTargetVerifierTests: XCTestCase {

    private let verifier = SourceTargetVerifier()

    // 30 fps → one frame = 33.33ms. Used as the duration tolerance throughout.
    private let frameMs = 1000.0 / 30.0

    // MARK: - Helpers

    private func makeSegment(
        codec: String = "h264",
        width: Int = 3840,
        height: Int = 2160,
        pixFmt: String = "yuv420p",
        fps: String = "30000/1001",
        timeBase: String = "1/30000",
        audio: StreamParameterGuard.AudioStreamParams? = nil
    ) -> StreamParameterGuard.SegmentStreamInfo {
        StreamParameterGuard.SegmentStreamInfo(
            video: StreamParameterGuard.VideoStreamParams(
                codecName: codec,
                width: width,
                height: height,
                pixelFormat: pixFmt,
                avgFrameRate: fps,
                timeBase: timeBase
            ),
            audio: audio
        )
    }

    // MARK: - compareCounts (exact)

    func testCountsExactMatchPasses() {
        XCTAssertEqual(verifier.compareCounts(output: 900, sources: [300, 300, 300]).severity, .pass)
    }

    func testCountsOffByOneFails() {
        let outcome = verifier.compareCounts(output: 899, sources: [300, 300, 300])
        XCTAssertEqual(outcome.severity, .fail)
    }

    func testCountsSingleSourcePasses() {
        XCTAssertEqual(verifier.compareCounts(output: 300, sources: [300]).severity, .pass)
    }

    func testCountsProbeFailureFails() {
        XCTAssertEqual(verifier.compareCounts(output: -1, sources: [300]).severity, .fail)
        XCTAssertEqual(verifier.compareCounts(output: 300, sources: [-1, 300]).severity, .fail)
    }

    // MARK: - compareByteSizes (exact)

    func testByteSizesExactMatchPasses() {
        XCTAssertEqual(verifier.compareByteSizes(output: 6_000, sources: [2_000, 2_000, 2_000]).severity, .pass)
    }

    func testByteSizesMismatchFails() {
        XCTAssertEqual(verifier.compareByteSizes(output: 5_999, sources: [2_000, 2_000, 2_000]).severity, .fail)
    }

    func testByteSizesProbeFailureFails() {
        XCTAssertEqual(verifier.compareByteSizes(output: -1, sources: [2_000]).severity, .fail)
    }

    // MARK: - compareDuration (±1 frame info / warning / whole-segment fail)

    func testDurationWithinOneFrameIsInfo() {
        // Output 20ms short of a 30,000ms total — inside one 33.33ms frame.
        let outcome = verifier.compareDuration(
            outputMs: 29_980, sourceMs: [10_000, 10_000, 10_000],
            frameIntervalMs: frameMs, shortestSegmentMs: 10_000
        )
        XCTAssertEqual(outcome.severity, .info)
    }

    func testDurationExactIsInfo() {
        let outcome = verifier.compareDuration(
            outputMs: 30_000, sourceMs: [10_000, 10_000, 10_000],
            frameIntervalMs: frameMs, shortestSegmentMs: 10_000
        )
        XCTAssertEqual(outcome.severity, .info)
    }

    func testDurationBeyondToleranceButSubSegmentIsWarning() {
        // 500ms short — well beyond a frame, far below a 10,000ms segment.
        let outcome = verifier.compareDuration(
            outputMs: 29_500, sourceMs: [10_000, 10_000, 10_000],
            frameIntervalMs: frameMs, shortestSegmentMs: 10_000
        )
        XCTAssertEqual(outcome.severity, .warning)
    }

    func testDurationWholeSegmentShortIsFail() {
        // A full trailing segment missing: 20,000ms output vs 30,000ms total.
        let outcome = verifier.compareDuration(
            outputMs: 20_000, sourceMs: [10_000, 10_000, 10_000],
            frameIntervalMs: frameMs, shortestSegmentMs: 10_000
        )
        XCTAssertEqual(outcome.severity, .fail)
        XCTAssertTrue(outcome.detail?.contains("missing trailing segment") ?? false,
                      "fail detail should name the missing-trailing-segment cause: \(outcome.detail ?? "nil")")
    }

    func testDurationWholeSegmentBoundaryAt90PercentFails() {
        // Shortfall exactly 90% of the shortest segment → fail (the pinned threshold).
        let outcome = verifier.compareDuration(
            outputMs: 21_000, sourceMs: [10_000, 10_000, 10_000],
            frameIntervalMs: frameMs, shortestSegmentMs: 10_000
        )
        XCTAssertEqual(outcome.severity, .fail)
    }

    // MARK: - compareAVDrift

    func testAVDriftWithinToleranceIsPass() {
        XCTAssertEqual(
            verifier.compareAVDrift(videoMs: 30_000, audioMs: 30_010, frameIntervalMs: frameMs).severity,
            .pass
        )
    }

    func testAVDriftBeyondToleranceIsWarning() {
        XCTAssertEqual(
            verifier.compareAVDrift(videoMs: 30_000, audioMs: 30_500, frameIntervalMs: frameMs).severity,
            .warning
        )
    }

    func testAVDriftUnmeasurableIsPass() {
        XCTAssertEqual(verifier.compareAVDrift(videoMs: 0, audioMs: 30_000, frameIntervalMs: frameMs).severity, .pass)
    }

    // MARK: - compareCodecParams

    func testCodecParamsIdenticalPasses() {
        let a = makeSegment()
        let b = makeSegment()
        XCTAssertEqual(verifier.compareCodecParams(sources: [a, b], output: a).severity, .pass)
    }

    func testCodecParamsMismatchFails() {
        let a = makeSegment(codec: "h264")
        let b = makeSegment(codec: "hevc")   // differing codec
        let outcome = verifier.compareCodecParams(sources: [a, b], output: a)
        XCTAssertEqual(outcome.severity, .fail)
    }

    func testCodecParamsOutputMismatchFails() {
        let a = makeSegment(width: 3840, height: 2160)
        let output = makeSegment(width: 1920, height: 1080)  // output resolution differs
        let outcome = verifier.compareCodecParams(sources: [a, a], output: output)
        XCTAssertEqual(outcome.severity, .fail)
    }

    func testCodecParamsNilEntriesSkipped() {
        let a = makeSegment()
        // Two nils + one known + matching output → nothing to disprove → pass.
        XCTAssertEqual(verifier.compareCodecParams(sources: [nil, a], output: a).severity, .pass)
    }

    // MARK: - classifyHashLines

    func testHashLinesEqualPasses() {
        let lines = ["0,v,MD5=aaaa", "1,a,MD5=bbbb"]
        XCTAssertEqual(verifier.classifyHashLines(sourceLines: lines, outputLines: lines).severity, .pass)
    }

    func testHashLinesDifferingFails() {
        let src = ["0,v,MD5=aaaa", "1,a,MD5=bbbb"]
        let out = ["0,v,MD5=aaaa", "1,a,MD5=cccc"]   // audio hash differs
        let outcome = verifier.classifyHashLines(sourceLines: src, outputLines: out)
        XCTAssertEqual(outcome.severity, .fail)
    }

    func testHashLinesCountMismatchFails() {
        let src = ["0,v,MD5=aaaa", "1,a,MD5=bbbb"]
        let out = ["0,v,MD5=aaaa"]   // audio stream dropped
        XCTAssertEqual(verifier.classifyHashLines(sourceLines: src, outputLines: out).severity, .fail)
    }

    func testHashLinesEmptyFails() {
        XCTAssertEqual(verifier.classifyHashLines(sourceLines: [], outputLines: ["x"]).severity, .fail)
        XCTAssertEqual(verifier.classifyHashLines(sourceLines: ["x"], outputLines: []).severity, .fail)
    }

    // MARK: - Pinned tolerance constants (a refactor must not silently change these)

    func testToleranceConstantsArePinned() {
        XCTAssertEqual(SourceTargetVerifier.durationToleranceFrames, 1.0)
        XCTAssertEqual(SourceTargetVerifier.fpsFallback, 30.0)
        XCTAssertEqual(SourceTargetVerifier.wholeSegmentShortfallFraction, 0.9)
    }

    // MARK: - Roll-up sanity (worst-wins through the result type)

    func testResultWorstWinsRollup() {
        let checks = [
            VerificationCheck(kind: .readability, severity: .pass, label: "R", detail: ""),
            VerificationCheck(kind: .duration, severity: .warning, label: "D", detail: "Δ"),
            VerificationCheck(kind: .packetCount, severity: .pass, label: "C", detail: ""),
        ]
        let result = SourceTargetResult(tier: .fast, checks: checks, verifiedAt: Date(), duration: 0)
        XCTAssertEqual(result.overall, .warning)
        XCTAssertFalse(result.passed)       // `passed` is `overall <= .info`; a warning is not passed.
        XCTAssertTrue(result.hasWarning)

        let infoOnly = [
            VerificationCheck(kind: .readability, severity: .pass, label: "R", detail: ""),
            VerificationCheck(kind: .duration, severity: .info, label: "D", detail: "Δ"),
        ]
        let infoResult = SourceTargetResult(tier: .fast, checks: infoOnly, verifiedAt: Date(), duration: 0)
        XCTAssertTrue(infoResult.passed)    // info ≤ .info → passed.
        XCTAssertFalse(infoResult.hasWarning)
    }
}

// MARK: - Integration: real join → verify (skips without ffmpeg)

/// End-to-end integration test for `SourceTargetVerifier`: generates two joinable `lavfi testsrc`
/// clips, joins them through the **real** join path (`FFmpegWrapper.mergeClips`), and asserts the
/// byte-exact thorough verification passes. A negative case swaps a source for a shorter clip after
/// the join and asserts the verifier flags the bad target. Skipped when no ffmpeg/ffprobe is
/// available (bundled or Homebrew) — guard idiom from `VerificationServiceTests:105`.
final class SourceTargetVerifierIntegrationTests: XCTestCase {

    private let verifier = SourceTargetVerifier()
    private let ffmpeg = FFmpegWrapper()

    /// Generates one **video-only** `testsrc` clip via a direct ffmpeg invocation. `offset` shifts
    /// the test pattern so two clips are genuinely distinct content (their per-clip hashes differ —
    /// so a wrong/missing segment is detectable).
    ///
    /// Deliberately **no audio track**: a synthetic AAC stream carries encoder priming/padding that
    /// the concat demuxer re-frames, so the summed source AAC packet bytes don't equal the output's
    /// — an artifact of generated test data, not a verifier bug (real DJI footage joins clean). A
    /// video-only `mpeg4` stream concatenated with `-c copy` is genuinely byte-identical, which is
    /// exactly the lossless guarantee the verifier asserts.
    private func generateClip(
        ffmpegURL: URL,
        to url: URL,
        durationSeconds: Double,
        offset: Int
    ) throws {
        let gen = Process()
        gen.executableURL = ffmpegURL
        // Encoders are constrained to what the bundled (LGPL) ffmpeg ships — `mpeg4` only; the GPL
        // `libx264` is NOT bundled (the join is `-c copy`, so the app never encodes). Using
        // `libx264` here would fail with "Unknown encoder" under the app test host.
        gen.arguments = [
            "-y",
            "-f", "lavfi", "-i",
            "testsrc=duration=\(durationSeconds):size=160x120:rate=30,format=yuv420p,"
                + "hue=h=\(offset * 60)",
            "-c:v", "mpeg4",
            url.path,
        ]
        // Null the pipes (don't use an undrained `Pipe()` — the encoder is verbose enough to fill
        // the 64KB pipe buffer and deadlock).
        gen.standardOutput = FileHandle.nullDevice
        gen.standardError = FileHandle.nullDevice
        try gen.run(); gen.waitUntilExit()
        try XCTSkipIf(gen.terminationStatus != 0, "ffmpeg could not generate a test clip")
    }

    private func makeInput(sources: [URL], output: URL) -> SourceTargetVerifier.SourceTargetInput {
        SourceTargetVerifier.SourceTargetInput(
            sourceSegments: sources,
            outputURL: output,
            hasAudio: false,
            sourceParams: sources.map { try? ffmpeg.probeStreamInfo($0) }
        )
    }

    func testRealJoinVerifiesByteExact() async throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpegURL = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }

        let tmp = FileManager.default.temporaryDirectory
        let clipA = tmp.appendingPathComponent("conjoyn-it-a-\(UUID().uuidString).mp4")
        let clipB = tmp.appendingPathComponent("conjoyn-it-b-\(UUID().uuidString).mp4")
        let output = tmp.appendingPathComponent("conjoyn-it-out-\(UUID().uuidString).mp4")
        defer {
            for u in [clipA, clipB, output] { try? FileManager.default.removeItem(at: u) }
        }

        try generateClip(ffmpegURL: ffmpegURL, to: clipA, durationSeconds: 2, offset: 0)
        try generateClip(ffmpegURL: ffmpegURL, to: clipB, durationSeconds: 2, offset: 1)

        // Join through the REAL join path (concat demuxer, -c copy).
        try await ffmpeg.mergeClips(
            [clipA, clipB],
            to: output,
            progress: { _, _ in },
            logHandler: { _ in }
        )

        // --- Positive case: thorough verify must pass, with the hash check matching. ---
        let goodInput = makeInput(sources: [clipA, clipB], output: output)
        let goodResult = await verifier.verifyThorough(goodInput)

        XCTAssertTrue(goodResult.passed,
                      "a clean join of its own sources should pass thorough verify; summary=\(goodResult.summary)")
        let hashCheck = goodResult.checks.first { $0.kind == .hashMatch }
        XCTAssertNotNil(hashCheck, "thorough verify should include a byte-exact hash check")
        XCTAssertEqual(hashCheck?.severity, .pass, "kept-stream hashes should match the sources")
        // Tier-1 checks should all be clean (no .warning / .fail).
        for check in goodResult.checks where check.kind != .hashMatch {
            XCTAssertLessThanOrEqual(check.severity, .info,
                                     "\(check.kind) should pass for a clean join (detail: \(check.detail))")
        }

        // --- Negative case: swap a source for a SHORTER clip → verifier must catch the bad target. ---
        let shortClip = tmp.appendingPathComponent("conjoyn-it-short-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: shortClip) }
        // Half-length stand-in for clipB; the real output still contains the full clipB content, so
        // the claimed sources no longer sum to the output (duration short / packet mismatch / hash).
        try generateClip(ffmpegURL: ffmpegURL, to: shortClip, durationSeconds: 1, offset: 1)

        let badInput = makeInput(sources: [clipA, shortClip], output: output)
        let badResult = await verifier.verifyThorough(badInput)

        XCTAssertFalse(badResult.passed,
                       "swapping a source for a shorter clip must fail verification; summary=\(badResult.summary)")
        XCTAssertEqual(badResult.overall, .fail,
                       "a missing/wrong segment is a definitive failure, not a warning")
        // At least one of the source↔target checks (duration, packet count/bytes, or hash) must fail.
        let failingKinds: Set<VerificationCheck.Kind> = [.duration, .packetCount, .packetBytes, .hashMatch]
        let failed = badResult.checks.filter { $0.severity == .fail && failingKinds.contains($0.kind) }
        XCTAssertFalse(failed.isEmpty,
                       "expected a duration/count/bytes/hash failure; checks=\(badResult.checks)")
    }
}
