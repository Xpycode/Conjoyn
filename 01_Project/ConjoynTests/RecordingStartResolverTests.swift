import XCTest
@testable import Conjoyn

// MARK: - RecordingStartResolver + formatter tests (Wave 2, task 2.8)

final class RecordingStartResolverTests: XCTestCase {

    /// A fixed UTC calendar so wall-clock components map to predictable absolute instants in tests
    /// (independent of the machine's zone).
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// `2026-03-18 17:39:05` as components (no zone).
    private func comps(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int,
                       ns: Int? = nil) -> DateComponents {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s
        c.nanosecond = ns
        return c
    }

    /// Absolute date helper in UTC.
    private func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int) -> Date {
        utc.date(from: comps(y, mo, d, h, mi, s))!
    }

    // MARK: - Priority order

    func testManualOverrideWinsOverEverything() {
        let override = date(2020, 1, 1, 12, 0, 0)
        let r = RecordingStartResolver.resolve(
            srtWallClock: comps(2026, 3, 18, 17, 39, 5),
            filenameTimestamp: comps(2026, 3, 18, 17, 39, 5),
            embeddedCreationTime: date(2026, 3, 18, 16, 39, 5),
            filesystemDate: date(2026, 3, 18, 16, 39, 5),
            manualOverride: override,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .manualOverride)
        XCTAssertEqual(r.date, override)
    }

    func testSRTBeatsFilenameAndEmbedded() {
        let r = RecordingStartResolver.resolve(
            srtWallClock: comps(2026, 3, 18, 17, 39, 5),
            filenameTimestamp: comps(2026, 3, 18, 17, 39, 9),
            embeddedCreationTime: date(2000, 1, 1, 0, 0, 0),
            filesystemDate: nil,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .srtFirstCue)
        XCTAssertEqual(r.date, date(2026, 3, 18, 17, 39, 5))
    }

    func testFilenameUsedWhenNoSRT() {
        let r = RecordingStartResolver.resolve(
            srtWallClock: nil,
            filenameTimestamp: comps(2026, 3, 18, 17, 39, 5),
            embeddedCreationTime: nil,
            filesystemDate: nil,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .filename)
        XCTAssertEqual(r.date, date(2026, 3, 18, 17, 39, 5))
    }

    func testEmbeddedUsedWhenSaneAndNoWallClock() {
        let embedded = date(2026, 3, 18, 16, 39, 5)
        let r = RecordingStartResolver.resolve(
            srtWallClock: nil,
            filenameTimestamp: nil,
            embeddedCreationTime: embedded,
            filesystemDate: date(2026, 3, 18, 16, 0, 0),
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .embeddedCreationTime)
        XCTAssertEqual(r.date, embedded)
    }

    func testInsaneEmbeddedFallsThroughToFilesystem() {
        let bogus1904 = Date(timeIntervalSince1970: -2_082_844_800)   // 1904-01-01
        let fs = date(2026, 3, 18, 16, 0, 0)
        let r = RecordingStartResolver.resolve(
            srtWallClock: nil,
            filenameTimestamp: nil,
            embeddedCreationTime: bogus1904,
            filesystemDate: fs,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .filesystem)
        XCTAssertEqual(r.date, fs)
    }

    func testNothingResolvesToUnavailable() {
        let r = RecordingStartResolver.resolve(
            srtWallClock: nil,
            filenameTimestamp: nil,
            embeddedCreationTime: nil,
            filesystemDate: nil,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .unavailable)
        XCTAssertNil(r.date)
        XCTAssertFalse(r.isResolved)
    }

    // MARK: - Sanity gate

    func testInsaneEmbeddedAndFilesystemYieldUnavailable() {
        let bogus1951 = Date(timeIntervalSince1970: -567_993_600)     // ~1952, still < 2010 floor
        let r = RecordingStartResolver.resolve(
            srtWallClock: nil,
            filenameTimestamp: nil,
            embeddedCreationTime: bogus1951,
            filesystemDate: bogus1951,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .unavailable)
    }

    func testFarFutureRejected() {
        let now = date(2026, 3, 18, 12, 0, 0)
        let far = date(2030, 1, 1, 0, 0, 0)
        XCTAssertFalse(RecordingStartResolver.isSane(far, now: now))
        XCTAssertTrue(RecordingStartResolver.isSane(date(2026, 3, 18, 11, 0, 0), now: now))
    }

    // MARK: - Mismatch detection

    func testMismatchFlaggedWhenWallClocksDiverge() throws {
        let r = RecordingStartResolver.resolve(
            srtWallClock: comps(2026, 3, 18, 17, 39, 5),
            filenameTimestamp: comps(2026, 3, 18, 17, 49, 5),   // 10 min apart
            embeddedCreationTime: nil,
            filesystemDate: nil,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .srtFirstCue)   // SRT still wins
        let mismatch = try XCTUnwrap(r.mismatch)
        XCTAssertEqual(mismatch.deltaSeconds, 600, accuracy: 0.5)
    }

    func testNoMismatchWhenWallClocksAgreeWithinTolerance() {
        let r = RecordingStartResolver.resolve(
            srtWallClock: comps(2026, 3, 18, 17, 39, 5),
            filenameTimestamp: comps(2026, 3, 18, 17, 39, 9),   // 4 s apart < 120 s
            embeddedCreationTime: nil,
            filesystemDate: nil,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertNil(r.mismatch)
    }

    // MARK: - Incomplete components

    func testPartialComponentsDoNotResolve() {
        var partial = DateComponents()
        partial.year = 2026; partial.month = 3; partial.day = 18   // no time
        let r = RecordingStartResolver.resolve(
            srtWallClock: partial,
            filenameTimestamp: nil,
            embeddedCreationTime: nil,
            filesystemDate: nil,
            manualOverride: nil,
            calendar: utc
        )
        XCTAssertEqual(r.provenance, .unavailable)
    }
}

