import XCTest
import CoreMedia
@testable import Conjoyn

/// Tests for the ported `QueueManager` (Wave 1, task 1.7).
///
/// Every test runs against a fresh, throwaway storage directory injected via
/// `QueueManager(storageDirectory:)`, so the suite never reads or mutates the user's real
/// `~/Library/Application Support/Conjoyn/queue.json`. The keystone is the enqueue→persist→reload
/// round-trip (the task's backpressure): a second manager pointed at the same directory must restore
/// the jobs a first manager saved.
@MainActor
final class QueueManagerTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueueManagerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
        tmpDir = nil
        try super.tearDownWithError()
    }

    // MARK: - Helpers

    private func makeManager() -> QueueManager {
        QueueManager(storageDirectory: tmpDir)
    }

    /// A clip with an exact duration and optional probed frame rate. With `fps`, an embedded
    /// `SegmentStreamInfo` is attached so `estimatedFrameCount` can resolve.
    private func makeClip(seconds: Double, index: Int = 0, fps: Double? = nil) -> DJIClip {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).mp4")
        var streamInfo: StreamParameterGuard.SegmentStreamInfo?
        if let fps {
            streamInfo = StreamParameterGuard.SegmentStreamInfo(
                video: .init(
                    codecName: "h264",
                    width: 3840, height: 2160,
                    pixelFormat: "yuv420p",
                    avgFrameRate: "\(Int(fps))/1",
                    timeBase: "1/\(Int(fps))"
                ),
                audio: nil
            )
        }
        return DJIClip(
            videoURL: url,
            index: index,
            stem: "DJI_000\(index)",
            duration: CMTime(seconds: seconds, preferredTimescale: 600),
            streamInfo: streamInfo
        )
    }

    /// A pending job whose output lands in `tmpDir` (file is NOT created on disk).
    private func makeJob(
        outputName: String,
        status: JobStatus = .pending,
        seconds: Double = 60
    ) -> ConversionJob {
        var job = ConversionJob(
            folderName: "100MEDIA",
            sourceFolderURL: tmpDir,
            clips: [makeClip(seconds: seconds, index: 0), makeClip(seconds: seconds, index: 1)],
            settings: ConversionSettings(),
            destinationURL: tmpDir.appendingPathComponent(outputName)
        )
        job.status = status
        return job
    }

    /// A clip backed by a REAL zero-filled file of `sizeBytes` in `tmpDir`, so `DJIClip.totalFileSize`
    /// reads a known nonzero size — the byte-weighted whole-queue ETA needs real sizes (the default
    /// `makeClip` points at a non-existent path, so its `totalFileSize` is 0).
    private func makeSizedClip(sizeBytes: Int, index: Int = 0, seconds: Double = 60) throws -> DJIClip {
        let url = tmpDir.appendingPathComponent("sized-\(UUID().uuidString)-\(index).mp4")
        try Data(count: sizeBytes).write(to: url)
        return DJIClip(
            videoURL: url,
            index: index,
            stem: "DJI_000\(index)",
            duration: CMTime(seconds: seconds, preferredTimescale: 600),
            streamInfo: nil
        )
    }

    /// A job whose clips are real files summing to `totalBytes`, for the size-weighted ETA tests.
    private func makeSizedJob(
        outputName: String,
        status: JobStatus = .pending,
        totalBytes: Int
    ) throws -> ConversionJob {
        var job = ConversionJob(
            folderName: "100MEDIA",
            sourceFolderURL: tmpDir,
            clips: [try makeSizedClip(sizeBytes: totalBytes, index: 0)],
            settings: ConversionSettings(),
            destinationURL: tmpDir.appendingPathComponent(outputName)
        )
        job.status = status
        return job
    }

    // MARK: - Enqueue → persist → reload round-trip (keystone)

    func testEnqueuePersistReloadRoundTrip() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "FlightA.mp4"))
        manager.addJob(makeJob(outputName: "FlightB.mp4"))
        XCTAssertEqual(manager.jobs.count, 2)

        // A fresh manager on the same directory must restore both pending jobs.
        let reloaded = makeManager()
        XCTAssertEqual(reloaded.jobs.count, 2)
        XCTAssertEqual(reloaded.jobs.map(\.displayName).sorted(), ["FlightA.mp4", "FlightB.mp4"])
        XCTAssertTrue(reloaded.jobs.allSatisfy { $0.status == .pending })
        // Segments and settings survive the round-trip.
        XCTAssertEqual(reloaded.jobs[0].clips.count, 2)
    }

    func testReloadDropsCompletedButKeepsPendingAndFailed() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Done.mp4"))
        manager.addJob(makeJob(outputName: "Waiting.mp4"))
        manager.addJob(makeJob(outputName: "Broken.mp4"))
        // Mutate statuses and persist.
        manager.jobs[0].status = .completed
        manager.jobs[2].status = .failed("boom")
        manager.saveQueue()

        let reloaded = makeManager()
        let names = reloaded.jobs.map(\.displayName).sorted()
        XCTAssertEqual(names, ["Broken.mp4", "Waiting.mp4"], "completed jobs are not restored")
        XCTAssertEqual(reloaded.failedCount, 1)
        XCTAssertEqual(reloaded.pendingCount, 1)
    }

    func testReloadResetsActiveJobToPending() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Interrupted.mp4"))
        manager.jobs[0].status = .active
        manager.jobs[0].progress = 0.4
        manager.saveQueue()

        let reloaded = makeManager()
        // `.active` is restored (it counts as not-finished) but reset to pending with zero progress.
        XCTAssertEqual(reloaded.jobs.count, 1)
        XCTAssertEqual(reloaded.jobs[0].status, .pending)
        XCTAssertEqual(reloaded.jobs[0].progress, 0)
    }

    // MARK: - Filename conflict resolution

    func testResolveFilenameConflictAppendsCounterForExistingFile() throws {
        let manager = makeManager()
        let target = tmpDir.appendingPathComponent("Output.mp4")
        try Data("x".utf8).write(to: target)

        let resolved = manager.resolveFilenameConflict(for: target)
        XCTAssertEqual(resolved.lastPathComponent, "Output (1).mp4")
    }

    func testResolveFilenameConflictAvoidsQueuedDestinations() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Clip.mp4"))

        // Same name as an already-queued destination → must be bumped even though no file exists.
        let resolved = manager.resolveFilenameConflict(for: tmpDir.appendingPathComponent("Clip.mp4"))
        XCTAssertEqual(resolved.lastPathComponent, "Clip (1).mp4")
    }

    func testAddJobAutoRenamesOnDiskConflict() throws {
        let manager = makeManager()
        let dest = tmpDir.appendingPathComponent("Flight.mp4")
        try Data("x".utf8).write(to: dest)   // a file already exists there

        manager.addJob(makeJob(outputName: "Flight.mp4"))
        XCTAssertEqual(manager.jobs.last?.displayName, "Flight (1).mp4")
    }

    // MARK: - Output-folder ↔ queue clarity

    // MARK: - mapStatus

    func testMapStatusThoroughHashPassOverridesWarning() {
        // Tier 2 byte-exact hash pass must promote the seal to .verified even when Tier 1 flagged a warning.
        let r = SourceTargetResult(
            tier: .thorough,
            checks: [
                VerificationCheck(kind: .duration, severity: .warning, label: "Duration", detail: "Δ 80ms (> 1 frame)"),
                VerificationCheck(kind: .hashMatch, severity: .pass, label: "Hash", detail: "")
            ],
            verifiedAt: Date(),
            duration: 1.0
        )
        let status = makeManager().mapStatus(r)
        XCTAssertEqual(status, VerificationStatus.verified)
    }

    func testDirectoriesDifferNilSafety() {
        XCTAssertFalse(QueueManager.directoriesDiffer(nil, tmpDir))
        XCTAssertFalse(QueueManager.directoriesDiffer(tmpDir, nil))
        XCTAssertFalse(QueueManager.directoriesDiffer(nil, nil))
    }

    func testDirectoriesDifferNormalizesTrailingSlashDotAndCase() {
        let base = URL(fileURLWithPath: "/tmp/conjoyn-dirtest", isDirectory: true)
        // Trailing slash / `.` segment / case variations all describe the same directory.
        XCTAssertFalse(QueueManager.directoriesDiffer(base, URL(fileURLWithPath: "/tmp/conjoyn-dirtest/")))
        XCTAssertFalse(QueueManager.directoriesDiffer(base, URL(fileURLWithPath: "/tmp/./conjoyn-dirtest")))
        XCTAssertFalse(QueueManager.directoriesDiffer(base, URL(fileURLWithPath: "/tmp/CONJOYN-DIRTEST")))
    }

    func testDirectoriesDifferResolvesSymlinks() throws {
        // A real directory and a symlink that points at it describe the same place. (macOS only
        // canonicalizes symlinks for paths that actually exist, so the test uses real ones — the
        // production folders are always real directories chosen via NSOpenPanel.)
        let real = tmpDir.appendingPathComponent("realdir", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = tmpDir.appendingPathComponent("linkdir")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        XCTAssertFalse(QueueManager.directoriesDiffer(real, link))
    }

    func testDirectoriesDifferTrueForGenuinelyDifferent() {
        XCTAssertTrue(QueueManager.directoriesDiffer(
            URL(fileURLWithPath: "/tmp/folderA"), URL(fileURLWithPath: "/tmp/folderB")))
    }

    func testReassignMovesPendingJobsPreservingStem() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "FlightA.mp4"))
        manager.addJob(makeJob(outputName: "FlightB.mp4"))

        let newFolder = tmpDir.appendingPathComponent("NewOut", isDirectory: true)
        manager.reassignPendingDestinations(to: newFolder)

        for job in manager.jobs {
            XCTAssertEqual(job.destinationURL.deletingLastPathComponent().path, newFolder.path,
                           "pending job moved to the new folder")
        }
        // Filename stems are preserved.
        XCTAssertEqual(manager.jobs.map { $0.destinationURL.lastPathComponent }.sorted(),
                       ["FlightA.mp4", "FlightB.mp4"])
    }

    func testReassignSuffixesTwoPendingJobsSharingAStem() throws {
        let manager = makeManager()
        // Two distinct jobs that would collapse to the same name in the new folder.
        manager.addJob(makeJob(outputName: "Sub1/Clip.mp4"))
        manager.addJob(makeJob(outputName: "Sub2/Clip.mp4"))

        let newFolder = tmpDir.appendingPathComponent("Merged", isDirectory: true)
        manager.reassignPendingDestinations(to: newFolder)

        let names = manager.jobs.map { $0.destinationURL.lastPathComponent }.sorted()
        XCTAssertEqual(names, ["Clip (1).mp4", "Clip.mp4"], "second collision gets a counter suffix")
    }

    func testReassignAvoidsCollisionWithNonPendingDestination() throws {
        let manager = makeManager()
        let newFolder = tmpDir.appendingPathComponent("Dest", isDirectory: true)

        // A completed job already owns Dest/Clip.mp4 — its destination must not be clobbered.
        var done = makeJob(outputName: "Whatever.mp4", status: .completed)
        done.destinationURL = newFolder.appendingPathComponent("Clip.mp4")
        manager.addJob(done)
        let doneID = manager.jobs[0].id

        manager.addJob(makeJob(outputName: "Clip.mp4"))   // pending, same stem

        manager.reassignPendingDestinations(to: newFolder)

        let doneJob = manager.jobs.first { $0.id == doneID }!
        XCTAssertEqual(doneJob.destinationURL.lastPathComponent, "Clip.mp4",
                       "finished job's destination untouched")
        let pendingJob = manager.jobs.first { $0.status == .pending }!
        XCTAssertEqual(pendingJob.destinationURL.lastPathComponent, "Clip (1).mp4",
                       "pending job avoids the finished job's path")
    }

    func testReassignNeverModifiesNonPendingJobs() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Active.mp4"))
        manager.addJob(makeJob(outputName: "Done.mp4"))
        manager.addJob(makeJob(outputName: "Failed.mp4"))
        manager.jobs[0].status = .active
        manager.jobs[1].status = .completed
        manager.jobs[2].status = .failed("x")

        let originals = manager.jobs.map { $0.destinationURL.path }

        manager.reassignPendingDestinations(to: tmpDir.appendingPathComponent("Other"))

        XCTAssertEqual(manager.jobs.map { $0.destinationURL.path }, originals,
                       "active/completed/failed destinations are never re-pointed")
    }

    func testReassignPersistsNewPaths() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Flight.mp4"))
        let newFolder = tmpDir.appendingPathComponent("Persisted", isDirectory: true)
        manager.reassignPendingDestinations(to: newFolder)

        // A fresh manager on the same store restores the re-pointed destination.
        let reloaded = makeManager()
        XCTAssertEqual(reloaded.jobs.count, 1)
        XCTAssertEqual(reloaded.jobs[0].destinationURL.deletingLastPathComponent().path, newFolder.path)
    }

    // MARK: - Queue management operations

    func testRemoveJobOnlyRemovesNonActive() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Pending.mp4"))
        manager.addJob(makeJob(outputName: "Active.mp4"))
        manager.jobs[1].status = .active

        manager.removeJob(manager.jobs[1].id)   // active → refused
        XCTAssertEqual(manager.jobs.count, 2)

        manager.removeJob(manager.jobs[0].id)   // pending → removed
        XCTAssertEqual(manager.jobs.count, 1)
        XCTAssertEqual(manager.jobs[0].displayName, "Active.mp4")
    }

    func testRetryJobResetsFailedAndCancelledToPending() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Failed.mp4"))
        manager.addJob(makeJob(outputName: "Cancelled.mp4"))
        manager.jobs[0].status = .failed("nope")
        manager.jobs[0].progress = 0.9
        manager.jobs[1].status = .cancelled

        manager.retryJob(manager.jobs[0].id)
        manager.retryJob(manager.jobs[1].id)

        XCTAssertTrue(manager.jobs.allSatisfy { $0.status == .pending })
        XCTAssertEqual(manager.jobs[0].progress, 0, "retry resets progress")
    }

    func testClearFinishedJobsKeepsOnlyUnfinished() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        manager.addJob(makeJob(outputName: "B.mp4"))
        manager.addJob(makeJob(outputName: "C.mp4"))
        manager.jobs[0].status = .completed
        manager.jobs[1].status = .failed("x")
        // jobs[2] stays pending

        manager.clearFinishedJobs()
        XCTAssertEqual(manager.jobs.map(\.displayName), ["C.mp4"])
    }

    func testCancelAllPendingMarksPendingCancelled() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        manager.addJob(makeJob(outputName: "B.mp4"))
        manager.jobs[1].status = .completed

        manager.cancelAllPending()
        XCTAssertEqual(manager.jobs[0].status, .cancelled)
        XCTAssertEqual(manager.jobs[1].status, .completed, "finished jobs are untouched")
    }

    // MARK: - Computed summaries

    func testStatusSummaryAndCounts() throws {
        let manager = makeManager()
        XCTAssertEqual(manager.statusSummary, "Queue empty")
        XCTAssertFalse(manager.hasPendingJobs)

        manager.addJob(makeJob(outputName: "A.mp4"))
        manager.addJob(makeJob(outputName: "B.mp4"))
        manager.jobs[1].status = .completed

        XCTAssertEqual(manager.pendingCount, 1)
        XCTAssertEqual(manager.completedCount, 1)
        XCTAssertTrue(manager.hasPendingJobs)
        XCTAssertEqual(manager.statusSummary, "1 job waiting")
    }

    /// The footer outcome bar paints completed jobs by verification tier, not merely "joined", so a
    /// joined-but-still-verifying file reads amber (awaiting) rather than a premature green. Green is
    /// reserved for a passed verification (a passing-but-flagged `warning` still counts as green);
    /// a verify failure rides the red failure segment. `completedCount` is the sum of the three tiers.
    func testCompletedJobsBucketByVerificationTier() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "Verified.mp4"))
        manager.addJob(makeJob(outputName: "Verifying.mp4"))
        manager.addJob(makeJob(outputName: "Unverified.mp4"))
        manager.addJob(makeJob(outputName: "Flagged.mp4"))
        manager.addJob(makeJob(outputName: "VerifyFailed.mp4"))

        for i in manager.jobs.indices { manager.jobs[i].status = .completed }
        manager.jobs[0].verificationStatus = .verified
        manager.jobs[1].verificationStatus = .verifying
        manager.jobs[2].verificationStatus = .unverified
        manager.jobs[3].verificationStatus = .warning("minor delta")
        manager.jobs[4].verificationStatus = .failed("hash mismatch")

        XCTAssertEqual(manager.completedCount, 5, "all five joins finished")
        // Green only for a passed (or passed-but-flagged) check.
        XCTAssertEqual(manager.verifiedCount, 2, "verified + warning are the green tier")
        // Amber: still being checked OR written but not yet checked — never a premature green.
        XCTAssertEqual(manager.awaitingVerificationCount, 2, "verifying + unverified are amber")
        // Red: a check that actually failed.
        XCTAssertEqual(manager.verifyFailedCount, 1, "a verify failure is the red tier")
        XCTAssertEqual(
            manager.verifiedCount + manager.awaitingVerificationCount + manager.verifyFailedCount,
            manager.completedCount,
            "the three verification tiers partition the completed jobs"
        )
    }

    /// The row's single bar folds verification into the produce pipeline: produce (join+move, via
    /// `progress`) fills `[0, producePortion]`, then verify (`verificationProgress`) fills the rest,
    /// so the bar hits 100% only once verified — and the produce→verify hand-off is continuous (no
    /// backward jump).
    func testLifecycleFractionFoldsVerifyIntoOneContinuousBar() throws {
        let p = ConversionJob.producePortion
        var job = makeJob(outputName: "Flight.mp4")

        // Pending: empty track.
        XCTAssertEqual(job.lifecycleFraction, 0, accuracy: 0.0001)

        // Producing (join/move) caps at the produce slice so verify has headroom.
        job.status = .active
        job.progress = 0.5
        XCTAssertEqual(job.lifecycleFraction, 0.5 * p, accuracy: 0.0001)
        job.progress = 1.0
        XCTAssertEqual(job.lifecycleFraction, p, accuracy: 0.0001,
                       "produce tops out at producePortion, not 1.0")

        // Verify begins exactly where produce ended — continuous, no jump.
        job.status = .completed
        job.verificationStatus = .verifying
        job.verificationProgress = 0
        XCTAssertEqual(job.lifecycleFraction, p, accuracy: 0.0001,
                       "verify starts at the produce hand-off point")
        job.verificationProgress = 1.0
        XCTAssertEqual(job.lifecycleFraction, 1.0, accuracy: 0.0001,
                       "a full verify reaches 100%")

        // A passed verification (terminal) shows full; the green is the bar's fill, this is the width.
        job.verificationStatus = .verified
        XCTAssertEqual(job.lifecycleFraction, 1.0, accuracy: 0.0001)

        // A hard join failure fills the whole track (painted red by the fill).
        job.status = .failed("boom")
        XCTAssertEqual(job.lifecycleFraction, 1.0, accuracy: 0.0001)
    }

    func testOverallProgressCountsFinishedPlusActive() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        manager.addJob(makeJob(outputName: "B.mp4"))
        manager.jobs[0].status = .completed
        manager.jobs[1].status = .active
        manager.jobs[1].progress = 0.5

        // (1 finished + 0.5 active) / 2 jobs = 0.75
        XCTAssertEqual(manager.overallProgress, 0.75, accuracy: 0.0001)
    }

    // MARK: - ETA readout (queue time-remaining)

    func testFormattedCoarseDuration() {
        XCTAssertEqual(formattedCoarseDuration(30), "< 1 min")     // sub-minute collapses
        XCTAssertEqual(formattedCoarseDuration(120), "~2 min")
        XCTAssertEqual(formattedCoarseDuration(3_700), "~1h 1m")   // 1h 1m 40s → hours + whole minutes
    }

    func testRemainingQueueSecondsNilWhenIdle() {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        // A queued-but-not-processing manager shows no readout.
        XCTAssertNil(manager.remainingQueueSeconds(at: Date()))
    }

    func testRemainingQueueSecondsLiveExtrapolationForActiveJob() {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        manager.jobs[0].status = .active
        manager.jobs[0].progress = 0.5
        manager.jobs[0].startedAt = start
        manager.currentJobId = manager.jobs[0].id
        manager.isProcessing = true

        // 60s elapsed at 50% → 120s total → 60s remaining; no pending jobs to add on top.
        let remaining = manager.remainingQueueSeconds(at: start.addingTimeInterval(60))
        XCTAssertNotNil(remaining)
        XCTAssertEqual(remaining!, 60, accuracy: 0.5)
    }

    func testRemainingQueueSecondsFallsBackToHistoricalEstimateBeforeFivePercent() {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        manager.jobs[0].status = .active
        manager.jobs[0].progress = 0.02      // below the 5% live-extrapolation floor
        manager.jobs[0].startedAt = start
        manager.currentJobId = manager.jobs[0].id
        manager.isProcessing = true
        manager.currentJobEstimate = ConversionEstimate(
            totalBytes: 0, totalDurationSeconds: 0, clipCount: 1,
            estimatedSeconds: 200, speedMultiplier: 15, confidence: .low
        )

        // Live formula returns nil this early, so the pre-job historical estimate stands in.
        let remaining = manager.remainingQueueSeconds(at: start.addingTimeInterval(2))
        XCTAssertEqual(remaining!, 200, accuracy: 0.5)
    }

    func testRemainingQueueSecondsAddsPendingJobs() throws {
        let manager = makeManager()
        let bytes = 12 * 1024 * 1024   // 12 MiB per job; real files so totalSourceBytes is nonzero
        manager.addJob(try makeSizedJob(outputName: "Active.mp4", totalBytes: bytes))
        manager.addJob(try makeSizedJob(outputName: "Waiting.mp4", totalBytes: bytes))  // stays pending
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        manager.jobs[0].status = .active
        manager.jobs[0].progress = 0.5
        manager.jobs[0].startedAt = start
        manager.currentJobId = manager.jobs[0].id
        manager.isProcessing = true

        // Active job alone is ~60s remaining; the still-pending job must add a positive estimate.
        let remaining = manager.remainingQueueSeconds(at: start.addingTimeInterval(60))
        XCTAssertNotNil(remaining)
        XCTAssertGreaterThan(remaining!, 60)
    }

    /// The whole-queue ETA must weigh pending jobs by their byte size (jobs run sequentially and the
    /// join is I/O-bound), so doubling a pending job's bytes roughly doubles the time it contributes.
    func testRemainingQueueSecondsWeightsPendingBySize() throws {
        let base = 10 * 1024 * 1024   // 10 MiB
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        func total(pendingBytes: Int) throws -> TimeInterval {
            // A fresh storage dir per manager — sharing one would let queue.json persistence leak
            // stale jobs from a prior call into this manager's pending set.
            let manager = QueueManager(storageDirectory: tmpDir.appendingPathComponent(UUID().uuidString))
            manager.addJob(try makeSizedJob(outputName: "Active.mp4", totalBytes: base))
            manager.addJob(try makeSizedJob(outputName: "Pending.mp4", totalBytes: pendingBytes))
            manager.jobs[0].status = .active
            manager.jobs[0].progress = 0.5
            manager.jobs[0].startedAt = start
            manager.currentJobId = manager.jobs[0].id
            manager.isProcessing = true
            return try XCTUnwrap(manager.remainingQueueSeconds(at: start.addingTimeInterval(60)))
        }

        // Active contributes a fixed ~60s; only the pending portion scales with bytes.
        let small = try total(pendingBytes: base)
        let large = try total(pendingBytes: base * 2)
        let smallPending = small - 60
        let largePending = large - 60
        XCTAssertEqual(largePending, smallPending * 2, accuracy: smallPending * 0.05,
                       "doubling pending bytes ~doubles its ETA contribution")
    }

    /// Regression (2026-06-17): the whole-queue ETA must not swing when the active job crosses from
    /// its fast ffmpeg-join phase into the un-progress-tracked staged-move/verify tail. Previously the
    /// pending estimate borrowed a *live* throughput sampled off the active job (`activeBytes ×
    /// progress / elapsed`), which collapsed toward zero while "Verifying…" (progress frozen at 1.0,
    /// elapsed climbing) and blew the readout up to hours, then crashed back to minutes on the next
    /// fast job. The pending portion is now driven only by historical effective throughput, so it is
    /// identical regardless of the active job's phase.
    func testRemainingQueueSecondsPendingStableAcrossActiveJobPhase() throws {
        let base = 10 * 1024 * 1024
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        func total(activeProgress: Double) throws -> TimeInterval {
            let manager = QueueManager(storageDirectory: tmpDir.appendingPathComponent(UUID().uuidString))
            manager.addJob(try makeSizedJob(outputName: "Active.mp4", totalBytes: base))
            manager.addJob(try makeSizedJob(outputName: "Pending.mp4", totalBytes: base * 4))  // stays pending
            manager.jobs[0].status = .active
            manager.jobs[0].progress = activeProgress
            manager.jobs[0].startedAt = start
            manager.currentJobId = manager.jobs[0].id
            manager.isProcessing = true
            return try XCTUnwrap(manager.remainingQueueSeconds(at: start.addingTimeInterval(60)))
        }

        // Mid-join: 60s elapsed at 50% → active contributes ~60s on top of the pending estimate.
        let midJoin = try total(activeProgress: 0.5)
        // Verifying: progress frozen at 1.0 → active contributes 0; only the pending estimate remains.
        let verifying = try total(activeProgress: 1.0)

        // The pending portion is identical in both — the readout no longer collapses/explodes by phase.
        XCTAssertEqual(midJoin - 60, verifying, accuracy: max(verifying * 0.01, 0.5),
                       "pending ETA must not depend on the active job's phase")
        XCTAssertGreaterThan(verifying, 0)
    }

    /// The pending estimate must extrapolate from **this run's observed pace** once a job has
    /// completed — a slow run (cold drive) should read slower than the optimistic steady-state
    /// default, exactly as the user asked ("first file's bytes/time → remaining bytes").
    func testRemainingQueueSecondsUsesObservedSessionPaceForPending() throws {
        let manager = QueueManager(storageDirectory: tmpDir.appendingPathComponent(UUID().uuidString))
        let pendingBytes = 100 * 1024 * 1024   // 100 MiB still pending
        manager.addJob(try makeSizedJob(outputName: "Pending.mp4", totalBytes: pendingBytes))
        manager.jobs[0].status = .pending
        manager.isProcessing = true
        // Simulate one completed job this run at a slow ~10 MiB/s observed pace.
        manager.sessionBytesDone = Int64(50 * 1024 * 1024)
        manager.sessionSecondsDone = 5                      // 50 MiB in 5s → 10 MiB/s

        // 100 MiB ÷ 10 MiB/s = ~10s — far above the ~0.8s the 120 MiB/s default would predict.
        let remaining = try XCTUnwrap(manager.remainingQueueSeconds(at: Date()))
        XCTAssertEqual(remaining, 10, accuracy: 1.0,
                       "pending ETA should extrapolate from the observed session pace, not the default")
    }

    // MARK: - Failure hardening (retry classification + staged move)

    func testRetriableJoinErrorClassification() {
        // Transient I/O hiccups → retry.
        XCTAssertTrue(QueueManager.isRetriableJoinError(FFmpegWrapper.FFmpegError.conversionFailed("Error closing file: Input/output error")))
        XCTAssertTrue(QueueManager.isRetriableJoinError(StreamParameterGuard.GuardError.probeFailed("exit code 1 for DJI_0108.MP4")))
        // A Foundation file-I/O error (e.g. during the move) is unknown → treat as transient.
        XCTAssertTrue(QueueManager.isRetriableJoinError(CocoaError(.fileWriteVolumeReadOnly)))

        // Deterministic errors → never retry.
        XCTAssertFalse(QueueManager.isRetriableJoinError(FFmpegWrapper.FFmpegError.cancelled))
        XCTAssertFalse(QueueManager.isRetriableJoinError(FFmpegWrapper.FFmpegError.ffmpegNotFound))
        XCTAssertFalse(QueueManager.isRetriableJoinError(FFmpegWrapper.FFmpegError.invalidInput("Nothing to export")))
        XCTAssertFalse(QueueManager.isRetriableJoinError(StreamParameterGuard.GuardError.incompatible("codec mismatch")))
        XCTAssertFalse(QueueManager.isRetriableJoinError(StreamParameterGuard.GuardError.noVideoStream("DJI_0001.MP4")))
    }

    func testMoveIntoPlaceReplacesExistingDestination() async throws {
        let src = tmpDir.appendingPathComponent("staged.mp4")
        let dest = tmpDir.appendingPathComponent("final.mp4")
        try Data("joined".utf8).write(to: src)
        try Data("stale".utf8).write(to: dest)   // a pre-existing file must be replaced

        try await QueueManager.moveIntoPlace(from: src, to: dest)

        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "source consumed by the move")
        XCTAssertEqual(try String(contentsOf: dest, encoding: .utf8), "joined", "destination holds the moved file")
    }

    func testMoveIntoPlaceStreamsProgressAndCopiesBytesIntact() async throws {
        // Multi-chunk payload (>8 MB chunk size) so the streamed copy reports several fractions.
        let payload = Data((0..<(20 * 1024 * 1024)).map { UInt8($0 & 0xFF) })
        let src = tmpDir.appendingPathComponent("staged-big.mp4")
        let dest = tmpDir.appendingPathComponent("final-big.mp4")
        try payload.write(to: src)

        // @Sendable progress sink (the callback fires on the detached copy task).
        final class Sink: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var values: [Double] = []
            func record(_ v: Double) { lock.lock(); values.append(v); lock.unlock() }
        }
        let sink = Sink()

        try await QueueManager.moveIntoPlace(from: src, to: dest) { sink.record($0) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: src.path), "source consumed by the move")
        XCTAssertEqual(try Data(contentsOf: dest), payload, "every byte copied intact")

        let values = sink.values
        XCTAssertGreaterThan(values.count, 2, "progress reported across multiple chunks")
        XCTAssertEqual(values.last, 1.0, "progress ends at 1.0")
        XCTAssertEqual(values, values.sorted(), "progress is monotonically non-decreasing")
    }

    // MARK: - Job-level aggregates

    func testTotalContentDurationSeconds() {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4", seconds: 45))   // 2 clips × 45s = 90s
        XCTAssertEqual(manager.jobs[0].totalContentDurationSeconds, 90, accuracy: 0.001)
    }

    func testEstimatedFrameCountNilWithoutStreamInfo() {
        // Default clips carry no streamInfo → no frame-rate → nil (treated as "no estimate").
        let job = makeJob(outputName: "A.mp4")
        XCTAssertNil(job.estimatedFrameCount)
    }

    func testEstimatedFrameCountSumsWhenFrameRateKnown() {
        var job = ConversionJob(
            folderName: "100MEDIA",
            sourceFolderURL: tmpDir,
            clips: [makeClip(seconds: 10, index: 0, fps: 30), makeClip(seconds: 5, index: 1, fps: 30)],
            settings: ConversionSettings(),
            destinationURL: tmpDir.appendingPathComponent("A.mp4")
        )
        job.status = .pending
        // (10s + 5s) × 30 fps = 450 frames
        XCTAssertEqual(job.estimatedFrameCount, 450)
    }

    // MARK: - Security-scoped access result semantics

    func testAccessResultGrantedFlag() {
        XCTAssertTrue(QueueManager.AccessResult.newlyGranted.wasGranted)
        XCTAssertTrue(QueueManager.AccessResult.alreadyActive.wasGranted)
        XCTAssertFalse(QueueManager.AccessResult.denied.wasGranted)
    }

    // MARK: - Task 3.3 — SRT stitched into the join pipeline (real ffmpeg; skips without it)

    /// A successful join emits a single re-timed `.SRT` sidecar next to the output, with the second
    /// segment's cue offset by the first segment's *decoded* duration (proving the wiring uses the
    /// ffprobe-backed stitch, not cue math).
    func testJoinWritesStitchedSRTSidecar() async throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }

        // Two real, joinable segments (identical params) with segment-relative sidecars.
        let video1 = tmpDir.appendingPathComponent("DJI_0001.mp4")
        let video2 = tmpDir.appendingPathComponent("DJI_0002.mp4")
        try generateClip(ffmpeg: ffmpeg, seconds: 2, to: video1)
        try generateClip(ffmpeg: ffmpeg, seconds: 3, to: video2)
        let srt1 = tmpDir.appendingPathComponent("DJI_0001.srt")
        let srt2 = tmpDir.appendingPathComponent("DJI_0002.srt")
        try "1\n00:00:00,000 --> 00:00:01,000\nseg1-cueA\n\n2\n00:00:01,500 --> 00:00:01,800\nseg1-cueB\n"
            .write(to: srt1, atomically: true, encoding: .utf8)
        try "1\n00:00:00,000 --> 00:00:01,000\nseg2-cueA\n"
            .write(to: srt2, atomically: true, encoding: .utf8)

        let manager = makeManager()
        let job = makeRealJob(outputName: "Joined.mp4", segments: [(video1, srt1), (video2, srt2)])
        manager.addJob(job)

        let outputs = try await manager.processConcatenateJob(job, jobId: job.id)

        // Video joined.
        XCTAssertEqual(outputs, [job.destinationURL])
        XCTAssertTrue(FileManager.default.fileExists(atPath: job.destinationURL.path), "joined video missing")

        // Sidecar written next to it, sharing the output stem.
        let sidecar = tmpDir.appendingPathComponent("Joined.SRT")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sidecar.path), "stitched .SRT missing")

        let cues = SRTParser.parse(try String(contentsOf: sidecar, encoding: .utf8)).cues
        XCTAssertEqual(cues.count, 3)
        XCTAssertEqual(cues.map(\.index), [1, 2, 3], "global renumbering across segments")
        // Segment 2's lone cue lands at ~clip 1's real duration (~2000 ms), not at its own 0.
        XCTAssertEqual(Double(cues[2].startMilliseconds), 2_000, accuracy: 250,
                       "second segment offset must come from clip 1's decoded duration")
    }

    /// When no segment carries a sidecar, the join still succeeds and **no** `.SRT` is written.
    func testJoinWithoutSidecarsWritesNoSRT() async throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg), resolver.path(for: .ffprobe) != nil else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }

        let video1 = tmpDir.appendingPathComponent("DJI_0001.mp4")
        let video2 = tmpDir.appendingPathComponent("DJI_0002.mp4")
        try generateClip(ffmpeg: ffmpeg, seconds: 1, to: video1)
        try generateClip(ffmpeg: ffmpeg, seconds: 1, to: video2)

        let manager = makeManager()
        let job = makeRealJob(outputName: "NoTelemetry.mp4", segments: [(video1, nil), (video2, nil)])
        manager.addJob(job)

        _ = try await manager.processConcatenateJob(job, jobId: job.id)

        XCTAssertTrue(FileManager.default.fileExists(atPath: job.destinationURL.path), "joined video missing")
        let sidecar = tmpDir.appendingPathComponent("NoTelemetry.SRT")
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path),
                       "no sidecars in → no .SRT out")
    }

    // MARK: - Real-media helpers

    /// A job whose clips point at real on-disk files (so ffprobe/concat work end-to-end).
    private func makeRealJob(outputName: String, segments: [(video: URL, srt: URL?)]) -> ConversionJob {
        let clips = segments.enumerated().map { index, pair in
            DJIClip(
                videoURL: pair.video,
                srtURL: pair.srt,
                index: index,
                stem: pair.video.deletingPathExtension().lastPathComponent,
                duration: CMTime(seconds: 1, preferredTimescale: 600)
            )
        }
        var job = ConversionJob(
            folderName: "100MEDIA",
            sourceFolderURL: tmpDir,
            clips: clips,
            settings: ConversionSettings(),
            destinationURL: tmpDir.appendingPathComponent(outputName)
        )
        job.status = .pending
        return job
    }

    // MARK: - Manual timecode override (Commit 1)

    /// Override set → `resolveJoinMetadata` returns the override string, not the resolver TC.
    func testResolveJoinMetadataUsesOverrideWhenSet() {
        let manager = makeManager()
        var job = makeJob(outputName: "Override.mp4")
        job.timecodeStringOverride = "01:00:00:00"
        manager.addJob(job)

        let metadata = manager.resolveJoinMetadata(for: manager.jobs.last!)
        XCTAssertEqual(metadata.timecode, "01:00:00:00",
                       "override string must be passed through verbatim")
    }

    /// Nil override + no date → timecode is nil (nothing stamped).
    func testResolveJoinMetadataNilTimecodeWhenNoOverrideAndNoDate() {
        let manager = makeManager()
        // Clips with no creation_time / SRT / filename date → resolver returns nil date.
        var job = makeJob(outputName: "NoDate.mp4")
        XCTAssertNil(job.timecodeStringOverride, "precondition: override starts nil")
        manager.addJob(job)

        let metadata = manager.resolveJoinMetadata(for: manager.jobs.last!)
        // Default ConversionSettings has preserveTimecode=true, fixCreationDate=true; no date
        // signal → both fields nil.
        XCTAssertNil(metadata.timecode)
        XCTAssertNil(metadata.creationTime)
    }

    /// Invalid override string (e.g. "99:99:99:99") is passed through as-is — no silent correction.
    func testResolveJoinMetadataPassesInvalidOverrideThrough() {
        let manager = makeManager()
        var job = makeJob(outputName: "Invalid.mp4")
        job.timecodeStringOverride = "99:99:99:99"
        manager.addJob(job)

        let metadata = manager.resolveJoinMetadata(for: manager.jobs.last!)
        XCTAssertEqual(metadata.timecode, "99:99:99:99",
                       "invalid override must not be silently corrected")
    }

    /// `updateTimecodeOverride` sets the property on the correct job.
    func testUpdateTimecodeOverrideSetsProperty() {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        let jobID = manager.jobs[0].id

        manager.updateTimecodeOverride(for: jobID, timecode: "02:30:00:00")
        XCTAssertEqual(manager.jobs[0].timecodeStringOverride, "02:30:00:00")
    }

    /// `updateTimecodeOverride` with nil clears the override.
    func testUpdateTimecodeOverrideClearsWithNil() {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        let jobID = manager.jobs[0].id

        manager.updateTimecodeOverride(for: jobID, timecode: "02:30:00:00")
        manager.updateTimecodeOverride(for: jobID, timecode: nil)
        XCTAssertNil(manager.jobs[0].timecodeStringOverride)
    }

    /// `updateTimecodeOverride` with an unknown UUID does not crash and leaves jobs unchanged.
    func testUpdateTimecodeOverrideUnknownUUIDNoCrash() {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        let original = manager.jobs.map(\.timecodeStringOverride)

        // Unknown UUID — must be a no-op.
        manager.updateTimecodeOverride(for: UUID(), timecode: "12:00:00:00")

        XCTAssertEqual(manager.jobs.count, 1, "jobs array length unchanged")
        XCTAssertEqual(manager.jobs[0].timecodeStringOverride, original[0],
                       "existing job's override unmodified")
    }

    /// Override is NOT persisted to queue.json — a reloaded manager must NOT restore it.
    func testTimecodeOverrideIsNotPersisted() throws {
        let manager = makeManager()
        manager.addJob(makeJob(outputName: "A.mp4"))
        let jobID = manager.jobs[0].id
        manager.updateTimecodeOverride(for: jobID, timecode: "03:00:00:00")
        XCTAssertEqual(manager.jobs[0].timecodeStringOverride, "03:00:00:00", "precondition")

        // Explicitly save (mimics what happens on status change, etc.) and reload.
        manager.saveQueue()
        let reloaded = makeManager()

        XCTAssertEqual(reloaded.jobs.count, 1)
        XCTAssertNil(reloaded.jobs[0].timecodeStringOverride,
                     "timecodeStringOverride must never survive a queue.json round-trip")
    }

    private func generateClip(ffmpeg: URL, seconds: Int, to url: URL) throws {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=\(seconds):size=160x120:rate=30",
                       "-pix_fmt", "yuv420p", url.path]
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try p.run()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ffmpeg failed to generate \(seconds)s clip")
    }
}
