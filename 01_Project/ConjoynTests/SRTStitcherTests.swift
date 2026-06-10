import XCTest
@testable import Conjoyn

final class SRTStitcherTests: XCTestCase {

    typealias Segment = SRTStitcher.Segment

    // MARK: - Fixtures

    /// Two cues; the second near the segment's end (the segment is ~10 s long).
    private let segment1SRT = """
    1
    00:00:00,000 --> 00:00:01,000
    seg1-cueA

    2
    00:00:09,000 --> 00:00:10,000
    seg1-cueB

    """

    /// One cue at the segment's start (the segment is ~20 s long).
    private let segment2SRT = """
    1
    00:00:00,000 --> 00:00:01,000
    seg2-cueA

    """

    /// One five-second cue at the segment's start (the segment is ~15 s long).
    private let segment3SRT = """
    1
    00:00:00,000 --> 00:00:05,000
    seg3-cueA

    """

    private func doc(_ srt: String) -> SRTParser.Document { SRTParser.parse(srt) }

    // MARK: - Backpressure: 3 segments → continuous, correctly-timed, sequential

    func testThreeSegmentStitchIsContinuousAndSequential() {
        let stitched = SRTStitcher.stitch([
            Segment(durationMilliseconds: 10_000, document: doc(segment1SRT)),
            Segment(durationMilliseconds: 20_000, document: doc(segment2SRT)),
            Segment(durationMilliseconds: 15_000, document: doc(segment3SRT)),
        ])

        XCTAssertEqual(stitched.cues.count, 4)

        // Global renumbering 1…N regardless of each file's own indices.
        XCTAssertEqual(stitched.cues.map(\.index), [1, 2, 3, 4])

        // Segment 1 (offset 0) unchanged.
        XCTAssertEqual(stitched.cues[0].startMilliseconds, 0)
        XCTAssertEqual(stitched.cues[0].endMilliseconds, 1_000)
        XCTAssertEqual(stitched.cues[1].startMilliseconds, 9_000)
        XCTAssertEqual(stitched.cues[1].endMilliseconds, 10_000)

        // Segment 2 shifted by segment 1's duration (10 s).
        XCTAssertEqual(stitched.cues[2].startMilliseconds, 10_000)
        XCTAssertEqual(stitched.cues[2].endMilliseconds, 11_000)

        // Segment 3 shifted by segments 1+2 (30 s).
        XCTAssertEqual(stitched.cues[3].startMilliseconds, 30_000)
        XCTAssertEqual(stitched.cues[3].endMilliseconds, 35_000)

        // Strictly increasing, non-overlapping seams.
        for (a, b) in zip(stitched.cues, stitched.cues.dropFirst()) {
            XCTAssertLessThanOrEqual(a.endMilliseconds, b.startMilliseconds)
        }
    }

    func testPayloadsPreservedVerbatim() {
        let stitched = SRTStitcher.stitch([
            Segment(durationMilliseconds: 10_000, document: doc(segment1SRT)),
            Segment(durationMilliseconds: 20_000, document: doc(segment2SRT)),
        ])
        XCTAssertEqual(stitched.cues.map(\.payload), ["seg1-cueA", "seg1-cueB", "seg2-cueA"])
    }

    // MARK: - Missing sidecars still advance the offset

    func testMissingMiddleSidecarStillAdvancesOffset() {
        let stitched = SRTStitcher.stitch([
            Segment(durationMilliseconds: 10_000, document: doc(segment1SRT)),
            Segment(durationMilliseconds: 20_000, document: nil),          // no .SRT for segment 2
            Segment(durationMilliseconds: 15_000, document: doc(segment3SRT)),
        ])

        // Segment 2 contributes no cues, but its 20 s still pushes segment 3 to 30 s.
        XCTAssertEqual(stitched.cues.count, 3)
        XCTAssertEqual(stitched.cues.map(\.index), [1, 2, 3])
        XCTAssertEqual(stitched.cues[2].payload, "seg3-cueA")
        XCTAssertEqual(stitched.cues[2].startMilliseconds, 30_000)
        XCTAssertEqual(stitched.cues[2].endMilliseconds, 35_000)
    }

    func testMissingFirstSidecarShiftsLaterSegments() {
        let stitched = SRTStitcher.stitch([
            Segment(durationMilliseconds: 10_000, document: nil),          // first segment has no .SRT
            Segment(durationMilliseconds: 20_000, document: doc(segment2SRT)),
        ])
        XCTAssertEqual(stitched.cues.count, 1)
        XCTAssertEqual(stitched.cues[0].index, 1)
        XCTAssertEqual(stitched.cues[0].startMilliseconds, 10_000)        // shifted by the silent first segment
    }

