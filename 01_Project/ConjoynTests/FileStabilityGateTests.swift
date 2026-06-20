import XCTest
@testable import Conjoyn

/// Backpressure for task 5.1: the pure file-settling predicate. These tests *are* the contract —
/// they hold whatever policy you write into `FileStabilityGate.isSettled`'s marked block.
final class FileStabilityGateTests: XCTestCase {

    typealias Sample = FileStabilityGate.Sample

    // A fixed clock so mtime equality is explicit, never wall-clock-dependent.
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ offset: TimeInterval) -> Date { t0.addingTimeInterval(offset) }

    private func settled(_ samples: [Sample], _ n: Int) -> Bool {
        FileStabilityGate.isSettled(samples: samples, requiredStablePolls: n)
    }

    // MARK: - Never-settle guards

    func testEmptySamplesNeverSettle() {
        XCTAssertFalse(settled([], 3))
    }

    func testFewerSamplesThanRequiredNeverSettle() {
        let s = Sample(size: 100, modified: at(0))
        XCTAssertFalse(settled([s, s], 3))
    }

    func testZeroRequiredPollsIsRejected() {
        // Defensive: a zero-poll gate would wave through an actively-growing file.
        let s = Sample(size: 100, modified: at(0))
        XCTAssertFalse(settled([s, s, s], 0))
    }

    // MARK: - Growth never settles

    func testStillGrowingFileNeverSettles() {
        let samples = [
            Sample(size: 10_000_000, modified: at(0)),
            Sample(size: 20_000_000, modified: at(0.75)),
            Sample(size: 30_000_000, modified: at(1.5)),
        ]
        XCTAssertFalse(settled(samples, 3))
    }

    func testGrowsAgainAtTheTailDoesNotSettle() {
        // Looked quiet, then one more chunk landed — the streak must reset.
        let samples = [
            Sample(size: 30_000_000, modified: at(0)),
            Sample(size: 30_000_000, modified: at(0.75)),
            Sample(size: 40_000_000, modified: at(1.5)),
        ]
        XCTAssertFalse(settled(samples, 3))
    }

    // MARK: - Stable tail settles

    func testThreeIdenticalSnapshotsSettle() {
        let s = Sample(size: 30_000_000, modified: at(0))
        XCTAssertTrue(settled([s, s, s], 3))
    }

    func testStableTailAfterGrowthSettles() {
        // Once the last write lands (at t=1.5) the file's mtime FREEZES at 1.5 — later polls read
        // the same (size, mtime) even though wall-clock keeps moving. So the plateau shares one mtime.
        let samples = [
            Sample(size: 10_000_000, modified: at(0)),
            Sample(size: 20_000_000, modified: at(0.75)),
            Sample(size: 30_000_000, modified: at(1.5)),
            Sample(size: 30_000_000, modified: at(1.5)),
            Sample(size: 30_000_000, modified: at(1.5)),
        ]
        // Last three (the 30 MB plateau, frozen mtime) are identical → settled.
        XCTAssertTrue(settled(samples, 3))
    }

    // MARK: - In-place rewrite (same size, new mtime) must NOT settle

    func testSameSizeButChangingMtimeDoesNotSettle() {
        let samples = [
            Sample(size: 30_000_000, modified: at(0)),
            Sample(size: 30_000_000, modified: at(0.75)),
            Sample(size: 30_000_000, modified: at(1.5)),
            Sample(size: 30_000_000, modified: at(2.25)), // rewritten in place: size same, mtime moved
        ]
        // The tail of 3 differs by mtime, so it is not a stable streak.
        let tail = Array(samples.suffix(3))
        XCTAssertFalse(tail.allSatisfy { $0 == tail.first }) // sanity on the fixture
        XCTAssertFalse(settled(samples, 3))
    }

    // MARK: - Atomic write-then-rename: complete file appears whole, still needs confirmation

    func testAtomicRenameNeedsConfirmationThenSettles() {
        // The sampler only sees the final path once the rename completes, so every snapshot is
        // already the full size — but a single sighting is not enough.
        let full = Sample(size: 42_000_000, modified: at(5.0))
        XCTAssertFalse(settled([full], 3))            // just appeared
        XCTAssertFalse(settled([full, full], 3))      // one confirmation
        XCTAssertTrue(settled([full, full, full], 3)) // two confirmations → safe
    }

    // MARK: - requiredStablePolls = 1 (eager) honours the contract

    func testSinglePollSettlesImmediately() {
        let s = Sample(size: 1, modified: at(0))
        XCTAssertTrue(settled([s], 1))
    }
}
