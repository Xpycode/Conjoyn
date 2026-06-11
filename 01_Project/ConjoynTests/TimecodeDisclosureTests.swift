import XCTest
import CoreMedia
@testable import Conjoyn

// MARK: - TimecodeDisclosure tests (rename-and-tc-disclosure, Part 2)

/// Verifies the *display-only* timecode disclosure: that it carries the same applied TC + origin the
/// engine stamps (resolver passthrough), and that slow-mo detection keys off the SRT playback-vs-real
/// span ratio. Source-`tmcd` reading is exercised indirectly — these clips point at non-existent
/// videos, so `SourceTimecodeReader` throws and `sourceTimecode` is `nil` (the normal DJI case).
final class TimecodeDisclosureTests: XCTestCase {

    /// Fixed UTC calendar so wall-clock components map to predictable instants regardless of zone.
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private var tempFiles: [URL] = []

    override func tearDownWithError() throws {
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        tempFiles = []
    }

    // MARK: - Fixtures

    /// 25 fps stream params, so the applied frame component and fps label are predictable.
    private func streamInfo(fps: String = "25/1") -> StreamParameterGuard.SegmentStreamInfo {
        .init(
            video: .init(
                codecName: "hevc", width: 3840, height: 2160,
                pixelFormat: "yuv420p", avgFrameRate: fps, timeBase: "1/25000"
            ),
            audio: nil
        )
    }

    /// A clip with a filename timestamp (no SRT unless `srtURL` is provided). `videoURL` points at a
    /// path that doesn't exist → the source-tmcd read throws → `sourceTimecode == nil`.
    private func clip(
        hour: Int = 17, minute: Int = 39, second: Int = 5,
        srtURL: URL? = nil,
        fps: String = "25/1"
    ) -> DJIClip {
        var ts = DateComponents()
        ts.year = 2026; ts.month = 3; ts.day = 18
        ts.hour = hour; ts.minute = minute; ts.second = second
        return DJIClip(
            videoURL: URL(fileURLWithPath: "/nonexistent/DJI_20260318173905_0008_D.MP4"),
            srtURL: srtURL,
            index: 8,
            variantSuffix: "D",
            filenameTimestamp: ts,
            stem: "DJI_20260318173905_0008_D",
            duration: CMTime(value: 100, timescale: 1),
            streamInfo: streamInfo(fps: fps)
        )
    }

    private func writeSRT(_ text: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("tc-disclosure-\(UUID().uuidString).SRT")
        try! text.write(to: url, atomically: true, encoding: .utf8)
        tempFiles.append(url)
        return url
    }

    /// One DJI modern-bracketed cue with a wall-clock line. `startMs` is the cue's playback-time
    /// start; `wall` is the embedded real-capture wall-clock.
    private func srtCue(_ index: Int, startMs: Int, endMs: Int, wall: String) -> String {
        func tc(_ ms: Int) -> String {
            let h = ms / 3_600_000, m = (ms / 60_000) % 60, s = (ms / 1000) % 60, mil = ms % 1000
            return String(format: "%02d:%02d:%02d,%03d", h, m, s, mil)
        }
        return """
        \(index)
        \(tc(startMs)) --> \(tc(endMs))
        <font size="28">FrameCnt: \(index), DiffTime: 40ms
        \(wall)
        [iso: 100] [latitude: 40.0] [longitude: 8.0]</font>
        """
    }

    // MARK: - Resolver passthrough

    func testAppliedTimecodeMatchesFilenameResolution() async {
        // No SRT → resolver falls to the filename datetime; 17:39:05 at 25 fps → frame 00.
        let d = await TimecodeDisclosure.build(
            clips: [clip()], settings: ConversionSettings(), calendar: utc
        )
        XCTAssertEqual(d.origin, .filename)
        XCTAssertEqual(d.appliedTimecode, "17:39:05:00")
        XCTAssertEqual(d.frameRate, 25)
        XCTAssertEqual(d.frameRateLabel, "25")
        XCTAssertEqual(d.originTag, "from filename")
        XCTAssertTrue(d.timecodeEnabled)
        XCTAssertNil(d.sourceTimecode)   // nonexistent video → no tmcd track
    }

    func testSRTFirstCueWinsOverFilename() async {
        // SRT first cue at 17:39:07.480 → frame floor(0.48*25)=12, origin srtCue.
        let srt = writeSRT(
            srtCue(1, startMs: 0, endMs: 40, wall: "2026-03-18 17:39:07,480")
            + "\n\n"
            + srtCue(2, startMs: 40, endMs: 80, wall: "2026-03-18 17:39:07,520")
        )
        let d = await TimecodeDisclosure.build(
            clips: [clip(srtURL: srt)], settings: ConversionSettings(), calendar: utc
        )
        XCTAssertEqual(d.origin, .srtFirstCue)
        XCTAssertEqual(d.appliedTimecode, "17:39:07:12")
        XCTAssertEqual(d.originTag, "from SRT cue")
    }

