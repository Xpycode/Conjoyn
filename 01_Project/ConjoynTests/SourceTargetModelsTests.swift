import XCTest
@testable import Conjoyn

// MARK: - Source↔Target model tests (Commit 1)

/// Pure value-type tests for the source↔target verification models: the worst-wins severity roll-up,
/// the `SourceTargetResult` computed verdicts, the `CheckOutcome` severity/detail mapping, and the
/// `VerificationStatus.warning` Codable wiring (including old-`queue.json` forward-compat). No I/O,
/// no ffmpeg — this is the arithmetic/classification layer the verifier (Commit 2) builds on.
final class SourceTargetModelsTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip<T: Codable>(_ value: T, as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    private func check(_ kind: VerificationCheck.Kind,
                       _ severity: CheckSeverity,
                       detail: String = "") -> VerificationCheck {
        VerificationCheck(kind: kind, severity: severity, label: "\(kind)", detail: detail)
    }

    private func result(_ checks: [VerificationCheck], tier: SourceTargetResult.Tier = .fast) -> SourceTargetResult {
        SourceTargetResult(tier: tier, checks: checks, verifiedAt: Date(), duration: 1.0)
    }

    // MARK: - CheckSeverity Comparable / worst-wins

    func testCheckSeverityOrdering() {
        XCTAssertLessThan(CheckSeverity.pass, .info)
        XCTAssertLessThan(CheckSeverity.info, .warning)
        XCTAssertLessThan(CheckSeverity.warning, .fail)
        XCTAssertGreaterThan(CheckSeverity.fail, .pass)
    }

    func testCheckSeverityWorstWinsViaMax() {
        XCTAssertEqual([CheckSeverity.pass, .info, .pass].max(), .info)
        XCTAssertEqual([CheckSeverity.pass, .warning, .info].max(), .warning)
        XCTAssertEqual([CheckSeverity.info, .fail, .warning].max(), .fail)
        XCTAssertEqual([CheckSeverity.pass, .pass].max(), .pass)
        XCTAssertNil([CheckSeverity]().max())
    }

    // MARK: - SourceTargetResult computed verdicts

    func testResultEmptyIsPass() {
        let r = result([])
        XCTAssertEqual(r.overall, .pass)
        XCTAssertTrue(r.passed)
        XCTAssertFalse(r.hasWarning)
        XCTAssertNil(r.firstFailureReason)
        XCTAssertEqual(r.summary, "All checks passed")
    }

    func testResultAllPass() {
        let r = result([check(.packetCount, .pass), check(.duration, .pass)])
        XCTAssertEqual(r.overall, .pass)
        XCTAssertTrue(r.passed)
        XCTAssertFalse(r.hasWarning)
        XCTAssertNil(r.firstFailureReason)
        XCTAssertEqual(r.summary, "All checks passed")
    }

    func testResultWithInfoStillPasses() {
        let r = result([check(.packetCount, .pass), check(.duration, .info, detail: "sub-frame delta")])
        XCTAssertEqual(r.overall, .info)
        XCTAssertTrue(r.passed)
        XCTAssertFalse(r.hasWarning)
        XCTAssertNil(r.firstFailureReason)
        XCTAssertEqual(r.summary, "All checks passed")
    }

    func testResultWithWarning() {
        let r = result([check(.packetCount, .pass), check(.duration, .warning, detail: "duration off by 3 frames")])
        XCTAssertEqual(r.overall, .warning)
        XCTAssertFalse(r.passed)
        XCTAssertTrue(r.hasWarning)
        XCTAssertNil(r.firstFailureReason)
        XCTAssertEqual(r.summary, "duration off by 3 frames")
    }

    func testResultWithMultipleWarnings() {
        let r = result([
            check(.duration, .warning, detail: "a"),
            check(.avDrift, .warning, detail: "b")
        ])
        XCTAssertEqual(r.overall, .warning)
        XCTAssertTrue(r.hasWarning)
        XCTAssertEqual(r.summary, "2 warnings")
    }

    func testResultWithFail() {
        let r = result([
            check(.packetCount, .pass),
            check(.duration, .fail, detail: "missing trailing segment"),
            check(.packetBytes, .fail, detail: "byte total mismatch")
        ])
        XCTAssertEqual(r.overall, .fail)
        XCTAssertFalse(r.passed)
        XCTAssertFalse(r.hasWarning)
        XCTAssertEqual(r.firstFailureReason, "missing trailing segment")
        XCTAssertEqual(r.summary, "missing trailing segment")
    }

    func testResultMixedWorstWins() {
        // warning + fail → fail dominates; firstFailureReason is the first .fail in order.
        let r = result([
            check(.duration, .warning, detail: "warn"),
            check(.packetCount, .fail, detail: "count mismatch"),
            check(.avDrift, .info, detail: "info")
        ])
        XCTAssertEqual(r.overall, .fail)
        XCTAssertFalse(r.passed)
        XCTAssertFalse(r.hasWarning)
        XCTAssertEqual(r.firstFailureReason, "count mismatch")
        XCTAssertEqual(r.summary, "count mismatch")
    }

    // MARK: - CheckOutcome severity / detail mapping

    func testCheckOutcomeSeverityMapping() {
        XCTAssertEqual(CheckOutcome.pass.severity, .pass)
        XCTAssertEqual(CheckOutcome.info("x").severity, .info)
        XCTAssertEqual(CheckOutcome.warning("x").severity, .warning)
        XCTAssertEqual(CheckOutcome.fail("x").severity, .fail)
    }

    func testCheckOutcomeDetailMapping() {
        XCTAssertNil(CheckOutcome.pass.detail)
        XCTAssertEqual(CheckOutcome.info("note").detail, "note")
        XCTAssertEqual(CheckOutcome.warning("warn").detail, "warn")
        XCTAssertEqual(CheckOutcome.fail("bad").detail, "bad")
    }

    // MARK: - VerificationStatus.warning Codable

    func testVerificationStatusWarningRoundTrip() throws {
        let original = VerificationStatus.warning("duration off by 3 frames")
        let decoded = try roundTrip(original, as: VerificationStatus.self)
        XCTAssertEqual(decoded, original)
    }

    func testVerificationStatusWarningProperties() {
        let status = VerificationStatus.warning("flagged")
        XCTAssertEqual(status.displayName, "Flagged")
        XCTAssertEqual(status.iconName, "exclamationmark.seal.fill")
        XCTAssertTrue(status.isFinished)
    }

    func testVerificationStatusExistingCasesStillRoundTrip() throws {
        for status: VerificationStatus in [.unverified, .verifying, .verified, .failed("boom")] {
            XCTAssertEqual(try roundTrip(status, as: VerificationStatus.self), status)
        }
    }

    /// An old `queue.json` written before the `warning` case (and any future unknown tag) must still
    /// decode via the default-case fallback rather than throwing.
    func testVerificationStatusUnknownTagFallsBackToUnverified() throws {
        let legacy = #"{"type":"sometag-from-the-future"}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(VerificationStatus.self, from: legacy)
        XCTAssertEqual(decoded, .unverified)
    }

    // MARK: - SourceTargetResult Codable

    func testSourceTargetResultRoundTrip() throws {
        let r = SourceTargetResult(
            tier: .thorough,
            checks: [
                check(.readability, .pass, detail: "decodes"),
                check(.packetCount, .pass, detail: "1200 == 1200"),
                check(.duration, .warning, detail: "off by 2 frames"),
                check(.hashMatch, .fail, detail: "v:0 md5 differs")
            ],
            verifiedAt: Date(timeIntervalSince1970: 1_700_000_000),
            duration: 12.5
        )
        let decoded = try roundTrip(r, as: SourceTargetResult.self)
        XCTAssertEqual(decoded, r)
        // Spot-check the computed verdicts survive intact through the stored data.
        XCTAssertEqual(decoded.overall, .fail)
        XCTAssertEqual(decoded.firstFailureReason, "v:0 md5 differs")
    }
}
