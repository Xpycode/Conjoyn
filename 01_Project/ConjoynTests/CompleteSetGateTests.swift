import XCTest
@testable import Conjoyn

/// Backpressure for task 5.2: the pure complete-set predicate. These tests are the contract; they
/// hold against whatever policy you write into `CompleteSetGate.isComplete`'s marked block.
final class CompleteSetGateTests: XCTestCase {

    // A representative ~4 GB split threshold (FAT32 single-file ceiling, minus a margin).
    private let threshold: Int64 = 4_000_000_000
    private let quietWindow: TimeInterval = 45

    private func complete(last: Int64, quiet: TimeInterval) -> Bool {
        CompleteSetGate.isComplete(lastSegmentBytes: last,
                                   splitThreshold: threshold,
                                   quietElapsed: quiet,
                                   quietWindow: quietWindow)
    }

    // MARK: - Last segment still at split size ⇒ a continuation may follow ⇒ not complete

    func testFullLastSegmentIsNotComplete() {
        // Even after a long quiet, a segment at the split ceiling means "more may come".
        XCTAssertFalse(complete(last: threshold, quiet: 600))
        XCTAssertFalse(complete(last: threshold + 1, quiet: 600))
    }

    // MARK: - Small last segment but not yet quiet ⇒ copy may still be in flight ⇒ not complete

    func testSmallLastSegmentButStillBusyIsNotComplete() {
        XCTAssertFalse(complete(last: 800_000_000, quiet: 5))
        XCTAssertFalse(complete(last: 800_000_000, quiet: quietWindow - 0.01))
    }

    // MARK: - Both signals satisfied ⇒ complete

    func testSmallLastSegmentAndQuietIsComplete() {
        XCTAssertTrue(complete(last: 800_000_000, quiet: quietWindow))      // exactly the window
        XCTAssertTrue(complete(last: 800_000_000, quiet: quietWindow + 30)) // well past
    }

    func testSingleSmallSegmentGroupCompletesOnceQuiet() {
        // A lone short clip (no split happened) is the common case — completes once quiet.
        XCTAssertTrue(complete(last: 120_000_000, quiet: quietWindow))
    }

    // MARK: - Boundary semantics are explicit

    func testThresholdIsExclusiveAtTheBoundary() {
        // "below the split threshold" — exactly at the threshold is NOT below.
        XCTAssertFalse(complete(last: threshold, quiet: 600))
        XCTAssertTrue(complete(last: threshold - 1, quiet: quietWindow))
    }

    func testQuietWindowIsInclusiveAtTheBoundary() {
        XCTAssertTrue(complete(last: 1_000, quiet: quietWindow))
        XCTAssertFalse(complete(last: 1_000, quiet: quietWindow - 0.001))
    }
}
