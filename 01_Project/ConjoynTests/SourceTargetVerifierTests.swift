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
