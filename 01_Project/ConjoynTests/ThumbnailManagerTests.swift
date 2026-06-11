import XCTest
import CoreMedia
import AppKit
@testable import Conjoyn

/// Tests for the ported `ThumbnailManager` + `FFmpegWrapper+Thumbnails` (Wave 1, task 1.10).
///
/// The deterministic core is the last-frame seek arithmetic (`DJIClip.lastFrameSeekSeconds` and the
/// `VideoStreamParams.framesPerSecond` rational decode it leans on) and the actor's cache lifecycle,
/// all exercised without FFmpeg. One skippable integration test drives the whole extraction path
/// over a real ffmpeg-muxed clip.
final class ThumbnailManagerTests: XCTestCase {

    // MARK: - Helpers

    private func makeClip(
        seconds: Double,
        videoURL: URL = URL(fileURLWithPath: "/tmp/does-not-exist.mp4"),
        fps avgFrameRate: String? = nil
    ) -> DJIClip {
        var streamInfo: StreamParameterGuard.SegmentStreamInfo?
        if let avgFrameRate {
            streamInfo = StreamParameterGuard.SegmentStreamInfo(
                video: StreamParameterGuard.VideoStreamParams(
                    codecName: "h264", width: 1920, height: 1080,
                    pixelFormat: "yuv420p", avgFrameRate: avgFrameRate, timeBase: "1/30000"
                ),
                audio: nil
            )
        }
        return DJIClip(
            videoURL: videoURL,
            index: 1,
            stem: "DJI_0001",
            duration: CMTime(seconds: seconds, preferredTimescale: 600),
            streamInfo: streamInfo
        )
    }

    // MARK: - framesPerSecond rational decode

    func testFramesPerSecondParsesNTSCRational() {
        let v = StreamParameterGuard.VideoStreamParams(
            codecName: "h264", width: 1920, height: 1080,
            pixelFormat: "yuv420p", avgFrameRate: "30000/1001", timeBase: "1/30000"
        )
        XCTAssertEqual(v.framesPerSecond ?? 0, 29.97, accuracy: 0.01)
    }

    func testFramesPerSecondParsesIntegerRational() {
        let v = StreamParameterGuard.VideoStreamParams(
            codecName: "h264", width: 1920, height: 1080,
            pixelFormat: "yuv420p", avgFrameRate: "30/1", timeBase: "1/30"
        )
        XCTAssertEqual(v.framesPerSecond ?? 0, 30.0, accuracy: 0.0001)
    }

    func testFramesPerSecondNilForUnknownRate() {
        // ffprobe emits "0/0" when it can't determine a rate — must not divide by zero.
        let zero = StreamParameterGuard.VideoStreamParams(
            codecName: "h264", width: 0, height: 0,
            pixelFormat: "", avgFrameRate: "0/0", timeBase: "0/0"
        )
        XCTAssertNil(zero.framesPerSecond)

        let garbage = StreamParameterGuard.VideoStreamParams(
            codecName: "h264", width: 0, height: 0,
            pixelFormat: "", avgFrameRate: "N/A", timeBase: "0/0"
        )
        XCTAssertNil(garbage.framesPerSecond)
    }

    func testFramesPerSecondPrefersRFrameRate() {
        // DJI clips can have avg_frame_rate that computes to 29.97 while r_frame_rate is 25/1.
        // framesPerSecond must return the codec-signalled value, not the computed average.
        let v = StreamParameterGuard.VideoStreamParams(
            codecName: "hevc", width: 3840, height: 2160,
            pixelFormat: "yuv420p10le", avgFrameRate: "30000/1001", timeBase: "1/30000",
            rFrameRate: "25/1"
        )
        XCTAssertEqual(v.framesPerSecond ?? 0, 25.0, accuracy: 0.001)
    }

    // MARK: - lastFrameSeekSeconds

    func testLastFrameSeekUsesProbedFrameRate() {
        // 2 s @ 30 fps → ~2-frame guard before the end (2/30 > 0.05).
        let clip = makeClip(seconds: 2.0, fps: "30/1")
        XCTAssertEqual(clip.lastFrameSeekSeconds, 2.0 - 2.0 / 30.0, accuracy: 0.0001)
    }

