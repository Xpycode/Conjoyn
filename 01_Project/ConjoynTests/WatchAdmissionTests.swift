import XCTest
import CoreMedia
import Combine
@testable import Conjoyn

@MainActor
final class WatchAdmissionTests: XCTestCase {
    private var directories: [URL] = []
    private var suites: [String] = []
    private func directory() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("admission-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        directories.append(url)
        return url
    }
    private func defaults() -> UserDefaults {
        let suite = "admission-" + UUID().uuidString
        suites.append(suite)
        return UserDefaults(suiteName: suite)!
    }
    override func tearDownWithError() throws {
        for url in directories { try? FileManager.default.removeItem(at: url) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }
    private func job(root: URL, entryID: UUID = UUID(), weak: Bool = false) -> ConversionJob {
        let clip = DJIClip(videoURL: root.appendingPathComponent("DJI_0001.MP4"), index: 1,
            stem: "DJI_0001", creationDate: weak ? nil : Date(timeIntervalSince1970: 100),
            duration: CMTime(value: 10, timescale: 1))
        let descriptor = WatchRecordingDescriptor(clips: [.init(cameraFamily: "dji", stem: clip.stem,
            index: 1, variant: nil, recordingNumber: nil, captureDate: clip.creationDate,
            duration: clip.duration, relativePath: "DJI_0001.MP4", settledVideoBytes: 100)])
        var result = ConversionJob(folderName: "source", sourceFolderURL: root, clips: [clip],
            settings: ConversionSettings(), destinationURL: root.appendingPathComponent("joined.mp4"))
        result.watchIdentitySnapshot = WatchIdentitySnapshot(watchEntryID: entryID,
            ledgerNamespace: entryID.uuidString, descriptor: descriptor)
        result.watchAdmissionPending = true
        return result
    }
    private func dependencies() -> WatchFolderManager.RecoveryDependencies {
        var dependencies = WatchFolderManager.RecoveryDependencies()
        dependencies.observe = { _ in AnyCancellable {} }
        dependencies.schedule = { _, _ in AnyCancellable {} }
        return dependencies
    }

    func testQueueFailureDoesNotCommitHistoryAndManualEntryPointsCannotBypassGate() async {
        let root = directory()
        let queue = QueueManager(storageDirectory: directory(), writeQueue: { _, _ in throw CocoaError(.fileWriteOutOfSpace) })
        let pending = job(root: root)
        XCTAssertFalse(queue.addJob(pending))
        var commits = 0
        XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { _ in commits += 1 })
        XCTAssertEqual(commits, 0)
        queue.startQueue()
        queue.retryJob(pending.id)
        await queue.processJob(pending)
        await queue.processQueue()
        XCTAssertEqual(queue.jobs.first?.status, .pending)
        XCTAssertNil(queue.currentJobId)
        XCTAssertEqual(queue.jobs.first?.watchAdmissionPending, true)
        XCTAssertNotNil(queue.persistenceError)
    }