    // MARK: - Edge cases

    func testEmptyInputYieldsEmptyDocument() {
        XCTAssertTrue(SRTStitcher.stitch([]).cues.isEmpty)
    }

    func testSingleSegmentIsUnchanged() {
        let stitched = SRTStitcher.stitch([
            Segment(durationMilliseconds: 10_000, document: doc(segment1SRT)),
        ])
        XCTAssertEqual(stitched.cues.count, 2)
        XCTAssertEqual(stitched.cues[0].startMilliseconds, 0)            // offset 0 for the first segment
        XCTAssertEqual(stitched.cues.map(\.index), [1, 2])
    }

    func testWallClockPreservedThroughStitch() {
        let withClock = """
        1
        00:00:00,000 --> 00:00:00,033
        2023-08-13 10:20:11.234

        """
        let stitched = SRTStitcher.stitch([
            Segment(durationMilliseconds: 5_000, document: doc(withClock)),
            Segment(durationMilliseconds: 5_000, document: doc(withClock)),
        ])
        // Re-timed (second cue offset by 5 s) but the embedded wall-clock is untouched.
        XCTAssertEqual(stitched.cues[1].startMilliseconds, 5_000)
        XCTAssertEqual(stitched.cues[1].wallClock?.year, 2023)
        XCTAssertEqual(stitched.cues[1].wallClock?.second, 11)
    }

    func testStitchToStringRoundTrips() {
        let segments = [
            Segment(durationMilliseconds: 10_000, document: doc(segment1SRT)),
            Segment(durationMilliseconds: 20_000, document: doc(segment2SRT)),
            Segment(durationMilliseconds: 15_000, document: doc(segment3SRT)),
        ]
        let text = SRTStitcher.stitchToString(segments)
        let reparsed = SRTParser.parse(text)
        XCTAssertEqual(reparsed.cues, SRTStitcher.stitch(segments).cues)
    }

    // MARK: - Integration (real ffprobe; skips without ffmpeg/ffprobe)

    func testProbeDurationAgainstRealFile() throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = dir.appendingPathComponent("two-seconds.mp4")
        try generateClip(ffmpeg: ffmpeg, seconds: 2, to: clip)

        let ms = try FFmpegWrapper().probeDurationMilliseconds(clip)
        XCTAssertEqual(Double(ms), 2_000, accuracy: 200, "expected ~2000 ms, got \(ms)")
    }

    func testStitchSRTEndToEndAlignsSecondSegment() throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let clip1 = dir.appendingPathComponent("a.mp4")
        let clip2 = dir.appendingPathComponent("b.mp4")
        try generateClip(ffmpeg: ffmpeg, seconds: 2, to: clip1)
        try generateClip(ffmpeg: ffmpeg, seconds: 3, to: clip2)

        let srt1 = dir.appendingPathComponent("a.srt")
        let srt2 = dir.appendingPathComponent("b.srt")
        try segment1SRT.write(to: srt1, atomically: true, encoding: .utf8)   // 2 cues, segment-relative
        try segment2SRT.write(to: srt2, atomically: true, encoding: .utf8)   // 1 cue at 0

        let text = try XCTUnwrap(FFmpegWrapper().stitchSRT(segments: [(clip1, srt1), (clip2, srt2)]))
        let cues = SRTParser.parse(text).cues

        XCTAssertEqual(cues.count, 3)
        XCTAssertEqual(cues.map(\.index), [1, 2, 3])
        // Clip 2's lone cue should land at ~clip 1's real duration (~2000 ms), proving the offset
        // came from decoded duration, not cue math.
        XCTAssertEqual(Double(cues[2].startMilliseconds), 2_000, accuracy: 250,
                       "second segment cue should be offset by clip 1's duration")
    }

    func testStitchSRTReturnsNilWhenNoSidecars() throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let clip = dir.appendingPathComponent("a.mp4")
        try generateClip(ffmpeg: ffmpeg, seconds: 1, to: clip)

        let text = try FFmpegWrapper().stitchSRT(segments: [(clip, nil)])
        XCTAssertNil(text)
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-srt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func generateClip(ffmpeg: URL, seconds: Int, to url: URL) throws {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=\(seconds):size=160x120:rate=30",
                       "-pix_fmt", "yuv420p", url.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ffmpeg failed to generate \(seconds)s clip")
    }
}
