import XCTest
@testable import Conjoyn

final class TimecodeTests: XCTestCase {

    // MARK: - frameGap continuity (task 1.1 backpressure)

    func testFrameGapContinuous() {
        // 10s in @25fps, 10s clip (250 frames), next starts exactly at 20s → gap 0
        let tc1 = Timecode(string: "00:00:10:00", frameRate: 25)!
        let tc2 = Timecode(string: "00:00:20:00", frameRate: 25)!
        XCTAssertEqual(Timecode.frameGap(from: tc1, duration1Frames: 250, to: tc2), 0)
    }

    func testFrameGapPositiveGap() {
        // Next clip starts 1s (25 frames) later than expected → missing frames
        let tc1 = Timecode(string: "00:00:10:00", frameRate: 25)!
        let tc2 = Timecode(string: "00:00:21:00", frameRate: 25)!
        XCTAssertEqual(Timecode.frameGap(from: tc1, duration1Frames: 250, to: tc2), 25)
    }

    func testFrameGapOverlap() {
        // Next clip starts 1s (25 frames) earlier than expected → overlap (negative)
        let tc1 = Timecode(string: "00:00:10:00", frameRate: 25)!
        let tc2 = Timecode(string: "00:00:19:00", frameRate: 25)!
        XCTAssertEqual(Timecode.frameGap(from: tc1, duration1Frames: 250, to: tc2), -25)
    }

    // MARK: - totalFrames / from(frames:) round trip

    func testTotalFramesAndRoundTrip() {
        let tc = Timecode(string: "01:02:03:04", frameRate: 25)!
        // 1h*90000 + 2m*1500 + 3s*25 + 4 = 90000+3000+75+4 = 93079
        XCTAssertEqual(tc.totalFrames, 93079)
        let rebuilt = Timecode.from(frames: 93079, frameRate: 25)
        XCTAssertEqual(rebuilt.description, "01:02:03:04")
    }

    func testNTSCRoundedFrameRate() {
        // 29.97 rounds to 30 for bucketing
        let tc = Timecode(hours: 0, minutes: 0, seconds: 1, frames: 0, frameRate: 29.97)
        XCTAssertEqual(tc.totalFrames, 30)
    }

    func testInvalidStringFailsToParse() {
        XCTAssertNil(Timecode(string: "1:2:3", frameRate: 25))   // only 3 components
        XCTAssertNil(Timecode(string: "ab:cd:ef:gh", frameRate: 25))
    }
}
