import XCTest
@testable import Conjoyn

// MARK: - RenamePatternEngine tests (output-name templating)

/// Covers the 1:1 port of the handoff's `cjApplyPattern` (token replace / illegal-char strip /
/// empty→fallback / per-batch counter) plus the `uniqueStem` collision suffixer. Dates use a fixed
/// UTC calendar so wall-clock components map to predictable strings regardless of the test host's
/// zone.
final class RenamePatternEngineTests: XCTestCase {

    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(secondsFromGMT: 0)!
        return c
    }

    /// 2026-05-21 19:53:03 UTC — a representative DJI recording-start instant.
    private var sampleDate: Date {
        var c = DateComponents()
        c.year = 2026; c.month = 5; c.day = 21
        c.hour = 19; c.minute = 53; c.second = 3
        c.timeZone = TimeZone(secondsFromGMT: 0)
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func apply(_ pattern: String, start: Int = 1, digits: Int = 3,
                       date: Date? = nil, index: Int = 0) -> String {
        RenamePatternEngine.applyStem(
            name: "DJI_0009_D",
            date: date,
            options: .init(pattern: pattern, start: start, digits: digits),
            index: index,
            calendar: utc
        )
    }

    // MARK: Individual tokens

    func testNameToken() {
        XCTAssertEqual(apply("{name}"), "DJI_0009_D")
    }

    func testDateToken() {
        XCTAssertEqual(apply("{date}", date: sampleDate), "2026-05-21")
    }

    func testTimeTokenUsesDotsNotColons() {
        XCTAssertEqual(apply("{time}", date: sampleDate), "19.53.03")
    }

    func testCounterTokenPaddingAndOffset() {
        XCTAssertEqual(apply("{###}", start: 1, digits: 3, index: 0), "001")
        XCTAssertEqual(apply("{###}", start: 1, digits: 3, index: 1), "002")
        XCTAssertEqual(apply("{###}", start: 7, digits: 2, index: 0), "07")
        XCTAssertEqual(apply("{###}", start: 7, digits: 4, index: 0), "0007")
        // More digits than the pad width are never truncated.
        XCTAssertEqual(apply("{###}", start: 1000, digits: 2, index: 0), "1000")
    }

    // MARK: Composite patterns

    func testDefaultPattern() {
        XCTAssertEqual(apply("{name}_{date}_joined", date: sampleDate), "DJI_0009_D_2026-05-21_joined")
    }

    func testDateCounterPreset() {
        XCTAssertEqual(
            apply("{date}_flight_{###}", start: 1, digits: 3, date: sampleDate, index: 4),
            "2026-05-21_flight_005"
        )
    }

    func testDateTimePreset() {
        XCTAssertEqual(apply("{date}_{time}", date: sampleDate), "2026-05-21_19.53.03")
    }

    // MARK: Per-batch counter semantics

    func testCounterIsBatchRelativeIndex() {
        // Counter == start + index; the engine never carries state between calls, so a fresh batch
        // (index back to 0) restarts at `start` — the product's "restart each batch" rule.
        let opts = RenamePatternEngine.Options(pattern: "f_{###}", start: 1, digits: 3)
        let batch = (0..<3).map {
            RenamePatternEngine.applyStem(name: "x", date: nil, options: opts, index: $0, calendar: utc)
        }
        XCTAssertEqual(batch, ["f_001", "f_002", "f_003"])
    }

    // MARK: Illegal characters & fallback

    func testIllegalCharactersBecomeDashes() {
        XCTAssertEqual(apply("a/b:c*d?e"), "a-b-c-d-e")
        XCTAssertEqual(apply("x\"<>|y"), "x----y")
    }

    func testEmptyPatternFallsBackToName() {
        XCTAssertEqual(apply(""), "DJI_0009_D")
    }

    func testWhitespaceOnlyPatternFallsBackToName() {
        XCTAssertEqual(apply("   "), "DJI_0009_D")
    }

    func testUnresolvedDateLeavesTokensEmpty() {
        // No resolved date → {date}/{time} expand to "" (the fallback only triggers on a fully-empty
        // result, so a trailing separator is left as-is — documents the nil behavior).
        XCTAssertEqual(apply("{name}_{date}", date: nil), "DJI_0009_D_")
        XCTAssertEqual(apply("{date}", date: nil), "DJI_0009_D")  // becomes "" → fallback
    }

    // MARK: Collision suffixing

    func testUniqueStemNoCollision() {
        XCTAssertEqual(RenamePatternEngine.uniqueStem("flight", taken: []), "flight")
    }

    func testUniqueStemSuffixesUntilFree() {
        XCTAssertEqual(RenamePatternEngine.uniqueStem("flight", taken: ["flight"]), "flight_2")
        XCTAssertEqual(
            RenamePatternEngine.uniqueStem("flight", taken: ["flight", "flight_2", "flight_3"]),
            "flight_4"
        )
    }

    func testUniqueStemIsCaseInsensitive() {
        // macOS volumes are case-insensitive by default, so "Flight" collides with "flight".
        XCTAssertEqual(RenamePatternEngine.uniqueStem("Flight", taken: ["flight"]), "Flight_2")
    }

    // MARK: usesCounter gate

    func testUsesCounter() {
        XCTAssertTrue(RenamePatternEngine.usesCounter("{date}_flight_{###}"))
        XCTAssertFalse(RenamePatternEngine.usesCounter("{name}_{date}_joined"))
    }
}
