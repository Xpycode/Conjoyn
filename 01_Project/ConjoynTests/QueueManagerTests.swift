import XCTest
import CoreMedia
@testable import Conjoyn

/// Tests for the ported `QueueManager` (Wave 1, task 1.7).
///
/// Every test runs against a fresh, throwaway storage directory injected via
/// `QueueManager(storageDirectory:)`, so the suite never reads or mutates the user's real
/// `~/Library/Application Support/DJIjoiner/queue.json`. The keystone is the enqueue→persist→reload
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
