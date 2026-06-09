import XCTest
@testable import DJIjoiner

final class SRTParserTests: XCTestCase {

    typealias Cue = SRTParser.Cue

    // MARK: - Variant 1: modern bracketed (DJI Fly — Mavic 3 / Air 2S / Mini 3)

    /// `<font>`-wrapped block with FrameCnt/DiffTime, a dotted-fraction wall-clock, and
    /// space-separated `[key: value]` telemetry pairs.
    private let modernBracketed = """
    1
    00:00:00,000 --> 00:00:00,033
    <font size="28">FrameCnt: 1, DiffTime: 33ms
    2023-08-13 10:20:11.234
    [iso: 100] [shutter: 1/500.0] [fnum: 2.8] [ev: 0] [focal_len: 24.00] [latitude: 40.123456] [longitude: -74.123456] [rel_alt: 1.300 abs_alt: 100.500]</font>

    2
    00:00:00,033 --> 00:00:00,066
    <font size="28">FrameCnt: 2, DiffTime: 33ms
    2023-08-13 10:20:11.267
    [iso: 100] [shutter: 1/500.0] [fnum: 2.8] [ev: 0] [focal_len: 24.00] [latitude: 40.123457] [longitude: -74.123455] [rel_alt: 1.350 abs_alt: 100.550]</font>

    """

    func testModernBracketedParsesBothCues() {
        let doc = SRTParser.parse(modernBracketed)
        XCTAssertEqual(doc.cues.count, 2)

        let first = doc.cues[0]
        XCTAssertEqual(first.index, 1)
        XCTAssertEqual(first.startMilliseconds, 0)
        XCTAssertEqual(first.endMilliseconds, 33)

        let second = doc.cues[1]
        XCTAssertEqual(second.index, 2)
        XCTAssertEqual(second.startMilliseconds, 33)
        XCTAssertEqual(second.endMilliseconds, 66)
    }

    func testModernBracketedPayloadPreservedVerbatim() {
        let doc = SRTParser.parse(modernBracketed)
        let expected = """
        <font size="28">FrameCnt: 1, DiffTime: 33ms
        2023-08-13 10:20:11.234
        [iso: 100] [shutter: 1/500.0] [fnum: 2.8] [ev: 0] [focal_len: 24.00] [latitude: 40.123456] [longitude: -74.123456] [rel_alt: 1.300 abs_alt: 100.500]</font>
        """
        XCTAssertEqual(doc.cues.first?.payload, expected)
    }

    func testModernBracketedWallClockWithMilliseconds() {
        let wc = SRTParser.parse(modernBracketed).cues.first?.wallClock
        XCTAssertEqual(wc?.year, 2023)
        XCTAssertEqual(wc?.month, 8)
        XCTAssertEqual(wc?.day, 13)
        XCTAssertEqual(wc?.hour, 10)
        XCTAssertEqual(wc?.minute, 20)
        XCTAssertEqual(wc?.second, 11)
        XCTAssertEqual(wc?.nanosecond, 234_000_000)
    }

    // MARK: - Variant 2: FrameCnt/DiffTime + wall-clock (Mavic 2 / Phantom 4), comma fractions

    private let frameCntWallClock = """
    1
    00:00:00,000 --> 00:00:00,016
    FrameCnt : 1, DiffTime : 16ms
    2017-09-08 14:38:30,234,567
    [iso : 200] [shutter : 1/200] [fnum : 280] [ev : 0] [ct : 5491] [latitude : 0.000000] [longitude : 0.000000] [altitude : 0.000000]

    """

    func testFrameCntVariantTiming() {
        let doc = SRTParser.parse(frameCntWallClock)
        XCTAssertEqual(doc.cues.count, 1)
        XCTAssertEqual(doc.cues.first?.startMilliseconds, 0)
        XCTAssertEqual(doc.cues.first?.endMilliseconds, 16)
    }

    func testFrameCntVariantWallClockCommaFraction() {
        // Comma sub-second groups: only the first (milliseconds) is taken.
        let wc = SRTParser.parse(frameCntWallClock).cues.first?.wallClock
        XCTAssertEqual(wc?.year, 2017)
        XCTAssertEqual(wc?.month, 9)
        XCTAssertEqual(wc?.day, 8)
        XCTAssertEqual(wc?.hour, 14)
        XCTAssertEqual(wc?.minute, 38)
        XCTAssertEqual(wc?.second, 30)
        XCTAssertEqual(wc?.nanosecond, 234_000_000)
    }

    func testFrameCntVariantPayloadVerbatim() {
        let expected = """
        FrameCnt : 1, DiffTime : 16ms
        2017-09-08 14:38:30,234,567
        [iso : 200] [shutter : 1/200] [fnum : 280] [ev : 0] [ct : 5491] [latitude : 0.000000] [longitude : 0.000000] [altitude : 0.000000]
        """
        XCTAssertEqual(SRTParser.parse(frameCntWallClock).cues.first?.payload, expected)
    }

    // MARK: - Variant 3: legacy GPS()/HOME() with dotted-date wall-clock (Phantom 3 / early Mavic)

    private let legacyGPS = """
    1
    00:00:00,000 --> 00:00:00,033
    HOME(120.000000,30.000000) 2016.08.15 14:38:50
    GPS(120.000001,30.000002,14) BAROMETER:50.40
    ISO:100 Shutter:240 EV:0 Fnum:F2.8

    """