    func testLastFrameSeekDefaultsTo30WithoutStreamInfo() {
        // No probed stream → assume 30 fps rather than seeking exactly to EOF.
        let clip = makeClip(seconds: 5.0)
        XCTAssertEqual(clip.lastFrameSeekSeconds, 5.0 - 2.0 / 30.0, accuracy: 0.0001)
    }

    func testLastFrameSeekDefaultsTo30ForUnknownRate() {
        // streamInfo present but rate is "0/0" → still falls back to 30 fps, no NaN/inf.
        let clip = makeClip(seconds: 5.0, fps: "0/0")
        XCTAssertEqual(clip.lastFrameSeekSeconds, 5.0 - 2.0 / 30.0, accuracy: 0.0001)
    }

    func testLastFrameSeekUsesFiftyMsFloorForHighFrameRate() {
        // At 120 fps, 2 frames = 16.7 ms < the 50 ms floor → back off 50 ms.
        let clip = makeClip(seconds: 3.0, fps: "120/1")
        XCTAssertEqual(clip.lastFrameSeekSeconds, 3.0 - 0.05, accuracy: 0.0001)
    }

    func testLastFrameSeekClampsToZeroForVeryShortClip() {
        // A clip shorter than one frame interval must not produce a negative seek.
        let clip = makeClip(seconds: 0.01, fps: "30/1")
        XCTAssertEqual(clip.lastFrameSeekSeconds, 0.0, accuracy: 0.0001)
    }

    // MARK: - Cache lifecycle (no FFmpeg required)

    func testGetThumbnailsCachesEvenWhenExtractionYieldsNothing() async {
        // A missing source yields empty thumbnails, but the *result* is still cached so we don't
        // relaunch FFmpeg on every scroll. This holds whether or not ffmpeg is installed.
        let manager = ThumbnailManager()
        let clip = makeClip(seconds: 1.0)

        let before = await manager.hasCachedThumbnails(for: clip.id)
        XCTAssertFalse(before)

        let result = await manager.getThumbnails(for: clip)
        XCTAssertNil(result.first)
        XCTAssertNil(result.last)

        let after = await manager.hasCachedThumbnails(for: clip.id)
        XCTAssertTrue(after, "the empty result should be cached")
    }

    func testClearCacheEmptiesTheCache() async {
        let manager = ThumbnailManager()
        let clip = makeClip(seconds: 1.0)

        _ = await manager.getThumbnails(for: clip)
        await manager.clearCache()

        let cached = await manager.hasCachedThumbnails(for: clip.id)
        XCTAssertFalse(cached)
    }

    // MARK: - Integration: extract real frames (skips without ffmpeg)

    func testExtractsFirstAndLastFrameFromRealClip() async throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpegBin = resolver.path(for: .ffmpeg) else {
            throw XCTSkip("No ffmpeg available (bundled or Homebrew)")
        }

        // 2 s @ 30 fps test pattern.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-thumb-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let gen = Process()
        gen.executableURL = ffmpegBin
        gen.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=2:size=160x120:rate=30",
                         "-pix_fmt", "yuv420p", url.path]
        gen.standardOutput = Pipe(); gen.standardError = Pipe()
        try gen.run(); gen.waitUntilExit()
        try XCTSkipIf(gen.terminationStatus != 0, "ffmpeg could not generate a test clip")

        let manager = ThumbnailManager()
        let clip = makeClip(seconds: 2.0, videoURL: url, fps: "30/1")

        let result = await manager.getThumbnails(for: clip)

        XCTAssertNotNil(result.first, "should extract a first-frame thumbnail")
        XCTAssertNotNil(result.last, "should extract a last-frame thumbnail")
        if let first = result.first {
            XCTAssertGreaterThan(first.size.width, 0)
        }

        // Second call must come from cache (and still be populated).
        let cached = await manager.getThumbnails(for: clip)
        XCTAssertNotNil(cached.first)
    }
}
