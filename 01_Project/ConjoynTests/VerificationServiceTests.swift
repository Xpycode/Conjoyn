import XCTest
@testable import Conjoyn

/// Tests for the ported `VerificationService` (Wave 1, task 1.9).
///
/// The bulk of these target `passesFrameCheck` — the full-decode pass criterion, which is the
/// load-bearing quality judgement of verification (it decides whether a stitched file is trusted
/// or flagged). It's pure arithmetic, so it's tested exhaustively and deterministically without
/// FFmpeg. One skippable integration test drives the whole `verify(...)` path over a real
/// ffmpeg-muxed clip.
final class VerificationServiceTests: XCTestCase {

    private let service = VerificationService()

    // MARK: - passesFrameCheck: normal case (have a usable estimate)

    func testExactMatchPasses() {
        XCTAssertTrue(service.passesFrameCheck(decoded: 1000, expected: 1000))
    }

    func testWithinTolerancePasses() {
        // 96% of expected — a frame or two short off rounded metadata is healthy.
        XCTAssertTrue(service.passesFrameCheck(decoded: 960, expected: 1000))
    }

    func testExactlyAtToleranceBoundaryPasses() {
        // 95.0% exactly — the boundary is inclusive (>=).
        XCTAssertTrue(service.passesFrameCheck(decoded: 950, expected: 1000))
    }

    func testJustBelowToleranceFails() {
        // 94.9% — one frame under the 95% bar.
        XCTAssertFalse(service.passesFrameCheck(decoded: 949, expected: 1000))
    }

    func testGrossTruncationFails() {
        // The classic failure this check exists to catch: a last segment cut short (30% missing).
        XCTAssertFalse(service.passesFrameCheck(decoded: 700, expected: 1000))
    }

    func testOverCountPasses() {
        // B-frames / rounding can push decoded slightly above expected — never a failure.
        XCTAssertTrue(service.passesFrameCheck(decoded: 1005, expected: 1000))
    }

    func testSmallIntegerBoundary() {
        // expected=20 → threshold 19.0; 19 passes, 18 fails. Guards integer/float rounding.
        XCTAssertTrue(service.passesFrameCheck(decoded: 19, expected: 20))
        XCTAssertFalse(service.passesFrameCheck(decoded: 18, expected: 20))
    }

    // MARK: - passesFrameCheck: no usable estimate (expected <= 0)

    func testNoEstimateWithFramesPasses() {
        // ffprobe couldn't size the file but the decoder still produced frames → trust the decode.
        XCTAssertTrue(service.passesFrameCheck(decoded: 1, expected: 0))
        XCTAssertTrue(service.passesFrameCheck(decoded: 5000, expected: 0))
    }

    func testNoEstimateWithZeroFramesFails() {
        // No estimate AND nothing decoded → genuinely broken.
        XCTAssertFalse(service.passesFrameCheck(decoded: 0, expected: 0))
    }

    func testNegativeExpectedTreatedAsNoEstimate() {
        // Defensive: a negative estimate can't bound anything; fall back to "decoded anything?".
        XCTAssertTrue(service.passesFrameCheck(decoded: 10, expected: -5))
        XCTAssertFalse(service.passesFrameCheck(decoded: 0, expected: -5))
    }

    // MARK: - passesFrameCheck: zero decoded with a real estimate

    func testZeroDecodedWithEstimateFails() {
        // Decoder produced nothing but we expected frames → fail (no tolerance saves this).
        XCTAssertFalse(service.passesFrameCheck(decoded: 0, expected: 1000))
    }

    // MARK: - Tolerance constant

    func testToleranceConstantIsFivePercentShortfall() {
        // Pins the documented default so an accidental change is caught by a test, not by footage.
        XCTAssertEqual(VerificationService.frameShortfallTolerance, 0.95, accuracy: 0.0001)
    }

    // MARK: - Public API: missing file throws

    func testVerifyMissingFileThrows() async {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-does-not-exist-\(UUID().uuidString).mp4")
        do {
            _ = try await service.verify(
                fileURL: missing,
                mode: .quick,
                progress: { _, _ in },
                logHandler: { _ in }
            )
            XCTFail("Expected verify to throw for a missing file")
        } catch {
            // Expected — fileNotFound.
        }
    }

    // MARK: - Integration: verify a real ffmpeg-muxed clip (skips without ffmpeg)

    func testFullVerifyOnRealHealthyClipPasses() async throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }

        // 2 s @ 30 fps = 60 frames; a complete, non-truncated file → must pass full verification.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-verify-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let gen = Process()
        gen.executableURL = ffmpeg
        gen.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=160x120:rate=30",
                         "-pix_fmt", "yuv420p", url.path]
        gen.standardOutput = Pipe(); gen.standardError = Pipe()
        try gen.run(); gen.waitUntilExit()
        try XCTSkipIf(gen.terminationStatus != 0, "ffmpeg could not generate a test clip")

        let result = try await service.verify(
            fileURL: url,
            mode: .full,
            expectedFrames: nil,                 // force it through the ffprobe estimate path
            progress: { _, _ in },
            logHandler: { _ in }
        )

        XCTAssertTrue(result.passed, "a complete 60-frame clip should pass full verification")
        XCTAssertTrue(result.containerValid)
        XCTAssertEqual(result.framesDecoded ?? 0, 60, accuracy: 2,
                       "expected ~60 decoded frames, got \(String(describing: result.framesDecoded))")
    }
}
