import XCTest
@testable import Conjoyn

/// Exercises the real load/save entry points using disposable queue files only.
@MainActor
final class QueueRecoveryTests: XCTestCase {
    private var directory: URL!
    private var queueURL: URL { directory.appendingPathComponent("queue.json") }

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("QueueRecoveryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let directory { try FileManager.default.removeItem(at: directory) }
        directory = nil
    }

    private func makeJob() -> ConversionJob {
        ConversionJob(folderName: "Recovery", sourceFolderURL: directory, clips: [],
                      settings: ConversionSettings(), destinationURL: directory.appendingPathComponent("joined.mp4"))
    }

    func testMalformedAndUnknownQueueBytesSurviveReplacementSavesExactly() throws {
        for bytes in [Data([0xff, 0x00, 0x7b, 0x0a]), Data(#"{"futureFormat":42,"jobs":[]}"#.utf8)] {
            try bytes.write(to: queueURL)
            let manager = QueueManager(storageDirectory: directory)
            let recovery = try XCTUnwrap(manager.recoveryState)
            let preserved = try XCTUnwrap(recovery.preservedURL)
            XCTAssertEqual(recovery.originalURL, queueURL)
            XCTAssertEqual(preserved.deletingLastPathComponent(), directory)
            XCTAssertNotEqual(preserved, queueURL)
            XCTAssertTrue(recovery.writesAllowed)
            XCTAssertFalse(recovery.reason.isEmpty)
            XCTAssertTrue(manager.jobs.isEmpty)
            XCTAssertEqual(try Data(contentsOf: preserved), bytes)

            manager.jobs = [makeJob()]
            manager.saveQueue()
            XCTAssertNil(manager.persistenceError)
            XCTAssertEqual(manager.recoveryState, recovery)
            XCTAssertEqual(try Data(contentsOf: preserved), bytes)
            XCTAssertEqual(QueueManager(storageDirectory: directory).jobs.count, 1)
        }
    }

    func testFailedPreservationLeavesOriginalUntouchedAndBlocksEverySaveForLifetime() throws {
        let bytes = Data("broken original queue".utf8)
        try bytes.write(to: queueURL)
        var attempts = 0
        let manager = QueueManager(storageDirectory: directory, preserveUnreadableQueue: { _, _ in
            attempts += 1
            throw CocoaError(.fileWriteNoPermission)
        })
        let recovery = try XCTUnwrap(manager.recoveryState)
        XCTAssertFalse(recovery.writesAllowed)
        XCTAssertNil(recovery.preservedURL)
        XCTAssertEqual(recovery.originalURL, queueURL)
        manager.jobs = [makeJob()]
        manager.saveQueue()
        manager.persistenceError = nil
        manager.saveQueue()
        XCTAssertEqual(attempts, 1)
        XCTAssertEqual(try Data(contentsOf: queueURL), bytes)
        XCTAssertEqual(manager.recoveryState, recovery)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["queue.json"])
    }

    func testRecoveryNoticeSurvivesFailedThenSuccessfulSave() throws {
        let bytes = Data("invalid JSON".utf8)
        try bytes.write(to: queueURL)
        let manager = QueueManager(storageDirectory: directory)
        let recovery = try XCTUnwrap(manager.recoveryState)
        let preserved = try XCTUnwrap(recovery.preservedURL)
        // A non-empty directory deterministically prevents the atomic replacement write.
        try FileManager.default.removeItem(at: queueURL)
        try FileManager.default.createDirectory(at: queueURL, withIntermediateDirectories: false)
        try Data([1]).write(to: queueURL.appendingPathComponent("occupied"))
        manager.saveQueue()
        XCTAssertNotNil(manager.persistenceError)
        XCTAssertEqual(manager.recoveryState, recovery)
        try FileManager.default.removeItem(at: queueURL)
        manager.saveQueue()
        XCTAssertNil(manager.persistenceError)
        XCTAssertEqual(manager.recoveryState, recovery)
        XCTAssertEqual(try Data(contentsOf: preserved), bytes)
    }

    func testRecoveryDestinationCollisionNeverOverwritesExistingBytes() throws {
        let originalBytes = Data("broken current queue".utf8)
        let earlierBytes = Data("earlier recovery bytes".utf8)
        try originalBytes.write(to: queueURL)
        var collidedURL: URL?
        let manager = QueueManager(storageDirectory: directory, preserveUnreadableQueue: { original, recovery in
            // Force a destination collision immediately before the same operation production uses.
            collidedURL = recovery
            try earlierBytes.write(to: recovery, options: .withoutOverwriting)
            try FileManager.default.copyItem(at: original, to: recovery)
        })
        XCTAssertEqual(manager.recoveryState?.writesAllowed, false)
        XCTAssertNil(manager.recoveryState?.preservedURL)
        manager.saveQueue()
        XCTAssertEqual(try Data(contentsOf: queueURL), originalBytes)
        XCTAssertEqual(try Data(contentsOf: XCTUnwrap(collidedURL)), earlierBytes)
    }

    func testRepeatedRecoveriesNeverReplaceAnEarlierBackup() throws {
        let firstBytes = Data("first broken queue".utf8)
        let secondBytes = Data("second broken queue".utf8)
        try firstBytes.write(to: queueURL)
        let first = QueueManager(storageDirectory: directory)
        let firstURL = try XCTUnwrap(first.recoveryState?.preservedURL)
        first.saveQueue()
        try secondBytes.write(to: queueURL)
        let second = QueueManager(storageDirectory: directory)
        let secondURL = try XCTUnwrap(second.recoveryState?.preservedURL)
        second.saveQueue()
        XCTAssertNotEqual(firstURL, secondURL)
        XCTAssertEqual(try Data(contentsOf: firstURL), firstBytes)
        XCTAssertEqual(try Data(contentsOf: secondURL), secondBytes)
    }

    func testReadFailureAlsoBlocksWritesWhenPreservationFails() throws {
        try FileManager.default.createDirectory(at: queueURL, withIntermediateDirectories: false)
        let marker = queueURL.appendingPathComponent("original")
        try Data([7]).write(to: marker)
        let manager = QueueManager(storageDirectory: directory, preserveUnreadableQueue: { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        })
        XCTAssertEqual(manager.recoveryState?.writesAllowed, false)
        manager.saveQueue()
        XCTAssertEqual(try Data(contentsOf: marker), Data([7]))
    }

    func testMissingFileAndValidEmptyQueueDoNotEnterRecovery() throws {
        let firstLaunch = QueueManager(storageDirectory: directory)
        XCTAssertNil(firstLaunch.recoveryState)
        XCTAssertFalse(FileManager.default.fileExists(atPath: queueURL.path))
        firstLaunch.saveQueue()
        let empty = QueueManager(storageDirectory: directory)
        XCTAssertNil(empty.recoveryState)
        XCTAssertTrue(empty.jobs.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["queue.json"])
    }

    func testShipped104QueueLoadsWithoutRecoveryAndCurrentQueueRoundTrips() throws {
        let fixture = Bundle(for: Self.self).url(forResource: "queue-1.0.4", withExtension: "json")
            ?? URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/queue-1.0.4.json")
        try Data(contentsOf: fixture).write(to: queueURL)
        let legacy = QueueManager(storageDirectory: directory)
        XCTAssertNil(legacy.recoveryState)
        XCTAssertEqual(legacy.jobs.count, 2)
        legacy.saveQueue()
        let current = QueueManager(storageDirectory: directory)
        XCTAssertNil(current.recoveryState)
        XCTAssertEqual(current.jobs.map(\.id), legacy.jobs.map(\.id))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["queue.json"])
    }
}
