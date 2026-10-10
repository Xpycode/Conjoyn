import XCTest
import CoreMedia
@testable import Conjoyn

// MARK: - Watch Folder Coordinator Tests (Wave 5C, task 5.9 + 5.10)

/// Live-shell tests for `WatchFolderCoordinator`, driven through the `reconcile(rootURL:rediscover:)`
/// test seam with fully injected dependencies (stub discover/sample/clock, isolated temp-dir
/// `QueueManager` + `ProcessedGroupLedger`). No FSEvents, no FFmpeg, no real card.
///
/// The headline test is a **regression for the relaunch idempotency bug**: an earlier draft passed
/// the reconciler a fingerprint set that started empty at launch (a separate mirror), so a group
/// that had already been joined in a previous session — whose source clips still sit on the card —
/// read as "fresh" and got re-enqueued forever. The fix sources the set from the ledger, which
/// loads its persisted fingerprints at `init`. These tests fail against the buggy version.
@MainActor
final class WatchFolderCoordinatorTests: XCTestCase {

    // A clock that returns scripted timestamps, one per `reconcile` pass. `@unchecked Sendable`
    // is safe: it's only touched on the @MainActor test thread via the injected `now` closure.
    private final class FakeClock: @unchecked Sendable {
        private let times: [Date]
        private var i = 0
        init(_ times: [Date]) { self.times = times }
        func next() -> Date {
            defer { i += 1 }
            return times[min(i, times.count - 1)]
        }
    }

