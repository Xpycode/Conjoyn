import XCTest
import CoreMedia
@testable import Conjoyn

// MARK: - File Identity / TOCTOU guard tests (cookbook #127)

/// Covers the source-identity TOCTOU guard added to the join path: `FileIdentity` capture/verify and
/// the `ConversionJob` enqueue-time snapshot + pre-join re-check that refuse a card swap / file
/// rotation between queueing and joining. Uses real temp files because the whole point is `stat`
/// behaviour against the live filesystem.
final class FileIdentityTests: XCTestCase {

    private var tmpDir: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIdentityTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let tmpDir { try? FileManager.default.removeItem(at: tmpDir) }
        tmpDir = nil
        try super.tearDownWithError()
    }

    @discardableResult
    private func writeFile(_ name: String, _ contents: String = "x") -> URL {
        let url = tmpDir.appendingPathComponent(name)
        try? contents.data(using: .utf8)!.write(to: url)
        return url
    }

    // MARK: - FileIdentity.capture / verify

    func testCaptureThenVerifyMatchesUnchangedFile() {
        let url = writeFile("a.mp4")
        let id = FileIdentity.capture(url)
        XCTAssertNotNil(id)
        XCTAssertEqual(FileIdentity.verify(url: url, against: id!), .matches)
    }

    func testCaptureReturnsNilForMissingFile() {
        XCTAssertNil(FileIdentity.capture(tmpDir.appendingPathComponent("nope.mp4")))
    }

    func testVerifyDetectsDifferentInodeAsMismatch() {
        let url = writeFile("a.mp4")
        let id = FileIdentity.capture(url)!
        // Same device, deliberately different inode → the path now resolves to "a different file".
        let wrong = FileIdentity(device: id.device, inode: id.inode &+ 1)
        XCTAssertEqual(FileIdentity.verify(url: url, against: wrong), .mismatch)
    }

    func testVerifyReportsMissingWhenFileDeletedSinceCapture() {
        let url = writeFile("a.mp4")
        let id = FileIdentity.capture(url)!
        try? FileManager.default.removeItem(at: url)
        XCTAssertEqual(FileIdentity.verify(url: url, against: id), .missingNow)
    }

    // MARK: - ConversionJob enqueue snapshot + pre-join re-check

    private func makeClip(at url: URL, index: Int) -> DJIClip {
        DJIClip(videoURL: url, index: index, stem: "DJI_000\(index)",
                duration: CMTime(seconds: 10, preferredTimescale: 600))
    }

    private func makeJob(clips: [DJIClip]) -> ConversionJob {
        ConversionJob(
            folderName: "100MEDIA",
            sourceFolderURL: tmpDir,
            clips: clips,
            settings: ConversionSettings(),
            destinationURL: tmpDir.appendingPathComponent("out.mp4")
        )
    }

    func testCapturedJobReportsNoMismatchWhenSourcesUnchanged() {
        let a = writeFile("DJI_0001.MP4")
        let b = writeFile("DJI_0002.MP4")
        var job = makeJob(clips: [makeClip(at: a, index: 1), makeClip(at: b, index: 2)])
        job.captureSourceIdentities()
        XCTAssertEqual(job.sourceIdentities.count, 2)
        XCTAssertNil(job.firstSourceIdentityMismatch(), "unchanged sources must pass the guard")
    }

    func testJobWithoutBaselineSkipsTheGuard() {
        // A job restored from a previous session has no captured identities → no baseline to compare,
        // and the relaunch is itself a fresh time-of-check, so the guard must be a no-op (not a fail).
        let a = writeFile("DJI_0001.MP4")
        let job = makeJob(clips: [makeClip(at: a, index: 1)])   // captureSourceIdentities NOT called
        XCTAssertTrue(job.sourceIdentities.isEmpty)
        XCTAssertNil(job.firstSourceIdentityMismatch())
    }

    func testJobFlagsAMissingSegment() {
        let a = writeFile("DJI_0001.MP4")
        var job = makeJob(clips: [makeClip(at: a, index: 1)])
        job.captureSourceIdentities()
        try? FileManager.default.removeItem(at: a)   // segment vanished after enqueue
        XCTAssertEqual(job.firstSourceIdentityMismatch(), "DJI_0001.MP4")
    }

    func testJobFlagsASwappedSegment() throws {
        let a = writeFile("DJI_0001.MP4", "original")
        var job = makeJob(clips: [makeClip(at: a, index: 1)])
        job.captureSourceIdentities()

        // Simulate a card swap / rotation: a *different* file (a distinct inode) now occupies the same
        // path. Rename-over guarantees a different inode than the one captured.
        let replacement = writeFile("replacement.MP4", "different recording entirely")
        try FileManager.default.removeItem(at: a)
        try FileManager.default.moveItem(at: replacement, to: a)

        XCTAssertEqual(job.firstSourceIdentityMismatch(), "DJI_0001.MP4",
                       "a path repointed at different bytes must be refused, not silently joined")
    }

    // MARK: - addJob captures identities in the shared funnel

    @MainActor
    func testAddJobCapturesSourceIdentities() {
        let a = writeFile("DJI_0001.MP4")
        let queue = QueueManager(storageDirectory: tmpDir)
        let job = makeJob(clips: [makeClip(at: a, index: 1)])
        queue.addJob(job)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.sourceIdentities.count, 1,
                       "addJob must snapshot identities so the manual queue is guarded too")
    }
}
