import XCTest
import CoreMedia
@testable import Conjoyn

// MARK: - RecordingIntegrity tests (recordings-list inline flags)

/// Verifies the *display-only* per-recording integrity summary: that it flags missing / implausible /
/// inconsistent / slow-mo dates, names the signal Conjoyn substitutes, and stays in lock-step with the
/// resolver the engine stamps from. Clips point at non-existent videos, so the only I/O is the temp
/// `.SRT` fixtures (filesystem-date fallback is `nil`, as on a copied card).
final class RecordingIntegrityTests: XCTestCase {

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

    private func streamInfo(fps: String = "25/1") -> StreamParameterGuard.SegmentStreamInfo {
        .init(
            video: .init(
                codecName: "hevc", width: 3840, height: 2160,
                pixelFormat: "yuv420p", avgFrameRate: fps, timeBase: "1/25000"
            ),
            audio: nil
        )
    }

    /// A clip whose signals are individually toggleable. `filenameTS` controls whether the filename
    /// carries a parseable timestamp (17:39:05 on 2026-03-18); `creationDate` is the embedded date;
    /// `srtURL` an optional sidecar. `videoURL` doesn't exist → filesystem date resolves to `nil`.
    private func clip(
        filenameTS: Bool = true,
        creationDate: Date? = nil,
        srtURL: URL? = nil,
        fps: String = "25/1"
    ) -> DJIClip {
        var ts: DateComponents?
        if filenameTS {
            var c = DateComponents()
            c.year = 2026; c.month = 3; c.day = 18
            c.hour = 17; c.minute = 39; c.second = 5
            ts = c
        }
        return DJIClip(
            videoURL: URL(fileURLWithPath: "/nonexistent/DJI_20260318173905_0008_D.MP4"),
            srtURL: srtURL,
            index: 8,
            variantSuffix: "D",
            filenameTimestamp: ts,
            stem: "DJI_20260318173905_0008_D",
            creationDate: creationDate,
            duration: CMTime(value: 100, timescale: 1),
            streamInfo: streamInfo(fps: fps)
        )
    }

    private func group(_ clip: DJIClip, type: RecordGroup.GroupType = .single) -> RecordGroup {
        RecordGroup(clips: [clip], groupIndex: 1, groupType: type)
    }

    /// A sane capture instant (passes `RecordingStartResolver.isSane`).
    private func saneDate() -> Date {
        utc.date(from: {
            var c = DateComponents(); c.year = 2026; c.month = 3; c.day = 18
            c.hour = 17; c.minute = 39; c.second = 5; return c
        }())!
    }

    /// A date that fails the sanity gate (pre-2010 QuickTime-epoch artifact).
    private func insaneDate() -> Date { Date(timeIntervalSince1970: 0) }   // 1970

    private func writeSRT(_ text: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("integrity-\(UUID().uuidString).SRT")
        try! text.write(to: url, atomically: true, encoding: .utf8)
        tempFiles.append(url)
        return url
    }

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

    private func build(_ clip: DJIClip, settings: ConversionSettings = ConversionSettings()) async -> RecordingIntegrity {
        await RecordingIntegrity.build(group: group(clip), settings: settings, calendar: utc)
    }

    private func kinds(_ r: RecordingIntegrity) -> [RecordingIntegrity.Flag.Kind] { r.flags.map(\.kind) }

    // MARK: - Clean / date-origin

    func testCleanEmbeddedDateHasNoFlags() async {
        // Only a sane embedded date → it wins, nothing to flag.
        let r = await build(clip(filenameTS: false, creationDate: saneDate()))
        XCTAssertEqual(r.provenance, .embeddedCreationTime)
        XCTAssertTrue(r.flags.isEmpty)
        XCTAssertFalse(r.usedNonEmbeddedSignal)
        XCTAssertNil(r.originTag)
        XCTAssertEqual(r.resolvedDate, saneDate())
    }

    func testNoEmbeddedDateShowsOriginTagNotAChip() async {
        // No embedded date, filename present → resolved from filename. The origin is shown inline on
        // the date line (originTag), so it does NOT add a redundant chip.
        let r = await build(clip(filenameTS: true, creationDate: nil))
        XCTAssertEqual(r.provenance, .filename)
        XCTAssertTrue(r.usedNonEmbeddedSignal)
        XCTAssertEqual(r.originTag, "from filename")
        XCTAssertTrue(r.flags.isEmpty)
        XCTAssertFalse(r.hasWarning)
    }

    func testSaneEmbeddedButFilenamePreferredHasNoChip() async {
        // Both present & sane → filename outranks embedded; origin tag only, no chip.
        let r = await build(clip(filenameTS: true, creationDate: saneDate()))
        XCTAssertEqual(r.provenance, .filename)
        XCTAssertTrue(r.flags.isEmpty)
        XCTAssertEqual(r.originTag, "from filename")
        XCTAssertFalse(r.hasWarning)
    }

    // MARK: - Warnings

    func testNoSignalAtAllIsWarning() async {
        // No filename, no embedded, no SRT, non-existent file → nothing resolves.
        let r = await build(clip(filenameTS: false, creationDate: nil))
        XCTAssertEqual(r.provenance, .unavailable)
        XCTAssertNil(r.resolvedDate)
        XCTAssertEqual(kinds(r), [.noSignalAtAll])
        XCTAssertTrue(r.hasWarning)
    }

    func testUnusableEmbeddedDateFlaggedWhenSubstituteExists() async {
        // Implausible embedded date + a good filename signal → warn, resolve from filename.
        let r = await build(clip(filenameTS: true, creationDate: insaneDate()))
        XCTAssertEqual(r.provenance, .filename)
        XCTAssertEqual(kinds(r), [.embeddedDateUnusable(.filename)])
        XCTAssertTrue(r.hasWarning)
        XCTAssertEqual(r.resolvedDate, saneDate())
    }

