import XCTest
@testable import Conjoyn

final class FFmpegOutputParsingTests: XCTestCase {

    // task 1.6 backpressure: parses a sample ffmpeg progress line
    func testParsesProgressLine() {
        let wrapper = FFmpegWrapper()
        let line = "frame=  123 fps= 24.5 q=28.0 size=    1234kB time=00:01:23.45 bitrate= 123.4kbits/s speed=12.3x"
        let m = wrapper.parseFFmpegOutput(line)

        XCTAssertEqual(m.frame, 123)
        XCTAssertEqual(m.fps ?? 0, 24.5, accuracy: 0.001)
        XCTAssertEqual(m.speed, "12.3x")
        XCTAssertEqual(m.time, "00:01:23.45")
        XCTAssertNotNil(m.bitrate)
        XCTAssertNotNil(m.size)
    }

    func testSpeedNAIsIgnored() {
        let wrapper = FFmpegWrapper()
        let m = wrapper.parseFFmpegOutput("frame=   1 fps=0.0 q=0.0 size=0kB time=00:00:00.00 bitrate=N/A speed=N/A")
        XCTAssertEqual(m.frame, 1)
        XCTAssertNil(m.speed)            // "N/A" must not be captured as a speed
    }

    func testNoMatchYieldsEmptyMetrics() {
        let wrapper = FFmpegWrapper()
        let m = wrapper.parseFFmpegOutput("ffmpeg version 8.1 Copyright (c) the FFmpeg developers")
        XCTAssertNil(m.frame)
        XCTAssertNil(m.speed)
    }
}
