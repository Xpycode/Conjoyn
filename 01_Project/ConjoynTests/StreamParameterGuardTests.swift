import XCTest
@testable import Conjoyn

/// Backpressure for task 2.6: the pure stream-parameter comparison + ffprobe-JSON decoding,
/// plus a skippable integration test against real ffprobe output.
final class StreamParameterGuardTests: XCTestCase {

    typealias Guard = StreamParameterGuard

    // A reference video stream; helpers below tweak one field at a time.
    private func video(codec: String = "h264", w: Int = 3840, h: Int = 2160,
                       pix: String = "yuv420p", fps: String = "30000/1001",
                       tb: String = "1/30000") -> Guard.VideoStreamParams {
        .init(codecName: codec, width: w, height: h, pixelFormat: pix, avgFrameRate: fps, timeBase: tb)
    }
    private func segment(_ v: Guard.VideoStreamParams, audio: Guard.AudioStreamParams? = nil) -> Guard.SegmentStreamInfo {
        .init(video: v, audio: audio)
    }
    private let aac = Guard.AudioStreamParams(codecName: "aac", sampleRate: "48000", channels: 2, channelLayout: "stereo")

    // MARK: - Compatible cases

    func testIdenticalSegmentsAreCompatible() {
        let s = segment(video(), audio: aac)
        XCTAssertEqual(Guard.check([s, s, s]), .compatible)
    }

    func testSingleSegmentIsCompatible() {
        XCTAssertEqual(Guard.check([segment(video())]), .compatible)
    }

    func testEmptyIsCompatible() {
        XCTAssertEqual(Guard.check([]), .compatible)
    }

    // MARK: - Each mismatch is refused with a descriptive reason

    func testCodecMismatchRefused() {
        let result = Guard.check([segment(video(codec: "h264")), segment(video(codec: "hevc"))])
        assertIncompatible(result, mentioning: "codec")
    }

    func testResolutionMismatchRefused() {
        let result = Guard.check([segment(video(w: 3840, h: 2160)), segment(video(w: 1920, h: 1080))])
        assertIncompatible(result, mentioning: "resolution")
    }

    func testFrameRateMismatchRefused() {
        let result = Guard.check([segment(video(fps: "30000/1001")), segment(video(fps: "25/1"))])
        assertIncompatible(result, mentioning: "frame rate")
    }

    func testPixelFormatMismatchRefused() {
        let result = Guard.check([segment(video(pix: "yuv420p")), segment(video(pix: "yuv422p10le"))])
        assertIncompatible(result, mentioning: "pixel format")
    }

    func testTimeBaseMismatchRefused() {
        let result = Guard.check([segment(video(tb: "1/30000")), segment(video(tb: "1/25000"))])
        assertIncompatible(result, mentioning: "time base")
    }

    func testAudioPresenceMismatchRefused() {
        let result = Guard.check([segment(video(), audio: aac), segment(video(), audio: nil)])
        assertIncompatible(result, mentioning: "audio presence")
    }

    func testAudioSampleRateMismatchRefused() {
        var other = aac; other.sampleRate = "44100"
        let result = Guard.check([segment(video(), audio: aac), segment(video(), audio: other)])
        assertIncompatible(result, mentioning: "audio sample rate")
    }

    func testReasonNamesTheOffendingSegment() {
        // Segments 1 & 2 match; segment 3 differs → message should cite segment 3.
        let result = Guard.check([segment(video()), segment(video()), segment(video(w: 1920, h: 1080))])
        if case let .incompatible(reason) = result {
            XCTAssertTrue(reason.contains("segment 3"), "expected segment 3 cited, got: \(reason)")
        } else {
            XCTFail("expected incompatible")
        }
    }

    // MARK: - ffprobe JSON decoding (no process)

    func testParseFFprobeJSON() throws {
        let json = """
        { "streams": [
            { "index": 0, "codec_type": "video", "codec_name": "hevc", "width": 3840,
              "height": 2160, "pix_fmt": "yuv420p10le", "avg_frame_rate": "30000/1001",
              "time_base": "1/30000" },
            { "index": 1, "codec_type": "audio", "codec_name": "aac", "sample_rate": "48000",
              "channels": 2, "channel_layout": "stereo" }
        ] }
        """.data(using: .utf8)!

        let info = try Guard.parse(ffprobeJSON: json, source: "DJI_0001.MP4")
        XCTAssertEqual(info.video.codecName, "hevc")
        XCTAssertEqual(info.video.width, 3840)
        XCTAssertEqual(info.video.height, 2160)
        XCTAssertEqual(info.video.pixelFormat, "yuv420p10le")
        XCTAssertEqual(info.video.avgFrameRate, "30000/1001")
        XCTAssertEqual(info.audio?.codecName, "aac")
        XCTAssertEqual(info.audio?.sampleRate, "48000")
        XCTAssertEqual(info.audio?.channels, 2)
    }

    func testParseRejectsNoVideoStream() {
        let json = #"{ "streams": [ { "index": 0, "codec_type": "audio", "codec_name": "aac" } ] }"#
            .data(using: .utf8)!
        XCTAssertThrowsError(try Guard.parse(ffprobeJSON: json))
    }

    // MARK: - Integration (real ffprobe; skips without ffmpeg/ffprobe)

    func testEnsureJoinableAgainstRealProbe() throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }

        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let a = dir.appendingPathComponent("a.mp4")
        let b = dir.appendingPathComponent("b.mp4")
        let mismatched = dir.appendingPathComponent("c.mp4")
        try generateClip(ffmpeg: ffmpeg, size: "160x120", to: a)
        try generateClip(ffmpeg: ffmpeg, size: "160x120", to: b)
        try generateClip(ffmpeg: ffmpeg, size: "320x240", to: mismatched)

        let wrapper = FFmpegWrapper()
        // Same params → no throw.
        XCTAssertNoThrow(try wrapper.ensureJoinable([a, b]))
        // Different resolution → throws with a resolution reason.
        XCTAssertThrowsError(try wrapper.ensureJoinable([a, mismatched])) { error in
            XCTAssertTrue("\(error)".lowercased().contains("resolution"), "got: \(error)")
        }
    }

    // MARK: - Helpers

    private func assertIncompatible(_ result: Guard.Compatibility, mentioning needle: String,
                                    file: StaticString = #filePath, line: UInt = #line) {
        guard case let .incompatible(reason) = result else {
            return XCTFail("expected incompatible (mentioning \(needle))", file: file, line: line)
        }
        XCTAssertTrue(reason.contains(needle), "reason '\(reason)' should mention '\(needle)'", file: file, line: line)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("djijoiner-guard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func generateClip(ffmpeg: URL, size: String, to url: URL) throws {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=\(size):rate=30",
                       "-pix_fmt", "yuv420p", url.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ffmpeg failed to generate \(size) clip")
    }
}