    func testMissingPersistenceURLFailsClosed() {
        let queue = QueueManager(storageDirectory: directory())
        queue.queueFileURL = nil
        let pending = job(root: directory())
        queue.addJob(pending)
        var committed = false
        XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { _ in committed = true })
        XCTAssertFalse(committed)
        XCTAssertNotNil(queue.persistenceError)
    }

    func testLedgerFailurePersistsPendingMarkerAndRestartCommitsBeforeRelease() throws {
        let queueDir = directory(), root = directory(), ledgerDir = directory()
        let queue = QueueManager(storageDirectory: queueDir)
        let pending = job(root: root)
        queue.addJob(pending)
        XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { _ in throw CocoaError(.fileWriteOutOfSpace) })
        let restored = QueueManager(storageDirectory: queueDir)
        XCTAssertEqual(restored.jobs.first?.watchAdmissionPending, true)
        var ledger = ProcessedGroupLedger(storageDirectory: ledgerDir)
        XCTAssertTrue(restored.recoverWatchAdmission(pending.id) { try ledger.commitAdmission($0.identity) })
        XCTAssertEqual(ledger.resolution(for: pending.watchIdentitySnapshot!.identity), .admitted)
        XCTAssertFalse(restored.jobs[0].watchAdmissionBlocked)
        XCTAssertFalse(QueueManager(storageDirectory: queueDir).jobs[0].watchAdmissionBlocked)
    }

    func testFinalQueueWriteFailureKeepsGateAndAlreadyCommittedLedgerRecoversIdempotently() {
        let queueDir = directory(), ledgerDir = directory()
        var writes = 0
        let queue = QueueManager(storageDirectory: queueDir, writeQueue: { data, url in
            writes += 1
            if writes == 3 { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let pending = job(root: directory())
        queue.addJob(pending)
        var ledger = ProcessedGroupLedger(storageDirectory: ledgerDir)
        XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { try ledger.commitAdmission($0.identity) })
        XCTAssertTrue(queue.jobs[0].watchAdmissionBlocked)
        XCTAssertEqual(ledger.resolution(for: pending.watchIdentitySnapshot!.identity), .admitted)
        let restored = QueueManager(storageDirectory: queueDir)
        XCTAssertEqual(restored.jobs[0].watchAdmissionPending, true)
        XCTAssertTrue(restored.recoverWatchAdmission(pending.id) { try ledger.commitAdmission($0.identity) })
        XCTAssertFalse(restored.jobs[0].watchAdmissionBlocked)
    }

    func testDisabledAndRemovedWatchesRecoverAfterRestartButKeepExplicitStartHold() throws {
        for remove in [false, true] {
            let queueDir = directory(), storage = directory(), root = directory(), prefs = defaults()
            let queue = QueueManager(storageDirectory: queueDir)
            queue.isProcessing = true
            let manager = WatchFolderManager(queue: queue, defaults: prefs, storeKey: "admission.entries", baseStorageDirectory: storage,
                recovery: dependencies())
            let bookmark = try WatchFolderEntry.makeBookmark(for: root)
            let entry = WatchFolderEntry(id: UUID(), rootBookmark: bookmark, rootPath: root.path, enabled: false)
            // Persist the entry without launching monitoring or touching production defaults.
            prefs.set(try JSONEncoder().encode([entry]), forKey: "admission.entries")
            let configured = WatchFolderManager(queue: queue, defaults: prefs, storeKey: "admission.entries", baseStorageDirectory: storage,
                recovery: dependencies())
            let pending = job(root: root, entryID: entry.id)
            queue.addJob(pending)
            let path = storage.appendingPathComponent("WatchFolders/" + entry.id.uuidString)
            try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
            let retained = path.appendingPathComponent("retained")
            try Data("history".utf8).write(to: retained)
            if remove { configured.remove(entry.id) } else { configured.setEnabled(entry.id, false) }
            XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
            XCTAssertEqual(queue.jobs[0].watchAdmissionRequiresStart, true)
            let restored = QueueManager(storageDirectory: queueDir)
            restored.isProcessing = true
            let relaunched = WatchFolderManager(queue: restored, defaults: prefs, storeKey: "admission.entries", baseStorageDirectory: storage,
                recovery: dependencies())
            relaunched.resumeAll()
            XCTAssertNil(restored.jobs[0].watchAdmissionPending)
            XCTAssertEqual(restored.jobs[0].watchAdmissionRequiresStart, true)
            XCTAssertEqual(QueueManager(storageDirectory: queueDir).jobs[0].watchAdmissionRequiresStart, true)
            restored.startQueue()
            XCTAssertFalse(restored.jobs[0].watchAdmissionBlocked)
            _ = manager
        }
    }

    func testStartBeforeRepairDoesNotReleasePersistedHold() {
        let queue = QueueManager(storageDirectory: directory())
        queue.isProcessing = true
        let pending = job(root: directory())
        queue.addJob(pending)
        queue.holdWatchAdmissions(entryID: pending.watchIdentitySnapshot!.watchEntryID)
        queue.startQueue()
        XCTAssertEqual(queue.jobs[0].watchAdmissionRequiresStart, true)
        queue.retryJob(pending.id)
        XCTAssertEqual(queue.jobs[0].watchAdmissionRequiresStart, true)
        XCTAssertTrue(queue.recoverWatchAdmission(pending.id) { _ in })
        XCTAssertTrue(queue.jobs[0].watchAdmissionBlocked)
        queue.retryJob(pending.id)
        XCTAssertFalse(queue.jobs[0].watchAdmissionBlocked)
    }

    func testCancelRemoveAndEveryClearInvalidateRetryBeforeLedgerCommit() {
        let actions: [(QueueManager, UUID) -> Void] = [
            { q, _ in q.cancelAllPending() }, { q, id in q.removeJob(id) },
            { q, _ in q.clearPendingJobs() }, { q, _ in q.clearAllJobs() },
            { q, _ in q.stopAllProcessing() },
            { q, _ in q.cancelAllPending(); q.clearFinishedJobs() }
        ]
        for action in actions {
            let queue = QueueManager(storageDirectory: directory())
            let pending = job(root: directory())
            queue.addJob(pending)
            XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { _ in throw CocoaError(.fileWriteOutOfSpace) })
            action(queue, pending.id)
            var commits = 0
            XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { _ in commits += 1 })
            XCTAssertEqual(commits, 0)
        }
    }

    func testCancelledAdmissionCanOnlyBeRecoveredAfterExplicitRetry() {
        let queue = QueueManager(storageDirectory: directory())
        let pending = job(root: directory())
        queue.addJob(pending)
        queue.cancelAllPending()
        XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { _ in XCTFail("Cancelled") })
        queue.retryJob(pending.id)
        XCTAssertTrue(queue.recoverWatchAdmission(pending.id) { _ in })
        XCTAssertFalse(queue.jobs[0].watchAdmissionBlocked)
    }

    func testFailedCancellationAndRemovalSaveRemainsVisible() {
        var fail = false
        let queue = QueueManager(storageDirectory: directory(), writeQueue: { data, url in
            if fail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        })
        let pending = job(root: directory())
        queue.addJob(pending)
        fail = true
        queue.cancelAllPending()
        XCTAssertNotNil(queue.persistenceError)
        queue.removeJob(pending.id)
        XCTAssertNotNil(queue.persistenceError)
        XCTAssertFalse(queue.recoverWatchAdmission(pending.id) { _ in XCTFail("Removed") })
    }

    func testUnrelatedManualJobRunsWhileWatchAdmissionWaits() async {
        let queue = QueueManager(storageDirectory: directory())
        let pending = job(root: directory())
        queue.addJob(pending)
        // An empty manual job fails normal preflight/join, proving the queue traversed it without
        // ever starting the preceding gated watch job. No real media or production storage.
        let manual = ConversionJob(folderName: "manual", sourceFolderURL: directory(), clips: [],
            settings: ConversionSettings(), destinationURL: directory().appendingPathComponent("out.mp4"))
        queue.addJob(manual)
        await queue.processQueue()
        XCTAssertEqual(queue.jobs[0].status, .pending)
        XCTAssertNotEqual(queue.jobs[1].status, .pending)
    }
}

