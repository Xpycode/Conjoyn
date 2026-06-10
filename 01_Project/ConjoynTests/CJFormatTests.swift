import XCTest
@testable import Conjoyn

/// Pure-function coverage for the display formatters used by the recordings rows.
final class CJFormatTests: XCTestCase {

    // MARK: codec

    func testCodecPrettifiesKnownNames() {
        XCTAssertEqual(CJFormat.codec("hevc"), "HEVC")
        XCTAssertEqual(CJFormat.codec("h265"), "HEVC")
        XCTAssertEqual(CJFormat.codec("h264"), "H.264")
        XCTAssertEqual(CJFormat.codec("avc1"), "H.264")
    }

    func testCodecIsCaseInsensitive() {
        XCTAssertEqual(CJFormat.codec("HEVC"), "HEVC")
        XCTAssertEqual(CJFormat.codec("H264"), "H.264")
    }

    func testCodecUppercasesUnknownVerbatim() {
        XCTAssertEqual(CJFormat.codec("prores"), "PRORES")
        XCTAssertEqual(CJFormat.codec("av1"), "AV1")
    }

    // MARK: resolution

    func testResolutionUsesMultiplicationSign() {
        XCTAssertEqual(CJFormat.resolution(width: 3840, height: 2160), "3840×2160")
        XCTAssertEqual(CJFormat.resolution(width: 1920, height: 1080), "1920×1080")
    }

    // MARK: fps

    func testFpsWholeNumberHasNoDecimals() {
        XCTAssertEqual(CJFormat.fps(25), "25 fps")
        XCTAssertEqual(CJFormat.fps(30), "30 fps")
    }

    func testFpsFractionalShowsTwoDecimals() {
        // 30000/1001 ≈ 29.97
        XCTAssertEqual(CJFormat.fps(30000.0 / 1001.0), "29.97 fps")
    }

    func testFpsNilIsEmpty() {
        XCTAssertEqual(CJFormat.fps(nil), "")
    }
}