// MARK: - TimecodeFormatter / ISO8601Z

final class RecordingDateFormattingTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    private func utcDate(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int,
                         ns: Int = 0) -> Date {
        var c = DateComponents()
        c.year = y; c.month = mo; c.day = d; c.hour = h; c.minute = mi; c.second = s; c.nanosecond = ns
        return utc.date(from: c)!
    }

    func testWallClockTimecodeWholeSecond() throws {
        let tc = try TimecodeFormatter.wallClockTimecode(
            for: utcDate(2026, 3, 18, 17, 39, 5),
            frameRate: 30, isDropFrame: false, calendar: utc
        )
        XCTAssertEqual(tc, "17:39:05:00")
    }

    func testWallClockTimecodeSubsecondFrame() throws {
        // 0.5 s at 30 fps → frame 15.
        let tc = try TimecodeFormatter.wallClockTimecode(
            for: utcDate(2026, 3, 18, 17, 39, 5, ns: 500_000_000),
            frameRate: 30, isDropFrame: false, calendar: utc
        )
        XCTAssertEqual(tc, "17:39:05:15")
    }

    func testDropFrameOnUnsupportedRateThrows() {
        XCTAssertThrowsError(try TimecodeFormatter.wallClockTimecode(
            for: utcDate(2026, 3, 18, 17, 39, 5),
            frameRate: 30, isDropFrame: true, calendar: utc
        )) { error in
            XCTAssertEqual(error as? TimecodeFormatter.TimecodeError,
                           .dropFrameOnUnsupportedRate(rate: 30))
        }
    }

    func testDropFrameAllowedAt2997() throws {
        let tc = try TimecodeFormatter.wallClockTimecode(
            for: utcDate(2026, 3, 18, 17, 39, 5),
            frameRate: 29.97, isDropFrame: true, calendar: utc
        )
        XCTAssertEqual(tc, "17:39:05;00")
    }

    func testISO8601ZFormatsUTC() {
        let s = ISO8601Z.format(utcDate(2026, 3, 18, 16, 39, 5, ns: 0))
        XCTAssertEqual(s, "2026-03-18T16:39:05.000Z")
    }
}