/// Injected probe results carry their own generation, just like DJIFolderReader. These tests
/// drive the production coordinator and real queue/ledger, without synthetic sleeps or ffprobe.
@MainActor
final class WatchMetadataTests: XCTestCase {
    private final class Feed: @unchecked Sendable {
        private let lock = NSLock()
        private var value: WatchDiscovery
        init(_ value: WatchDiscovery) { self.value = value }
        func read() -> WatchDiscovery { lock.lock(); defer { lock.unlock() }; return value }
        func set(_ next: WatchDiscovery) { lock.lock(); value = next; lock.unlock() }
    }
    private actor Probe {
        let feed: Feed
        var pauseNext = false
        var suspended: CheckedContinuation<Void, Never>?
        var observer: CheckedContinuation<Void, Never>?
        init(_ feed: Feed) { self.feed = feed }
        func pause() { pauseNext = true }
        func read() async -> WatchDiscovery {
            let snapshot = feed.read()
            if pauseNext {
                pauseNext = false
                await withCheckedContinuation { continuation in
                    suspended = continuation
                    observer?.resume(); observer = nil
                }
            }
            return snapshot
        }
        func waitUntilSuspended() async {
            if suspended != nil { return }
            await withCheckedContinuation { observer = $0 }
        }
        func release() { suspended?.resume(); suspended = nil }
    }
    private var dirs: [URL] = []
    private var suites: [String] = []
    private func directory() -> URL {
        let value = FileManager.default.temporaryDirectory.appendingPathComponent("metadata-" + UUID().uuidString)
        try! FileManager.default.createDirectory(at: value, withIntermediateDirectories: true)
        dirs.append(value)
        return value
    }
    override func tearDownWithError() throws {
        for dir in dirs { try? FileManager.default.removeItem(at: dir) }
        for suite in suites { UserDefaults(suiteName: suite)?.removePersistentDomain(forName: suite) }
    }
    private func group(_ root: URL, date: Double? = 100, index: Int = 1) -> RecordGroup {
        let stem = String(format: "DJI_%04d", index)
        return RecordGroup(clips: [DJIClip(videoURL: root.appendingPathComponent(stem + ".MP4"),
            index: index, stem: stem, creationDate: date.map { Date(timeIntervalSince1970: $0) },
            duration: CMTime(value: 10, timescale: 1))], groupIndex: index)
    }
    private func discovery(_ groups: [RecordGroup], modified: Double = 1, identifier: String = "1") -> WatchDiscovery {
        WatchDiscovery(groups: groups, generations: Dictionary(uniqueKeysWithValues: groups.flatMap(\.clips).map {
            ($0.videoURL.path, WatchFileGeneration(sample: .init(size: 100, modified: Date(timeIntervalSince1970: modified)), identifier: identifier))
        }))
    }
    private func coordinator(_ feed: Feed, probe: Probe, queue: QueueManager, ledger: URL,
                             entryID: UUID = UUID()) -> WatchFolderCoordinator {
        let suite = "metadata-" + UUID().uuidString
        suites.append(suite)
        queue.isProcessing = true
        return WatchFolderCoordinator(discover: { _ in [] },
            sample: { feed.read().generations[$0.path]?.sample }, now: { Date(timeIntervalSince1970: 100) },
            queue: queue, ledger: ProcessedGroupLedger(storageDirectory: ledger),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: suite)!, key: "root"),
            settings: WatchFolderSettings(enabled: true, requiredStablePolls: 2, quietWindow: 0),
            storageDirectory: ledger, watchEntryID: entryID, ledgerNamespace: entryID.uuidString,
            discoverBound: { _ in await probe.read() },
            fileIdentifier: { feed.read().generations[$0.path]?.identifier })
    }
    private func settle(_ coordinator: WatchFolderCoordinator, root: URL) async {
        await coordinator.reconcile(rootURL: root, rediscover: true)
        await coordinator.reconcile(rootURL: root, rediscover: false)
    }

    func testEqualSizeReplacementWaitsForFreshMetadataWhileProbeStalls() async {
        for sameMtime in [false, true] {
            let root = directory(), history = directory()
            let old = discovery([group(root)])
            let feed = Feed(old), probe = Probe(feed)
            let queue = QueueManager(storageDirectory: directory())
            let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
            await coordinator.reconcile(rootURL: root, rediscover: true)
            await probe.pause()
            // Start a probe of the original generation, then replace it while suspended.
            let refresh = Task { await coordinator.reconcile(rootURL: root, rediscover: true) }
            await probe.waitUntilSuspended()
            let replacement = discovery([group(root, date: 200)], modified: sameMtime ? 1 : 2, identifier: "2")
            feed.set(replacement)
            await coordinator.reconcile(rootURL: root, rediscover: false)
            await coordinator.reconcile(rootURL: root, rediscover: false)
            XCTAssertTrue(queue.jobs.isEmpty, "Settled samples cannot bless cached metadata")
            XCTAssertTrue(coordinator.reviewRecords.isEmpty)
            await probe.release()
            await refresh.value
            XCTAssertTrue(queue.jobs.isEmpty, "A probe spanning replacement must be rejected")
            await settle(coordinator, root: root)
            XCTAssertEqual(queue.jobs.count, 1)
            XCTAssertEqual(queue.jobs.first?.watchIdentitySnapshot?.descriptor.clips.first?.captureMicroseconds, 200_000_000)
        }
    }

    func testUnaffectedCurrentGroupProceedsWhileReplacementRefreshStalls() async {
        let root = directory(), history = directory()
        let first = group(root), second = group(root, date: 200, index: 2)
        let original = discovery([first, second])
        let feed = Feed(original), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: directory())
        let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
        await coordinator.reconcile(rootURL: root, rediscover: true)
        await probe.pause()
        let refresh = Task { await coordinator.sourceDidChange(rootURL: root) }
        await probe.waitUntilSuspended()
        var changed = discovery([group(root, date: 300), second], modified: 2, identifier: "2")
        changed.generations[second.clips[0].videoURL.path] = original.generations[second.clips[0].videoURL.path]
        feed.set(changed)
        await coordinator.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.clips.first?.index, 2)
        await probe.release()
        await refresh.value
        XCTAssertEqual(queue.jobs.count, 1)
    }

    func testRefreshedGroupingReplacesOldMembershipBeforeAdmission() async {
        let root = directory(), history = directory()
        let a = group(root), b = group(root, date: 200, index: 2)
        let merged = RecordGroup(clips: a.clips + b.clips, groupIndex: 1)
        let feed = Feed(discovery([merged])), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: directory())
        let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
        await coordinator.reconcile(rootURL: root, rediscover: true)
        feed.set(discovery([a, b], modified: 2, identifier: "2"))
        await settle(coordinator, root: root)
        XCTAssertEqual(queue.jobs.count, 2)
        XCTAssertEqual(queue.jobs.map { $0.clips.count }, [1, 1])
    }

    func testWeakIdentityReviewBothChoicesSurviveRestartAndStayWeak() async {
        for process in [false, true] {
            let root = directory(), history = directory()
            let feed = Feed(discovery([group(root, date: nil)])), probe = Probe(feed)
            let queue = QueueManager(storageDirectory: directory())
            let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
            await settle(coordinator, root: root)
            XCTAssertTrue(queue.jobs.isEmpty)
            XCTAssertEqual(coordinator.reviewRecords.count, 1)
            guard let record = coordinator.reviewRecords.first else { continue }
            XCTAssertTrue(record.reason.contains("Weak"))
            await coordinator.resolveReview(record.id, as: process ? .processOnce : .alreadyProcessed)
            let restarted = self.coordinator(feed, probe: probe, queue: queue, ledger: history)
            await settle(restarted, root: root)
            XCTAssertEqual(queue.jobs.count, process ? 1 : 0)
            XCTAssertTrue(restarted.reviewRecords.isEmpty)
            let ledger = ProcessedGroupLedger(storageDirectory: history)
            if case .weak = ledger.classify(record.descriptor.identity, legacyFingerprint: "") {} else {
                XCTFail("Explicit resolution must not promote weak evidence")
            }
        }
    }

    func testLegacyReviewDoesNotBlockNewFootageAndRepeatedProcessClickEnqueuesOnce() async {
        let root = directory(), history = directory()
        let ambiguous = group(root), fresh = group(root, date: 200, index: 2)
        var ledger = ProcessedGroupLedger(storageDirectory: history)
        XCTAssertTrue(ledger.insert(ambiguous))
        let feed = Feed(discovery([ambiguous, fresh])), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: directory())
        let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
        await settle(coordinator, root: root)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(coordinator.reviewRecords.count, 1)
        guard let review = coordinator.reviewRecords.first else { return }
        await coordinator.resolveReview(review.id, as: .processOnce)
        await coordinator.resolveReview(review.id, as: .processOnce)
        await coordinator.reconcile(rootURL: root, rediscover: false)
        await coordinator.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 2)
        XCTAssertEqual(Set(queue.jobs.compactMap { $0.watchIdentitySnapshot?.identity.ledgerKey }).count, 2)
    }

    func testChangedDescriptorAndGenerationInvalidateReviewApproval() async {
        for changeDescriptor in [false, true] {
            let root = directory(), history = directory()
            let feed = Feed(discovery([group(root, date: nil)])), probe = Probe(feed)
            let queue = QueueManager(storageDirectory: directory())
            let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
            await settle(coordinator, root: root)
            guard let review = coordinator.reviewRecords.first else { XCTFail("Missing review"); return }
            await coordinator.resolveReview(review.id, as: .processOnce)
            var replacement = discovery([group(root, date: nil)], modified: 2, identifier: "2")
            if changeDescriptor {
                let path = replacement.groups[0].clips[0].videoURL.path
                replacement.generations[path] = .init(sample: .init(size: 200, modified: Date(timeIntervalSince1970: 2)), identifier: "2")
            }
            feed.set(replacement)
            await coordinator.reconcile(rootURL: root, rediscover: false)
            await coordinator.reconcile(rootURL: root, rediscover: false)
            XCTAssertTrue(queue.jobs.isEmpty)
            XCTAssertEqual(coordinator.reviewRecords.count, 1)
        }
    }

    func testDirectRediscoveryInvalidatesSameDescriptorReviewApproval() async {
        let root = directory(), history = directory()
        let feed = Feed(discovery([group(root, date: nil)])), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: directory())
        let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
        await settle(coordinator, root: root)
        guard let review = coordinator.reviewRecords.first else { XCTFail("Missing review"); return }
        await coordinator.resolveReview(review.id, as: .processOnce)
        feed.set(discovery([group(root, date: nil)], modified: 2, identifier: "2"))
        // No cadence pass observes the replacement before rediscovery overwrites the cache.
        await settle(coordinator, root: root)
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertEqual(coordinator.reviewRecords.first?.id, review.id)
    }

    func testReaderGroupingUsesCapturedSizesWithoutRestattingReplacementFiles() {
        let root = directory()
        let a = group(root, date: 100).clips[0]
        let b = group(root, date: 110, index: 2).clips[0]
        // No media exists on disk. Observed cap-sized first segment + adjacent capture times
        // must still group; a live stat would return zero and incorrectly split the recording.
        let groups = DJIFolderReader.group([a, b], observedSizes: [a.videoURL.path: 4_000_000_000,
                                                                  b.videoURL.path: 100])
        XCTAssertEqual(groups.count, 1)
        XCTAssertEqual(groups.first?.clips.count, 2)
    }

    func testReviewCancelAndRelaunchPreserveUnresolvedCase() async {
        let root = directory(), history = directory()
        let feed = Feed(discovery([group(root, date: nil)])), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: directory())
        let first = coordinator(feed, probe: probe, queue: queue, ledger: history)
        await settle(first, root: root)
        // Sheet dismissal performs no manager/coordinator mutation.
        let second = coordinator(feed, probe: probe, queue: queue, ledger: history)
        await settle(second, root: root)
        XCTAssertEqual(first.reviewRecords.first?.id, second.reviewRecords.first?.id)
        XCTAssertEqual(second.reviewRecords.count, 1)
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testRestoredSnapshotAndOldLiveJobExcludeDuplicatesAcrossNewEntryID() async {
        for oldFormat in [false, true] {
            let root = directory(), history = directory(), queueDir = directory()
            let feed = Feed(discovery([group(root)])), probe = Probe(feed)
            let queue = QueueManager(storageDirectory: queueDir)
            let first = coordinator(feed, probe: probe, queue: queue, ledger: history)
            await settle(first, root: root)
            XCTAssertEqual(queue.jobs.count, 1)
            if oldFormat { queue.jobs[0].watchIdentitySnapshot = nil; queue.saveQueue() }
            let restored = QueueManager(storageDirectory: queueDir)
            let readded = coordinator(feed, probe: probe, queue: restored, ledger: directory())
            await settle(readded, root: root)
            XCTAssertEqual(restored.jobs.count, 1)
        }
    }

    func testCancelledUncommittedAdmissionCannotBeRecreatedAfterStorageRepairOrRestart() async {
        let root = directory(), history = directory(), queueDir = directory()
        let feed = Feed(discovery([group(root)])), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: queueDir)
        let first = coordinator(feed, probe: probe, queue: queue, ledger: history)
        // Force the queue-first persistence gate to fail, so no admission can be committed.
        let savedURL = queue.queueFileURL
        queue.queueFileURL = nil
        await settle(first, root: root)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.watchAdmissionPending, true)
        queue.queueFileURL = savedURL
        queue.cancelAllPending()
        await settle(first, root: root)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.status, .cancelled)
        let restored = QueueManager(storageDirectory: queueDir)
        let restarted = coordinator(feed, probe: probe, queue: restored, ledger: history)
        await settle(restarted, root: root)
        XCTAssertEqual(restored.jobs.count, 1)
        XCTAssertEqual(restored.jobs.first?.status, .cancelled)
        XCTAssertNil(ProcessedGroupLedger(storageDirectory: history).resolution(
            for: restored.jobs[0].watchIdentitySnapshot!.identity))
    }

    private actor ProbeCount {
        var count = 0
        func increment() -> Int { count += 1; return count }
    }

    func testActualReaderRetainsChangedOnlyCandidateAndPollReprobesWithoutEvent() async throws {
        let root = directory(), history = directory()
        let file = root.appendingPathComponent("DJI_0001.MP4")
        try Data([1]).write(to: file)
        let queue = QueueManager(storageDirectory: directory())
        queue.isProcessing = true
        let counter = ProbeCount()
        let suite = "metadata-" + UUID().uuidString
        suites.append(suite)
        let coordinator = WatchFolderCoordinator(discover: { _ in [] },
            sample: { WatchFileGeneration.read($0)?.sample }, now: { Date() }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: history),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: suite)!, key: "root"),
            settings: WatchFolderSettings(enabled: true, requiredStablePolls: 2, quietWindow: 0),
            storageDirectory: history,
            discoverBound: { url in
                let result = await DJIFolderReader.read(folder: url, using: FFmpegWrapper(), metadataProbe: { url in
                    if await counter.increment() == 1 { try Data([1, 2]).write(to: url) }
                    return .init(duration: CMTime(value: 10, timescale: 1),
                                 creationDate: Date(timeIntervalSince1970: 100), streamInfo: nil)
                })
                return WatchDiscovery(groups: result.groups, generations: result.metadataGenerations,
                                      retryPaths: result.retryPaths)
            })
        await coordinator.reconcile(rootURL: root, rediscover: true)
        XCTAssertTrue(queue.jobs.isEmpty)
        // No FSEvent and no forced rediscovery: production polling owns the retry.
        await coordinator.reconcile(rootURL: root, rediscover: false)
        await coordinator.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.watchIdentitySnapshot?.descriptor.clips.first?.settledVideoBytes, 2)
        let probes = await counter.count
        XCTAssertEqual(probes, 2)
    }

    private final class WriteFault: @unchecked Sendable {
        private let lock = NSLock()
        private var fail = true
        func recover() { lock.lock(); fail = false; lock.unlock() }
        func write(_ data: Data, _ url: URL) throws {
            lock.lock(); let shouldFail = fail; lock.unlock()
            if shouldFail { throw CocoaError(.fileWriteOutOfSpace) }
            try data.write(to: url, options: .atomic)
        }
    }

    func testReviewWriteFailureRecoversOnPollWithoutPendingJob() async {
        let root = directory(), history = directory()
        let feed = Feed(discovery([group(root, date: nil)])), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: directory())
        queue.isProcessing = true
        let suite = "metadata-" + UUID().uuidString
        suites.append(suite)
        let fault = WriteFault()
        let coordinator = WatchFolderCoordinator(discover: { _ in [] },
            sample: { feed.read().generations[$0.path]?.sample }, now: { Date() }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: history, write: { try fault.write($0, $1) }),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: suite)!, key: "root"),
            settings: WatchFolderSettings(enabled: true, requiredStablePolls: 2, quietWindow: 0),
            storageDirectory: history, discoverBound: { _ in await probe.read() },
            fileIdentifier: { feed.read().generations[$0.path]?.identifier })
        coordinator.reloadHistory = { ProcessedGroupLedger(storageDirectory: history, write: { try fault.write($0, $1) }) }
        await settle(coordinator, root: root)
        guard let review = coordinator.reviewRecords.first else { XCTFail("Missing review"); return }
        await coordinator.resolveReview(review.id, as: .processOnce)
        XCTAssertEqual(coordinator.status, .historyUnavailable)
        XCTAssertTrue(queue.jobs.isEmpty)
        await coordinator.sourceDidChange(rootURL: root)
        fault.recover()
        await coordinator.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(coordinator.reviewRecords.count, 1)
        XCTAssertNotEqual(coordinator.status, .historyUnavailable)
        await coordinator.resolveReview(review.id, as: .processOnce)
        await coordinator.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1)
    }

    func testDisableDuringProbeRejectsLateMetadataAndAdmissions() async {
        let root = directory(), history = directory()
        let feed = Feed(discovery([group(root)])), probe = Probe(feed)
        let queue = QueueManager(storageDirectory: directory())
        let coordinator = coordinator(feed, probe: probe, queue: queue, ledger: history)
        await probe.pause()
        let refresh = Task { await coordinator.reconcile(rootURL: root, rediscover: true) }
        await probe.waitUntilSuspended()
        coordinator.disable()
        await probe.release()
        await refresh.value
        await coordinator.reconcile(rootURL: root, rediscover: false)
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertTrue(coordinator.reviewRecords.isEmpty)
        XCTAssertEqual(coordinator.status, .idle)
    }
}
