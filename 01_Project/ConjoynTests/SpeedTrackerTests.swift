import XCTest
import CoreMedia
@testable import Conjoyn

/// Tests for the ported `SpeedTracker` (Wave 1, task 1.8).
///
/// Every test runs against a fresh, throwaway storage directory injected via
/// `SpeedTracker(storageDirectory:)`, so the suite never reads or mutates the user's real
/// `~/Library/Application Support/DJIjoiner/speed_records.json`.
@MainActor
final class SpeedTrackerTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("SpeedTrackerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
        tmpDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeTracker() -> SpeedTracker {
        SpeedTracker(storageDirectory: tmpDir)
    }

    /// Builds a clip with an exact duration. When `fileSize` is given, a real file of that many bytes
    /// is written so `totalFileSize` reads back a known value; otherwise the path won't exist (size 0).
    private func makeClip(seconds: Double, fileSize: Int? = nil) throws -> DJIClip {
        let url: URL
        if let fileSize {
            url = tmpDir.appendingPathComponent("clip-\(UUID().uuidString).mp4")
            try Data(count: fileSize).write(to: url)
        } else {
            url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mp4")
        }
        return DJIClip(
            videoURL: url,
            index: 0,
            stem: "DJI_0001",
            duration: CMTime(seconds: seconds, preferredTimescale: 600)
        )
    }

    // MARK: - Estimation: no history

    func testEstimateWithNoHistoryUsesDefaultAndLowConfidence() throws {
        let tracker = makeTracker()
        let clips = [try makeClip(seconds: 60), try makeClip(seconds: 30)]

        let estimate = tracker.estimateConversion(clips: clips, outputFormat: .mp4)

        XCTAssertEqual(estimate.clipCount, 2)
        XCTAssertEqual(estimate.totalDurationSeconds, 90, accuracy: 0.001)
        XCTAssertEqual(estimate.speedMultiplier, 15.0, accuracy: 0.001, "no history → default 15x")
        XCTAssertEqual(estimate.confidence, .low)
        // 90s of content at 15x → 6s.
        XCTAssertEqual(estimate.estimatedSeconds, 6.0, accuracy: 0.001)
    }

    // MARK: - Recording

    func testRecordConversionComputesSpeedMultiplier() throws {
        let tracker = makeTracker()
        // 60s of content joined in 2s → 30x realtime.
        tracker.recordConversion(
            bytesProcessed: 1_000_000,
            durationSeconds: 2,
            contentDurationSeconds: 60,
            outputFormat: .mp4
        )

        XCTAssertEqual(tracker.records.count, 1)
        XCTAssertEqual(tracker.records[0].speedMultiplier, 30.0, accuracy: 0.001)
        XCTAssertEqual(tracker.records[0].outputFormat, .mp4)
    }

    func testRecordConversionRejectsNonPositiveInputs() {
        let tracker = makeTracker()
        tracker.recordConversion(bytesProcessed: 100, durationSeconds: 0, contentDurationSeconds: 60, outputFormat: .mp4)
        tracker.recordConversion(bytesProcessed: 100, durationSeconds: 2, contentDurationSeconds: 0, outputFormat: .mp4)
        XCTAssertTrue(tracker.records.isEmpty, "zero duration or content must not produce a record")
    }

    func testRecordsAreCappedAtFifty() {
        let tracker = makeTracker()
        for i in 0..<60 {
            tracker.recordConversion(
                bytesProcessed: Int64(i),
                durationSeconds: 2,
                contentDurationSeconds: 60,
                outputFormat: .mp4
            )
        }
        XCTAssertEqual(tracker.records.count, 50, "only the most recent 50 are kept")
        // The first 10 should have been dropped (bytesProcessed 0..<10 gone, 10 is now first).
        XCTAssertEqual(tracker.records.first?.bytesProcessed, 10)
        XCTAssertEqual(tracker.records.last?.bytesProcessed, 59)
    }

    // MARK: - Confidence tiers

    func testThreeRecentMatchingRecordsGivesHighConfidence() throws {
        let tracker = makeTracker()
        for _ in 0..<3 {
            tracker.recordConversion(bytesProcessed: 10, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        }
        let estimate = tracker.estimateConversion(clips: [try makeClip(seconds: 60)], outputFormat: .mp4)
        XCTAssertEqual(estimate.confidence, .high)
        XCTAssertEqual(estimate.speedMultiplier, 30.0, accuracy: 0.001)
    }

    func testFewerThanThreeMatchingGivesMediumConfidence() throws {
        let tracker = makeTracker()
        // Two matching-format records → recent count 2 (<3) but matchingAll non-empty → medium.
        tracker.recordConversion(bytesProcessed: 10, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        tracker.recordConversion(bytesProcessed: 10, durationSeconds: 3, contentDurationSeconds: 60, outputFormat: .mp4)
        let estimate = tracker.estimateConversion(clips: [try makeClip(seconds: 60)], outputFormat: .mp4)
        XCTAssertEqual(estimate.confidence, .medium)
    }

    func testCrossFormatFallbackGivesMediumConfidence() throws {
        let tracker = makeTracker()
        // History only for MP4; estimate for MOV → no matching format, falls back to all records.
        for _ in 0..<5 {
            tracker.recordConversion(bytesProcessed: 10, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        }
        let estimate = tracker.estimateConversion(clips: [try makeClip(seconds: 60)], outputFormat: .mov)
        XCTAssertEqual(estimate.confidence, .medium)
        XCTAssertEqual(estimate.speedMultiplier, 30.0, accuracy: 0.001, "uses average of all records")
    }

    // MARK: - Estimate totals

    func testEstimateSumsBytesAndDuration() throws {
        let tracker = makeTracker()
        let clips = [
            try makeClip(seconds: 10, fileSize: 1024),
            try makeClip(seconds: 20, fileSize: 2048)
        ]
        let estimate = tracker.estimateConversion(clips: clips, outputFormat: .mp4)
        XCTAssertEqual(estimate.totalBytes, 3072)
        XCTAssertEqual(estimate.totalDurationSeconds, 30, accuracy: 0.001)
        XCTAssertEqual(estimate.clipCount, 2)
    }

    func testEstimateJobDelegatesToEstimateConversion() throws {
        let tracker = makeTracker()
        let clips = [try makeClip(seconds: 60)]
        var settings = ConversionSettings()
        settings.outputContainer = .mov
        let job = ConversionJob(
            folderName: "100MEDIA",
            sourceFolderURL: tmpDir,
            clips: clips,
            settings: settings,
            destinationURL: tmpDir.appendingPathComponent("out.mov")
        )
        let estimate = tracker.estimateJob(job)
        XCTAssertEqual(estimate.clipCount, 1)
        XCTAssertEqual(estimate.totalDurationSeconds, 60, accuracy: 0.001)
    }

    // MARK: - Slow speed detection

    func testCheckSpeedReturnsWarningWhenWellBelowExpected() throws {
        let tracker = makeTracker()
        // Establish an expected ~30x average.
        for _ in 0..<5 {
            tracker.recordConversion(bytesProcessed: 10, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        }
        // Current 5x is < 30 * 0.3 (= 9), so it should warn.
        let warning = try XCTUnwrap(tracker.checkSpeed(
            currentSpeedMultiplier: 5,
            bytesRemaining: 1_000,
            contentDurationRemaining: 100,
            outputPath: tmpDir
        ))
        XCTAssertEqual(tracker.currentSpeedWarning?.currentSpeed, 5)
        XCTAssertEqual(warning.estimatedRemaining, 20, accuracy: 0.001, "100s remaining / 5x")
    }

    func testCheckSpeedNoWarningWhenNearExpected() {
        let tracker = makeTracker()
        for _ in 0..<5 {
            tracker.recordConversion(bytesProcessed: 10, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        }
        // 25x is above the 9x threshold → no warning, and any prior warning is cleared.
        let warning = tracker.checkSpeed(
            currentSpeedMultiplier: 25,
            bytesRemaining: 1_000,
            contentDurationRemaining: 100,
            outputPath: tmpDir
        )
        XCTAssertNil(warning)
        XCTAssertNil(tracker.currentSpeedWarning)
    }

    func testClearSpeedWarning() {
        let tracker = makeTracker()
        for _ in 0..<5 {
            tracker.recordConversion(bytesProcessed: 10, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        }
        _ = tracker.checkSpeed(currentSpeedMultiplier: 1, bytesRemaining: 1, contentDurationRemaining: 10, outputPath: tmpDir)
        XCTAssertNotNil(tracker.currentSpeedWarning)
        tracker.clearSpeedWarning()
        XCTAssertNil(tracker.currentSpeedWarning)
    }

    // MARK: - Statistics

    func testAverageThroughput() {
        let tracker = makeTracker()
        XCTAssertNil(tracker.averageThroughputMBps, "no records → nil")
        // 2 MiB processed over 2s total → 1 MB/s.
        tracker.recordConversion(bytesProcessed: 2 * 1024 * 1024, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        XCTAssertEqual(tracker.averageThroughputMBps ?? 0, 1.0, accuracy: 0.001)
    }

    func testClearHistory() {
        let tracker = makeTracker()
        tracker.recordConversion(bytesProcessed: 10, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mp4)
        XCTAssertFalse(tracker.records.isEmpty)
        tracker.clearHistory()
        XCTAssertTrue(tracker.records.isEmpty)
    }

    // MARK: - Persistence round-trip

    func testRecordsPersistAcrossInstances() {
        let first = makeTracker()
        first.recordConversion(bytesProcessed: 123, durationSeconds: 2, contentDurationSeconds: 60, outputFormat: .mov)
        first.recordConversion(bytesProcessed: 456, durationSeconds: 4, contentDurationSeconds: 60, outputFormat: .mp4)
        // recordConversion persists synchronously, so the next instance is guaranteed to see it.

        // A new tracker pointed at the same directory loads the saved records.
        let second = SpeedTracker(storageDirectory: tmpDir)
        XCTAssertEqual(second.records.count, 2)
        XCTAssertEqual(second.records[0].bytesProcessed, 123)
        XCTAssertEqual(second.records[0].outputFormat, .mov)
        XCTAssertEqual(second.records[1].speedMultiplier, 15.0, accuracy: 0.001, "60s / 4s = 15x survives the round-trip")
    }

    func testFreshDirectoryStartsEmpty() {
        let tracker = makeTracker()
        XCTAssertTrue(tracker.records.isEmpty)
        XCTAssertNil(tracker.currentSpeedWarning)
    }
}