    func testUnusableEmbeddedWithNoSubstituteIsNoSignalOnly() async {
        // Bad embedded date and nothing else → only the no-signal warning (no duplicate chip).
        let r = await build(clip(filenameTS: false, creationDate: insaneDate()))
        XCTAssertEqual(r.provenance, .unavailable)
        XCTAssertEqual(kinds(r), [.noSignalAtAll])
    }

    func testSrtFilenameMismatchFlaggedAboveThreshold() async {
        // SRT first cue 11 min after the filename instant (> 120 s) → warning, SRT wins.
        let srt = writeSRT(
            srtCue(1, startMs: 0, endMs: 40, wall: "2026-03-18 17:50:05,000")
            + "\n\n"
            + srtCue(2, startMs: 40, endMs: 80, wall: "2026-03-18 17:50:05,040")
        )
        let r = await build(clip(filenameTS: true, creationDate: nil, srtURL: srt))
        XCTAssertEqual(r.provenance, .srtFirstCue)
        let mismatch = r.flags.first { if case .srtFilenameMismatch = $0.kind { return true }; return false }
        let unwrapped = try? XCTUnwrap(mismatch)
        if case .srtFilenameMismatch(let delta)? = unwrapped?.kind {
            XCTAssertEqual(delta, 660, accuracy: 1)
        } else {
            XCTFail("expected srtFilenameMismatch flag")
        }
        XCTAssertTrue(r.hasWarning)
    }

    func testSrtFilenameWithinThresholdNotFlagged() async {
        // SRT cue 4 s from the filename instant (< 120 s) → no mismatch warning.
        let srt = writeSRT(
            srtCue(1, startMs: 0, endMs: 40, wall: "2026-03-18 17:39:09,000")
            + "\n\n"
            + srtCue(2, startMs: 40, endMs: 80, wall: "2026-03-18 17:39:09,040")
        )
        let r = await build(clip(filenameTS: true, creationDate: nil, srtURL: srt))
        XCTAssertFalse(r.flags.contains { if case .srtFilenameMismatch = $0.kind { return true }; return false })
    }

    // MARK: - Slow motion

    func testSlowMotionFlaggedFromSRT() async {
        // Playback span 4 s over a 1 s real span → slow-mo info flag.
        let srt = writeSRT(
            srtCue(1, startMs: 0,    endMs: 40,   wall: "2026-03-18 17:39:00,000")
            + "\n\n"
            + srtCue(2, startMs: 4000, endMs: 4040, wall: "2026-03-18 17:39:01,000")
        )
        let r = await build(clip(filenameTS: true, creationDate: nil, srtURL: srt))
        XCTAssertTrue(r.flags.contains { $0.kind == .slowMotionDualTimebase })
    }

    // MARK: - Manual override & ordering

    func testManualOverrideSuppressesMismatchAndOriginNoise() async {
        var settings = ConversionSettings()
        settings.dateOverride = saneDate()
        // Even with a divergent SRT, manual override wins and silences the source-data noise.
        let srt = writeSRT(
            srtCue(1, startMs: 0, endMs: 40, wall: "2026-03-18 17:50:05,000")
            + "\n\n"
            + srtCue(2, startMs: 40, endMs: 80, wall: "2026-03-18 17:50:05,040")
        )
        let r = await build(clip(filenameTS: true, creationDate: nil, srtURL: srt), settings: settings)
        XCTAssertEqual(r.provenance, .manualOverride)
        XCTAssertTrue(r.flags.isEmpty)
        XCTAssertEqual(r.originTag, "manual")
    }

    func testFlagsAreSeverityOrderedWarningBeforeInfo() async {
        // Bad embedded date (warning) + no embedded substitute origin info would not both apply;
        // use mismatch (warning) + slow-mo (info) which co-occur, and assert ordering.
        let srt = writeSRT(
            srtCue(1, startMs: 0,    endMs: 40,   wall: "2026-03-18 17:50:00,000")
            + "\n\n"
            + srtCue(2, startMs: 8000, endMs: 8040, wall: "2026-03-18 17:50:02,000")
        )
        let r = await build(clip(filenameTS: true, creationDate: nil, srtURL: srt))
        XCTAssertGreaterThanOrEqual(r.flags.count, 2)
        let firstInfo = r.flags.firstIndex { $0.severity == .info }
        let lastWarning = r.flags.lastIndex { $0.severity == .warning }
        if let firstInfo, let lastWarning {
            XCTAssertLessThan(lastWarning, firstInfo, "warnings must precede info flags")
        } else {
            XCTFail("expected both a warning and an info flag")
        }
    }

    func testEmptyGroupHasNoFlags() async {
        let r = await RecordingIntegrity.build(
            group: RecordGroup(clips: [], groupIndex: 1, groupType: .single),
            settings: ConversionSettings(), calendar: utc
        )
        XCTAssertTrue(r.flags.isEmpty)
        XCTAssertNil(r.resolvedDate)
        XCTAssertEqual(r.provenance, .unavailable)
    }

    // MARK: - Delta formatter

    func testFormatDelta() {
        XCTAssertEqual(RecordingIntegrity.formatDelta(45), "45 s")
        XCTAssertEqual(RecordingIntegrity.formatDelta(120), "2 min")
        XCTAssertEqual(RecordingIntegrity.formatDelta(3600), "1 h")
        XCTAssertEqual(RecordingIntegrity.formatDelta(3840), "1 h 4 min")
    }
}