    func testTimecodeDisabledYieldsNoAppliedTimecode() async {
        var settings = ConversionSettings()
        settings.preserveTimecode = false
        let d = await TimecodeDisclosure.build(
            clips: [clip()], settings: settings, calendar: utc
        )
        XCTAssertFalse(d.timecodeEnabled)
        XCTAssertNil(d.appliedTimecode)
        XCTAssertEqual(d.origin, .filename)   // resolution still computed, just not applied
    }

    func testManualOverrideWinsAndTagsManual() async {
        var settings = ConversionSettings()
        settings.dateOverride = utc.date(from: {
            var c = DateComponents(); c.year = 2020; c.month = 1; c.day = 2
            c.hour = 3; c.minute = 4; c.second = 5; return c
        }())
        let d = await TimecodeDisclosure.build(
            clips: [clip()], settings: settings, calendar: utc
        )
        XCTAssertEqual(d.origin, .manualOverride)
        XCTAssertEqual(d.originTag, "manual")
        XCTAssertEqual(d.appliedTimecode, "03:04:05:00")
    }

    // MARK: - tcOverride parameter (manual TC string override)

    /// A non-nil `tcOverride` wins over all resolver logic and stamps `origin: .manualOverride`.
    func testTCOverrideWinsOverResolverAndTagsManual() async {
        let overrideString = "10:20:30:05"
        // Clip has a filename timestamp that would normally resolve to origin .filename.
        // The tcOverride must take precedence.
        let d = await TimecodeDisclosure.build(
            clips: [clip()], settings: ConversionSettings(), tcOverride: overrideString, calendar: utc
        )
        XCTAssertEqual(d.appliedTimecode, overrideString)
        XCTAssertEqual(d.origin, .manualOverride)
        XCTAssertEqual(d.originTag, "manual")
    }

    /// Passing `tcOverride: nil` leaves the normal resolver path untouched — regression guard.
    func testNilTCOverrideFallsThroughToResolver() async {
        // No SRT → resolver falls to filename datetime; 17:39:05 at 25 fps → frame 00.
        let d = await TimecodeDisclosure.build(
            clips: [clip()], settings: ConversionSettings(), tcOverride: nil, calendar: utc
        )
        XCTAssertEqual(d.origin, .filename)
        XCTAssertEqual(d.appliedTimecode, "17:39:05:00")
        XCTAssertNotEqual(d.origin, .manualOverride)
    }

    /// `originTag` for `.manualOverride` is "manual" — guards the constant stays in sync.
    func testManualOverrideOriginTagIsManual() {
        let d = TimecodeDisclosure(
            sourceTimecode: nil,
            appliedTimecode: "01:02:03:04",
            origin: .manualOverride,
            frameRate: 25,
            timecodeEnabled: true,
            isSlowMotion: false
        )
        XCTAssertEqual(d.originTag, "manual")
    }

    func testEmptyClipsResolvesToUnavailable() async {
        let d = await TimecodeDisclosure.build(clips: [], settings: ConversionSettings(), calendar: utc)
        XCTAssertEqual(d.origin, .unavailable)
        XCTAssertNil(d.appliedTimecode)
        XCTAssertFalse(d.isSlowMotion)
    }

    // MARK: - Slow-motion detection

    func testSlowMotionDetectedWhenPlaybackSpanExceedsRealSpan() {
        // Playback span 4 s (0 → 4000 ms); real wall-clock span 1 s → ratio 4 ≥ 1.5 → slow-mo.
        let srt = writeSRT(
            srtCue(1, startMs: 0,    endMs: 40,   wall: "2026-03-18 17:39:00,000")
            + "\n\n"
            + srtCue(2, startMs: 4000, endMs: 4040, wall: "2026-03-18 17:39:01,000")
        )
        XCTAssertTrue(TimecodeDisclosure.detectSlowMotion(clip: clip(srtURL: srt), calendar: utc))
    }

    func testNormalSpeedNotFlaggedSlowMotion() {
        // Playback span ≈ real span (both ~2 s) → ratio ~1.0 → not slow-mo.
        let srt = writeSRT(
            srtCue(1, startMs: 0,    endMs: 40,   wall: "2026-03-18 17:39:00,000")
            + "\n\n"
            + srtCue(2, startMs: 2000, endMs: 2040, wall: "2026-03-18 17:39:02,000")
        )
        XCTAssertFalse(TimecodeDisclosure.detectSlowMotion(clip: clip(srtURL: srt), calendar: utc))
    }

    func testNoSRTIsNotSlowMotion() {
        XCTAssertFalse(TimecodeDisclosure.detectSlowMotion(clip: clip(srtURL: nil), calendar: utc))
    }

    // MARK: - SourceTimecodeReader frame math (TN2310, no footage needed)

    func testSourceTimecodeFrameMathNonDropFrame() {
        // 25 fps, frame 1561 = 00:01:02:11 (1561 = 62*25 + 11).
        let tc = SourceTimecodeReader.timecode(forFrameNumber: 1561, frameQuanta: 25, isDropFrame: false)
        XCTAssertEqual(tc.hours, 0)
        XCTAssertEqual(tc.minutes, 1)
        XCTAssertEqual(tc.seconds, 2)
        XCTAssertEqual(tc.frames, 11)
    }
}
