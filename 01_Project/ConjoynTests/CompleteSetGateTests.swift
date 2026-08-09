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

    // MARK: - GoPro family-aware overload (Wave G6.1)

    private let goProFloor = WatchFolderSettings.defaults.goProSplitFloor
    private let goProRatio = WatchFolderSettings.defaults.goProFinalChapterRatio

    private func goProComplete(last: Int64, preceding: [Int64], quiet: TimeInterval) -> Bool {
        CompleteSetGate.isComplete(family: .goPro,
                                   lastSegmentBytes: last,
                                   precedingSegmentBytes: preceding,
                                   splitThreshold: threshold,
                                   goProSplitFloor: goProFloor,
                                   finalChapterRatio: goProRatio,
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

    // MARK: - GoPro: DJI family delegates verbatim

    func testGoProOverloadWithDJIFamilyDelegatesVerbatim() {
        // Deliberately extreme GoPro-only params: if they leaked into the DJI branch they would
        // flip the outcome. They must be entirely ignored.
        let delegated = CompleteSetGate.isComplete(family: .dji,
                                                    lastSegmentBytes: 800_000_000,
                                                    precedingSegmentBytes: [1],
                                                    splitThreshold: threshold,
                                                    goProSplitFloor: 1,
                                                    finalChapterRatio: 0.0001,
                                                    quietElapsed: quietWindow,
                                                    quietWindow: quietWindow)
        XCTAssertEqual(delegated, complete(last: 800_000_000, quiet: quietWindow))
        XCTAssertTrue(delegated)
    }

    // MARK: - GoPro: relative-ratio branch (preceding chapter visible)

    func testGoProRatioBranch_belowRatio_isFinal() {
        // last / min(preceding) = 9.0e9 / 10.0e9 = 0.90, below the 0.94 ratio.
        XCTAssertTrue(goProComplete(last: 9_000_000_000, preceding: [10_000_000_000], quiet: quietWindow))
    }

    func testGoProRatioBranch_aboveRatio_isNotFinal() {
        // last / min(preceding) = 9.5e9 / 10.0e9 = 0.95, above the 0.94 ratio — continuation expected.
        XCTAssertFalse(goProComplete(last: 9_500_000_000, preceding: [10_000_000_000], quiet: quietWindow + 30))
    }

    func testGoProRatioBranch_ratioAboveOne_readsAsContinuation() {
        // A later chapter marginally larger than the smallest earlier one (ratio 1.00015, as
        // measured in the real corpus) must still read as "expect continuation", not final.
        XCTAssertFalse(goProComplete(last: 10_001_500_000, preceding: [10_000_000_000], quiet: quietWindow + 30))
    }

    func testGoProRatioBranch_usesMinimumOfMultiplePrecedingChapters() {
        // The smallest preceding chapter is the reference, not the largest or the first.
        XCTAssertTrue(goProComplete(last: 4_000_000_000, preceding: [10_000_000_000, 5_000_000_000], quiet: quietWindow))
    }

    // MARK: - GoPro: no-reference floor branch

    func testGoProFloorBranch_noPrecedingChapters_belowFloor_isFinal() {
        // A lone chapter (no reference at all) below the 9.5 GB floor.
        XCTAssertTrue(goProComplete(last: 9_000_000_000, preceding: [], quiet: quietWindow))
    }

    func testGoProFloorBranch_noPrecedingChapters_atOrAboveFloor_isNotFinal() {
        // Still-copying card that has only chapter 01 so far — must not be joined alone.
        XCTAssertFalse(goProComplete(last: goProFloor, preceding: [], quiet: quietWindow + 30))
        XCTAssertFalse(goProComplete(last: 10_000_000_000, preceding: [], quiet: quietWindow + 30))
    }

    func testGoProFloorBranch_everyPrecedingSizeUnusable_fallsBackToFloor() {
        // Missing size samples (0) must not make the ratio comparison `x < 0` — never true, which
        // would stall the group forever. With no usable reference at all, the floor decides.
        XCTAssertTrue(goProComplete(last: 9_000_000_000, preceding: [0, 0], quiet: quietWindow))
        XCTAssertFalse(goProComplete(last: 10_000_000_000, preceding: [0, 0], quiet: quietWindow + 30))
    }

    func testGoProZeroPrecedingSizeDoesNotPoisonAGenuineReference() {
        // A 0 alongside a real chapter size must be filtered out, not taken as the minimum:
        // the 5 GB reference still governs. The second assertion is the discriminating one —
        // 9 GB is below the 9.5 GB floor, so a floor fallback here would wrongly say "join now",
        // while the real reference says 9/5 = 1.8 ⇒ still expecting a continuation.
        XCTAssertTrue(goProComplete(last: 4_000_000_000, preceding: [0, 5_000_000_000], quiet: quietWindow))
        XCTAssertFalse(goProComplete(last: 9_000_000_000, preceding: [0, 5_000_000_000], quiet: quietWindow + 30))
    }

    // MARK: - GoPro: quiet window still gates, independent of the final-chapter signal

    func testGoProFinalChapter_stillGatedByQuietWindow() {
        XCTAssertFalse(goProComplete(last: 1_000_000_000, preceding: [10_000_000_000], quiet: quietWindow - 0.01))
        XCTAssertTrue(goProComplete(last: 1_000_000_000, preceding: [10_000_000_000], quiet: quietWindow))
    }

    // MARK: - GoPro: real 71-file Hero 11 corpus criterion

    /// Walks all 6 multi-chapter recordings in the real corpus. For every prefix length
    /// k = 1...N, treats chapter k as the last segment and chapters 1..<k as
    /// `precedingSegmentBytes`, then asserts the group reads complete iff k == N.
    func testGoProCorpus_multiChapterRecordings_completeOnlyAtFinalChapter() {
        let settings = WatchFolderSettings.defaults
        let quiet = settings.quietWindow + 1

        let byRecording = Dictionary(grouping: DJIFolderGroupingTests.corpusRows, by: \.recording)
        let multiChapter = byRecording.filter { $0.value.count > 1 }
        XCTAssertEqual(multiChapter.count, 6, "Corpus is expected to hold exactly 6 multi-chapter recordings")

        for (recording, rows) in multiChapter {
            let sizes = rows.sorted { $0.chapter < $1.chapter }.map(\.sizeBytes)
            let n = sizes.count
            for k in 1...n {
                let last = sizes[k - 1]
                let preceding = Array(sizes[0..<(k - 1)])
                let result = CompleteSetGate.isComplete(family: .goPro,
                                                         lastSegmentBytes: last,
                                                         precedingSegmentBytes: preceding,
                                                         splitThreshold: settings.splitThreshold,
                                                         goProSplitFloor: settings.goProSplitFloor,
                                                         finalChapterRatio: settings.goProFinalChapterRatio,
                                                         quietElapsed: quiet,
                                                         quietWindow: settings.quietWindow)
                XCTAssertEqual(result, k == n,
                               "recording \(recording) chapter \(k)/\(n) expected complete == \(k == n)")
            }
        }
    }

    /// All 51 single-chapter recordings in the real corpus must complete once quiet — there is no
    /// reference, so the no-reference floor branch applies, and every genuine single-chapter
    /// recording in the corpus sits below the floor.
    func testGoProCorpus_singleChapterRecordings_completeOnceQuiet() {
        let settings = WatchFolderSettings.defaults
        let quiet = settings.quietWindow + 1

        let byRecording = Dictionary(grouping: DJIFolderGroupingTests.corpusRows, by: \.recording)
        let singleChapter = byRecording.filter { $0.value.count == 1 }
        XCTAssertEqual(singleChapter.count, 51, "Corpus is expected to hold exactly 51 single-chapter recordings")

        for (recording, rows) in singleChapter {
            let row = rows[0]
            let result = CompleteSetGate.isComplete(family: .goPro,
                                                     lastSegmentBytes: row.sizeBytes,
                                                     precedingSegmentBytes: [],
                                                     splitThreshold: settings.splitThreshold,
                                                     goProSplitFloor: settings.goProSplitFloor,
                                                     finalChapterRatio: settings.goProFinalChapterRatio,
                                                     quietElapsed: quiet,
                                                     quietWindow: settings.quietWindow)
            XCTAssertTrue(result, "single-chapter recording \(recording) should complete once quiet")
        }
    }
}