    // A thread-safe call counter for the injected discover closure (which runs off the main actor
    // inside `withDiscoverTimeout`). `@unchecked Sendable` is safe — all access is lock-guarded.
    private final class CallCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var n = 0
        /// Returns the pre-increment count, then increments. (call 0, call 1, …)
        func bump() -> Int { lock.lock(); defer { n += 1; lock.unlock() }; return n }
        var value: Int { lock.lock(); defer { lock.unlock() }; return n }
    }

    private var tmpDirs: [URL] = []
    private lazy var sourceRoot = freshTmpDir()

    private func freshTmpDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cj.coord.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirs.append(url)
        return url
    }

    override func tearDownWithError() throws {
        for url in tmpDirs { try? FileManager.default.removeItem(at: url) }
        tmpDirs = []
    }

    // MARK: - Fixtures

    private let settings = WatchFolderSettings(
        enabled: true,
        requiredStablePolls: 1,        // one sample = settled, so two passes suffice
        quietWindow: 30.0,
        splitThreshold: 3_900_000_000,
        pollInterval: 0.75
    )

    private func makeGroup() -> RecordGroup {
        let clip = DJIClip(
            videoURL: sourceRoot.appendingPathComponent("DJI_0001.MP4"),
            index: 1,
            variantSuffix: nil,
            stem: "DJI_0001",
            creationDate: Date(timeIntervalSince1970: 1000),
            duration: .zero
        )
        return RecordGroup(clips: [clip], groupIndex: 1)
    }

    /// Builds a coordinator whose group is always discovered, always reads as a small frozen file,
    /// and whose clock advances past the quiet window between pass 1 and pass 2.
    private func makeCoordinator(ledger: ProcessedGroupLedger,
                                 queue: QueueManager,
                                 groups: [RecordGroup]? = nil) -> WatchFolderCoordinator {
        queue.isProcessing = true // Admission tests never launch a media subprocess.
        let discoveredGroups = groups ?? [makeGroup()]
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let clock = FakeClock([t0, t0.addingTimeInterval(31)])   // 31s > quietWindow(30)
        let frozenSample = FileStabilityGate.Sample(size: 800_000_000, modified: t0) // < splitThreshold
        return WatchFolderCoordinator(
            discover: { _ in discoveredGroups },
            sample: { _ in frozenSample },
            now: { clock.next() },
            queue: queue,
            ledger: ledger,
            bookmark: WatchFolderBookmark(
                defaults: UserDefaults(suiteName: "test.coord.\(UUID().uuidString)")!,
                key: "watchFolder.rootBookmark"
            ),
            settings: settings,
            storageDirectory: freshTmpDir()
        )
    }

    func testCorruptV2HistoryBlocksAdmissionDespiteValidV1() async throws {
        let ledgerDir = freshTmpDir()
        let original = Data("[]".utf8)
        let corrupt = Data("corrupt history".utf8)
        try original.write(to: ledgerDir.appendingPathComponent("processed_groups.json"))
        try corrupt.write(to: ledgerDir.appendingPathComponent("processed_groups_v2.json"))
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ProcessedGroupLedger(storageDirectory: ledgerDir), queue: queue)
        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)
        await coord.reconcile(rootURL: root, rediscover: false)
        await coord.reconcile(rootURL: root, rediscover: true)
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertEqual(coord.status, .historyUnavailable)
        XCTAssertEqual(try Data(contentsOf: ledgerDir.appendingPathComponent("processed_groups.json")), original)
        XCTAssertEqual(try Data(contentsOf: ledgerDir.appendingPathComponent("processed_groups_v2.json")), corrupt)
    }

    func testFailedLedgerInsertStopsBatchAndAllLaterPollAdmissions() async {
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir(), write: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        let first = makeGroup()
        let second = RecordGroup(clips: [DJIClip(
            videoURL: sourceRoot.appendingPathComponent("DJI_0002.MP4"), index: 2,
            variantSuffix: nil, stem: "DJI_0002", creationDate: Date(timeIntervalSince1970: 2000), duration: .zero
        )], groupIndex: 2)
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ledger, queue: queue, groups: [first, second])
        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)
        XCTAssertTrue(queue.jobs.isEmpty)
        await coord.reconcile(rootURL: root, rediscover: false)
        // The first job persists as pending admission, with processing gated until history repairs.
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(coord.status, .historyUnavailable)
        XCTAssertEqual(queue.jobs.first?.watchAdmissionPending, true)
        await coord.reconcile(rootURL: root, rediscover: false)
        await coord.reconcile(rootURL: root, rediscover: true)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(coord.status, .historyUnavailable)
        // An unrelated output setting refresh cannot hide the history failure.
        coord.resolveOutputDestination = { .unavailable }
        XCTAssertEqual(coord.status, .historyUnavailable)
    }

    // MARK: - Regression: already-processed group is not re-enqueued after relaunch

    func testLedgeredGroupIsNotReEnqueuedAfterRelaunch() async {
        let ledgerDir = freshTmpDir()
        let group = makeGroup()

        // Simulate a prior session having joined this group (sealed + persisted).
        var seed = ProcessedGroupLedger(storageDirectory: ledgerDir)
        seed.insert(group)

        // Relaunch: a fresh ledger loads the persisted fingerprint from disk.
        let reloaded = ProcessedGroupLedger(storageDirectory: ledgerDir)
        XCTAssertTrue(reloaded.contains(group), "fingerprint must survive relaunch")

        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: reloaded, queue: queue)

        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)   // pass 1
        await coord.reconcile(rootURL: root, rediscover: false)  // pass 2 (quiet elapsed)

        // Legacy history holds for explicit review; it never silently seals v2.
        XCTAssertEqual(coord.reviewRecords.count, 1)
        XCTAssertEqual(queue.jobs.count, 0,
                       "a previously-joined group whose clips remain on the card must not re-enqueue")
    }

    // MARK: - Control: a fresh group enqueues exactly once, then is sealed

    func testFreshGroupEnqueuesOnceAndIsSealed() async {
        let group = makeGroup()
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir())
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ledger, queue: queue)

        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)   // pass 1: settled but not yet quiet
        XCTAssertEqual(queue.jobs.count, 0, "not enqueued before the quiet window elapses")

        await coord.reconcile(rootURL: root, rediscover: false)  // pass 2: quiet window elapsed
        XCTAssertEqual(queue.jobs.count, 1, "ready group enqueues exactly one job")
        XCTAssertEqual(queue.jobs.first?.clips.map(\.stem), group.clips.map(\.stem))

        // A further pass must not double-enqueue — the group is now sealed in the ledger.
        await coord.reconcile(rootURL: root, rediscover: false)  // pass 3
        XCTAssertEqual(queue.jobs.count, 1, "a sealed group must not be enqueued again")
    }

    // MARK: - Output folder (Wave 5D)

    func testOutputFolderRedirectsJoinDestination() async {
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir())
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ledger, queue: queue)
        let output = freshTmpDir()
        coord.resolveOutputDestination = { .resolved(output) }

        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)
        await coord.reconcile(rootURL: root, rediscover: false)

        XCTAssertEqual(queue.jobs.count, 1)
        let parent = queue.jobs.first!.destinationURL.deletingLastPathComponent().resolvingSymlinksInPath()
        XCTAssertEqual(parent, output.resolvingSymlinksInPath(),
                       "with an output folder set, the join must land there, not next to source")
    }

    func testDisappearingOutputPausesWithoutSealingAndRestoresAutomatically() async throws {
        let ledgerDir = freshTmpDir()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ProcessedGroupLedger(storageDirectory: ledgerDir), queue: queue)
        let output = freshTmpDir()
        coord.resolveOutputDestination = { .resolved(output) }
        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)
        try FileManager.default.removeItem(at: output)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertTrue(queue.jobs.isEmpty, "a missing configured output must not enqueue")
        XCTAssertEqual(coord.status, .outputUnavailable)
        XCTAssertFalse(ProcessedGroupLedger(storageDirectory: ledgerDir).contains(makeGroup()))

        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1, "restoring the folder resumes without a source event")
        XCTAssertEqual(queue.jobs.first?.destinationURL.deletingLastPathComponent().resolvingSymlinksInPath(),
                       output.resolvingSymlinksInPath())
    }

    func testFailedBookmarkNeverFallsBackAndReselectionRecovers() async throws {
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()), queue: queue)
        let output = freshTmpDir()
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/unused",
                                    outputBookmark: Data([0, 1, 2]), outputPath: output.path)
        coord.resolveOutputDestination = { entry.outputDestination }
        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertEqual(coord.status, .outputUnavailable)
        coord.resolveOutputDestination = { .resolved(output) }
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertEqual(queue.jobs.first?.destinationURL.deletingLastPathComponent().resolvingSymlinksInPath(),
                       output.resolvingSymlinksInPath())
    }

    func testOutputRemovedDuringAsyncDiscoveryIsRevalidatedBeforeEnqueue() async throws {
        let output = freshTmpDir()
        let root = sourceRoot
        let group = makeGroup()
        let counter = CallCounter()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let clock = FakeClock([t0, t0.addingTimeInterval(31)])
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let suite = "test.coord.discovery.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let coord = WatchFolderCoordinator(
            discover: { _ in
                if counter.bump() == 1 { try? FileManager.default.removeItem(at: output) }
                return [group]
            },
            sample: { _ in FileStabilityGate.Sample(size: 800_000_000, modified: t0) },
            now: { clock.next() }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(defaults: defaults, key: "root"),
            settings: settings, storageDirectory: freshTmpDir())
        coord.resolveOutputDestination = { .resolved(output) }
        await coord.reconcile(rootURL: root, rediscover: true)
        await coord.reconcile(rootURL: root, rediscover: true)
        XCTAssertEqual(counter.value, 2)
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertEqual(coord.status, .outputUnavailable)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1)
    }

    func testNilOutputFolderKeepsJoinNextToSource() async {
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir())
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ledger, queue: queue)   // destination stays unconfigured

        let root = sourceRoot
        await coord.reconcile(rootURL: root, rediscover: true)
        await coord.reconcile(rootURL: root, rediscover: false)

        XCTAssertEqual(queue.jobs.count, 1)
        let parent = queue.jobs.first!.destinationURL.deletingLastPathComponent().resolvingSymlinksInPath()
        XCTAssertEqual(parent, root.resolvingSymlinksInPath(),
                       "with no output folder, the join lands next to the source (v1 default)")
    }

    // MARK: - Hung-discovery recovery (#1): a wedged scan must not permanently latch the watcher

    func testHungDiscoveryTimesOutThenWatcherRecoversAndEnqueues() async {
        let group = makeGroup()
        let counter = CallCounter()
        let t0 = Date(timeIntervalSinceReferenceDate: 2_000_000)
        // One clock tick is consumed per pass that gets past the empty-groups guard. Pass 1 (hung →
        // timeout → empty) consumes none; pass 2 (discovers) consumes t0; pass 3 (poll, quiet) t0+31.
        let clock = FakeClock([t0, t0.addingTimeInterval(31)])
        let frozen = FileStabilityGate.Sample(size: 800_000_000, modified: t0) // < splitThreshold

        // Short discover timeout so the hung first pass abandons quickly.
        var s = settings
        s.discoverTimeout = 0.05

        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = WatchFolderCoordinator(
            discover: { _ in
                // First discovery wedges (a stalled mount / hung ffprobe); later ones recover.
                if counter.bump() == 0 {
                    try? await Task.sleep(nanoseconds: 5_000_000_000) // 5s — abandoned by the timeout
                    return []
                }
                return [group]
            },
            sample: { _ in frozen },
            now: { clock.next() },
            queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(
                defaults: UserDefaults(suiteName: "test.coord.\(UUID().uuidString)")!,
                key: "watchFolder.rootBookmark"
            ),
            settings: s,
            storageDirectory: freshTmpDir()
        )

        let root = sourceRoot

        // Pass 1: discovery hangs → times out (~50 ms) → no enqueue, and crucially the discovery
        // latch is cleared by the `defer`, not stuck `true` forever (the old deadlock).
        await coord.reconcile(rootURL: root, rediscover: true)
        XCTAssertEqual(queue.jobs.count, 0)

        // Pass 2: a *fresh* discovery actually runs — proof the latch was cleared (a permanent latch
        // would drop this pass at the guard before ever calling discover) — and finds the group.
        await coord.reconcile(rootURL: root, rediscover: true)

        // Pass 3: quiet window elapsed → the recovered group settles and enqueues.
        await coord.reconcile(rootURL: root, rediscover: false)

        XCTAssertEqual(queue.jobs.count, 1,
                       "after a hung discovery times out, the watcher recovers and enqueues")
        XCTAssertGreaterThanOrEqual(counter.value, 2,
                                    "a second discovery must have run — the hang did not latch the watcher shut")
    }

    // MARK: - Disable stops cleanly

    func testDisablePersistsDisabledState() {
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir())
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ledger, queue: queue)
        coord.disable()
        XCTAssertEqual(coord.status, .idle)
    }
}