    func testLegacyVariantTiming() {
        let doc = SRTParser.parse(legacyGPS)
        XCTAssertEqual(doc.cues.count, 1)
        XCTAssertEqual(doc.cues.first?.startMilliseconds, 0)
        XCTAssertEqual(doc.cues.first?.endMilliseconds, 33)
    }

    func testLegacyVariantDottedDateWallClockNoFraction() {
        let wc = SRTParser.parse(legacyGPS).cues.first?.wallClock
        XCTAssertEqual(wc?.year, 2016)
        XCTAssertEqual(wc?.month, 8)
        XCTAssertEqual(wc?.day, 15)
        XCTAssertEqual(wc?.hour, 14)
        XCTAssertEqual(wc?.minute, 38)
        XCTAssertEqual(wc?.second, 50)
        XCTAssertNil(wc?.nanosecond)   // no sub-second digits in the legacy wall-clock
    }

    func testLegacyVariantPayloadVerbatim() {
        let expected = """
        HOME(120.000000,30.000000) 2016.08.15 14:38:50
        GPS(120.000001,30.000002,14) BAROMETER:50.40
        ISO:100 Shutter:240 EV:0 Fnum:F2.8
        """
        XCTAssertEqual(SRTParser.parse(legacyGPS).cues.first?.payload, expected)
    }

    // MARK: - Tolerances

    func testTolerateUTF8BOM() {
        let withBOM = "\u{FEFF}" + modernBracketed
        XCTAssertEqual(SRTParser.parse(withBOM).cues.count, 2)
        XCTAssertEqual(SRTParser.parse(withBOM).cues.first?.index, 1)
    }

    func testTolerateCRLFLineEndings() {
        let crlf = modernBracketed.replacingOccurrences(of: "\n", with: "\r\n")
        let doc = SRTParser.parse(crlf)
        XCTAssertEqual(doc.cues.count, 2)
        // Payload carries no stray carriage returns after normalization.
        XCTAssertFalse(doc.cues.first?.payload.contains("\r") ?? true)
        XCTAssertEqual(doc.cues.first?.endMilliseconds, 33)
    }

    func testTolerateLoneCRLineEndings() {
        let cr = modernBracketed.replacingOccurrences(of: "\n", with: "\r")
        XCTAssertEqual(SRTParser.parse(cr).cues.count, 2)
    }

    func testTolerateDotMillisecondSeparator() {
        // Some tools write `00:00:01.500` instead of the SubRip-standard comma.
        let dotted = """
        1
        00:00:01.500 --> 00:00:02.000
        payload

        """
        let cue = SRTParser.parse(dotted).cues.first
        XCTAssertEqual(cue?.startMilliseconds, 1500)
        XCTAssertEqual(cue?.endMilliseconds, 2000)
    }

    func testMissingIndexLineFallsBackToPosition() {
        // No numeric index line before the timecode — position (1-based) is used.
        let noIndex = """
        00:00:00,000 --> 00:00:00,033
        first

        00:00:00,033 --> 00:00:00,066
        second

        """
        let cues = SRTParser.parse(noIndex).cues
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].index, 1)
        XCTAssertEqual(cues[1].index, 2)
    }

    func testHourComponentInTimecode() {
        let withHours = """
        1
        01:02:03,400 --> 01:02:04,500
        payload

        """
        let cue = SRTParser.parse(withHours).cues.first
        XCTAssertEqual(cue?.startMilliseconds, (1 * 3600 + 2 * 60 + 3) * 1000 + 400)
        XCTAssertEqual(cue?.endMilliseconds, (1 * 3600 + 2 * 60 + 4) * 1000 + 500)
    }

    func testMalformedBlocksAreSkippedNotFatal() {
        let mixed = """
        garbage with no timecode at all

        1
        00:00:00,000 --> 00:00:00,033
        good cue

        also no arrow here

        """
        let cues = SRTParser.parse(mixed).cues
        XCTAssertEqual(cues.count, 1)
        XCTAssertEqual(cues.first?.payload, "good cue")
    }

    func testEmptyAndNonSRTInputYieldNoCues() {
        XCTAssertTrue(SRTParser.parse("").cues.isEmpty)
        XCTAssertTrue(SRTParser.parse("   \n\n  ").cues.isEmpty)
        XCTAssertTrue(SRTParser.parse("just some prose\nwith no cues").cues.isEmpty)
    }

    func testPayloadWithoutWallClockHasNilWallClock() {
        let cue = SRTParser.parse("""
        1
        00:00:00,000 --> 00:00:00,033
        no date here, just [iso: 100]

        """).cues.first
        XCTAssertNotNil(cue)
        XCTAssertNil(cue?.wallClock)
    }

    // MARK: - Serialization round-trip (supports the stitcher, task 3.2)

    func testSerializeProducesParseableSRT() {
        let original = SRTParser.parse(modernBracketed)
        let roundTripped = SRTParser.parse(SRTParser.serialize(original.cues))
        XCTAssertEqual(roundTripped.cues, original.cues)
    }

    func testFormatTimecode() {
        XCTAssertEqual(SRTParser.formatTimecode(0), "00:00:00,000")
        XCTAssertEqual(SRTParser.formatTimecode(33), "00:00:00,033")
        XCTAssertEqual(SRTParser.formatTimecode(1500), "00:00:01,500")
        XCTAssertEqual(SRTParser.formatTimecode((1 * 3600 + 2 * 60 + 3) * 1000 + 400), "01:02:03,400")
    }
}
