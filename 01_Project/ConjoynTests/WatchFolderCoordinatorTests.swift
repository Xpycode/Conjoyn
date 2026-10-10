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

    // MARK: - Disable stops cleanly

    func testDisablePersistsDisabledState() {
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir())
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = makeCoordinator(ledger: ledger, queue: queue)
        coord.disable()
        XCTAssertEqual(coord.status, .idle)
    }
    // Continuations control both the reader and timeout clock; no timing sleeps or media I/O.
    private actor ControlledWork<Value: Sendable> {
        private var calls: [CheckedContinuation<Value, Never>?] = []
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
        func run() async -> Value {
            await withCheckedContinuation { continuation in
                calls.append(continuation)
                let ready = waiters.filter { calls.count >= $0.0 }
                waiters.removeAll { calls.count >= $0.0 }
                ready.forEach { $0.1.resume() }
            }
        }
        func waitForCalls(_ count: Int) async {
            if calls.count >= count { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }
        func finish(_ index: Int, _ value: Value) {
            let continuation = calls[index]
            calls[index] = nil
            continuation?.resume(returning: value)
        }
        var count: Int { calls.count }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Controlled work did not reach the expected state", file: file, line: line)
    }

    private final class ManualClock: @unchecked Sendable {
        var date = Date(timeIntervalSince1970: 1_000)
    }

    private func controlledCoordinator(reader: ControlledWork<[RecordGroup]>,
                                       delays: ControlledWork<Void>, clock: ManualClock,
                                       queue: QueueManager, budget: WatchDiscoveryBudget? = nil) -> WatchFolderCoordinator {
        queue.isProcessing = true
        let suite = "test.coord.controlled.\(UUID().uuidString)"
        var tunables = settings
        tunables.quietWindow = 0
        let coordinator = WatchFolderCoordinator(discover: { _ in await reader.run() },
            sample: { _ in .init(size: 100, modified: Date(timeIntervalSince1970: 100)) },
            now: { clock.date }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: suite)!, key: "root"),
            settings: tunables, storageDirectory: freshTmpDir(),
            timeoutSleep: { _ in await delays.run() })
        if let budget { coordinator.discoveryBudget = budget }
        return coordinator
    }

    func testEventBurstDuringDiscoveryRunsOneTrailingPassAndRejectsOldResult() async {
        let reader = ControlledWork<[RecordGroup]>()
        let delays = ControlledWork<Void>()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        let coord = controlledCoordinator(reader: reader, delays: delays, clock: ManualClock(), queue: queue)
        let root = sourceRoot
        let first = Task { await coord.reconcile(rootURL: root, rediscover: true) }
        await reader.waitForCalls(1)
        await delays.waitForCalls(1)
        for _ in 0..<8 { await coord.sourceDidChange(rootURL: root) }
        await reader.finish(0, [makeGroup()])
        await first.value
        await reader.waitForCalls(2)
        await delays.waitForCalls(2)
        XCTAssertTrue(queue.jobs.isEmpty, "A result spanning a change event cannot admit its old metadata")
        await reader.finish(1, [])
        // A subsequent poll drains publication without requiring another event.
        await coord.refreshTask?.value
        await coord.reconcile(rootURL: root, rediscover: false)
        let calls = await reader.count
        XCTAssertEqual(calls, 2)
        XCTAssertTrue(queue.jobs.isEmpty)
        await delays.finish(0, ())
        await delays.finish(1, ())
    }

    func testQuietRootTimeoutRetriesFromPollAndCapsUnderlyingWorkers() async {
        let reader = ControlledWork<[RecordGroup]>()
        let delays = ControlledWork<Void>()
        let clock = ManualClock()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        let coord = controlledCoordinator(reader: reader, delays: delays, clock: clock, queue: queue)
        let root = sourceRoot
        let first = Task { await coord.reconcile(rootURL: root, rediscover: true) }
        await reader.waitForCalls(1)
        await delays.waitForCalls(1)
        await delays.finish(0, ())
        await first.value
        XCTAssertEqual(coord.status, .discoveryStalled)
        XCTAssertEqual(coord.discoveryBudget.workerCount, 1)
        clock.date.addTimeInterval(1)
        await coord.reconcile(rootURL: root, rediscover: false)
        await reader.waitForCalls(2)
        await delays.waitForCalls(2)
        await delays.finish(1, ())
        await coord.refreshTask?.value
        clock.date.addTimeInterval(1)
        for _ in 0..<8 { await coord.reconcile(rootURL: root, rediscover: false) }
        let calls = await reader.count
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(coord.discoveryBudget.workerCount, 2, "Timeout must not release underlying work")
        XCTAssertEqual(coord.status, .discoveryStalled)
        // Late abandoned results free a slot but never publish or enqueue.
        await reader.finish(0, [makeGroup()])
        await waitUntil { coord.discoveryBudget.workerCount == 1 }
        XCTAssertTrue(queue.jobs.isEmpty)
        await coord.reconcile(rootURL: root, rediscover: false)
        await reader.waitForCalls(3)
        await delays.waitForCalls(3)
        await reader.finish(2, [makeGroup()])
        await reader.finish(1, [makeGroup()])
        await coord.refreshTask?.value
        await waitUntil { coord.discoveryBudget.workerCount == 0 }
        XCTAssertEqual(queue.jobs.count, 1, "The quiet-root retry admits recovered footage")
        XCTAssertNotEqual(coord.status, .discoveryStalled)
        XCTAssertEqual(coord.discoveryBudget.workerCount, 0)
        await delays.finish(2, ())
    }

    func testDisableFencesSuspendedDiscoveryAndRetainsSlotForReplacement() async {
        let reader = ControlledWork<[RecordGroup]>()
        let delays = ControlledWork<Void>()
        let clock = ManualClock()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        let budget = WatchDiscoveryBudget()
        let old = controlledCoordinator(reader: reader, delays: delays, clock: clock, queue: queue, budget: budget)
        let root = sourceRoot
        let oldPass = Task { await old.reconcile(rootURL: root, rediscover: true) }
        await reader.waitForCalls(1)
        await delays.waitForCalls(1)
        old.disable()
        let replacement = controlledCoordinator(reader: reader, delays: delays, clock: clock, queue: queue, budget: budget)
        let newPass = Task { await replacement.reconcile(rootURL: root, rediscover: true) }
        await reader.waitForCalls(2)
        await delays.waitForCalls(2)
        replacement.disable()
        let third = controlledCoordinator(reader: reader, delays: delays, clock: clock, queue: queue, budget: budget)
        await third.reconcile(rootURL: root, rediscover: true)
        XCTAssertEqual(third.status, .discoveryStalled)
        XCTAssertEqual(budget.workerCount, 2)
        await reader.finish(0, [makeGroup()])
        await reader.finish(1, [makeGroup()])
        await oldPass.value
        await newPass.value
        XCTAssertTrue(queue.jobs.isEmpty)
        XCTAssertEqual(old.status, .idle)
        XCTAssertEqual(replacement.status, .idle)
        XCTAssertEqual(budget.workerCount, 0)
        third.disable()
        await third.reconcile(rootURL: root, rediscover: false)
        let calls = await reader.count
        XCTAssertEqual(calls, 2, "Completion after disable cannot restart discovery")
        await delays.finish(0, ())
        await delays.finish(1, ())
    }

    func testPollInitiatedReprobeDoesNotHoldHealthyResamplingLatch() async {
        final class Samples: @unchecked Sendable {
            var changed = false
        }
        let samples = Samples()
        let reader = ControlledWork<[RecordGroup]>()
        let delays = ControlledWork<Void>()
        let clock = ManualClock()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let stale = makeGroup()
        let healthy = RecordGroup(clips: [DJIClip(videoURL: sourceRoot.appendingPathComponent("DJI_0002.MP4"),
            index: 1, variantSuffix: nil, stem: "DJI_0002", creationDate: Date(timeIntervalSince1970: 2000), duration: .zero)], groupIndex: 2)
        let coord = WatchFolderCoordinator(discover: { _ in await reader.run() },
            sample: { url in .init(size: samples.changed && url.lastPathComponent == "DJI_0001.MP4" ? 200 : 100,
                                  modified: Date(timeIntervalSince1970: 100)) },
            now: { clock.date }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: "test.reprobe.\(UUID().uuidString)")!, key: "root"),
            settings: settings, storageDirectory: freshTmpDir(), timeoutSleep: { _ in await delays.run() })
        let root = sourceRoot
        let initial = Task { await coord.reconcile(rootURL: root, rediscover: true) }
        await reader.waitForCalls(1)
        await delays.waitForCalls(1)
        await reader.finish(0, [stale, healthy])
        await initial.value
        samples.changed = true
        let refresh = Task { await coord.reconcile(rootURL: root, rediscover: false) }
        await reader.waitForCalls(2)
        await delays.waitForCalls(2)
        XCTAssertEqual(coord.discoveryBudget.workerCount, 1, "Generation re-probes share the worker budget")
        clock.date.addTimeInterval(31)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1, "Healthy cached footage must settle while a poll-started re-probe is suspended")
        XCTAssertEqual(queue.jobs.first?.clips.first?.stem, "DJI_0002")
        await delays.finish(1, ())
        await refresh.value
        XCTAssertEqual(coord.status, .discoveryStalled)
        XCTAssertEqual(coord.discoveryBudget.workerCount, 1)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1, "Changed footage cannot use the old cached metadata during timeout")
        coord.disable()
        await reader.finish(1, [stale, healthy])
        await waitUntil { coord.discoveryBudget.workerCount == 0 }
        await delays.finish(0, ())
    }

    func testNewPredecessorBlocksCachedTailWhileUnrelatedVariantSettles() async throws {
        for alternateRoot in [false, true] {
            try await assertPredecessorMembership(deliverEvent: true, omittedByInitialDiscovery: false,
                                                   alternateRoot: alternateRoot)
        }
    }

    func testPollDetectsNewPredecessorWithoutFilesystemEvent() async throws {
        try await assertPredecessorMembership(deliverEvent: false, omittedByInitialDiscovery: false)
    }

    func testSuccessfulDiscoveryOmittingFailedPredecessorCannotAdmitTail() async throws {
        try await assertPredecessorMembership(deliverEvent: false, omittedByInitialDiscovery: true)
    }

    private func assertPredecessorMembership(deliverEvent: Bool, omittedByInitialDiscovery: Bool, alternateRoot: Bool = false) async throws {
        let reader = ControlledWork<[RecordGroup]>()
        let delays = ControlledWork<Void>()
        let clock = ManualClock()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let selected = freshTmpDir()
        let aliasPath = selected.path.hasPrefix("/var/") ? "/private" + selected.path : selected.resolvingSymlinksInPath().path
        let root = alternateRoot ? URL(fileURLWithPath: aliasPath) : selected
        func clip(_ name: String, _ index: Int, _ variant: String) -> DJIClip {
            DJIClip(videoURL: root.appendingPathComponent(name + ".MP4"), index: index,
                variantSuffix: variant, stem: name, creationDate: Date(timeIntervalSince1970: Double(index * 1000)), duration: .zero)
        }
        let tail = clip("DJI_20261010120000_0002_D", 2, "D")
        let predecessor = clip("DJI_20261010115900_0001_D", 1, "D")
        let healthy = clip("DJI_20261010120000_0003_W", 3, "W")
        for item in [tail, healthy] { try Data([0]).write(to: item.videoURL) }
        if omittedByInitialDiscovery { try Data([0]).write(to: predecessor.videoURL) }
        let partial = RecordGroup(clips: [tail], groupIndex: 1)
        let independent = RecordGroup(clips: [healthy], groupIndex: 2)
        let coord = WatchFolderCoordinator(discover: { _ in await reader.run() },
            sample: { url in .init(size: url.lastPathComponent == predecessor.videoURL.lastPathComponent ? 4_000_000_000 : 100,
                                  modified: Date(timeIntervalSince1970: 100)) },
            now: { clock.date }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: "test.membership.\(UUID().uuidString)")!, key: "root"),
            settings: settings, storageDirectory: freshTmpDir(), timeoutSleep: { _ in await delays.run() })
        let initial = Task { await coord.reconcile(rootURL: root, rediscover: true) }
        await reader.waitForCalls(1)
        await delays.waitForCalls(1)
        await reader.finish(0, [partial, independent])
        await initial.value
        clock.date.addTimeInterval(31)
        try Data([0]).write(to: predecessor.videoURL)
        let refresh = Task {
            if deliverEvent { await coord.sourceDidChange(rootURL: root) }
            else { await coord.reconcile(rootURL: root, rediscover: false) }
        }
        await reader.waitForCalls(2)
        await delays.waitForCalls(2)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.map { $0.clips.map(\.stem) }, [[healthy.stem]],
            "A newly copied predecessor must block the cached short tail, while another variant proceeds")
        clock.date.addTimeInterval(31)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.count, 1, "Waiting longer cannot authorize obsolete membership")
        await reader.finish(1, [RecordGroup(clips: [predecessor, tail], groupIndex: 1), independent])
        await refresh.value
        XCTAssertEqual(queue.jobs.count, 1, "Regrouping must restart the quiet window")
        clock.date.addTimeInterval(31)
        await coord.reconcile(rootURL: root, rediscover: false)
        XCTAssertEqual(queue.jobs.map { $0.clips.map(\.stem) }, [[healthy.stem], [predecessor.stem, tail.stem]])
        coord.disable()
        await delays.finish(0, ())
        await delays.finish(1, ())
    }

    func testReviewCannotSealTailAfterUnprobedPredecessorAppears() async throws {
        try await assertMembershipChangeInvalidatesReview(removeDirectory: false)
    }

    func testUnavailableMembershipCensusInvalidatesReview() async throws {
        try await assertMembershipChangeInvalidatesReview(removeDirectory: true)
    }

    private func assertMembershipChangeInvalidatesReview(removeDirectory: Bool) async throws {
        let root = sourceRoot
        let tail = DJIClip(videoURL: root.appendingPathComponent("DJI_0002.MP4"),
            index: 2, variantSuffix: nil, stem: "DJI_0002", duration: .zero)
        try Data([0]).write(to: tail.videoURL)
        let group = RecordGroup(clips: [tail], groupIndex: 1)
        let clock = ManualClock()
        let ledgerDirectory = freshTmpDir()
        let ledger = ProcessedGroupLedger(storageDirectory: ledgerDirectory)
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = WatchFolderCoordinator(discover: { _ in [group] },
            sample: { _ in .init(size: 100, modified: Date(timeIntervalSince1970: 100)) },
            now: { clock.date }, queue: queue, ledger: ledger,
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: "test.membership.review.\(UUID().uuidString)")!, key: "root"),
            settings: settings, storageDirectory: freshTmpDir(), fileIdentifier: { _ in "stable" })
        await coord.reconcile(rootURL: root, rediscover: true)
        clock.date.addTimeInterval(31)
        await coord.reconcile(rootURL: root, rediscover: false)
        let review = try XCTUnwrap(coord.reviewRecords.first)
        if removeDirectory { try FileManager.default.removeItem(at: root) }
        else { try Data([0]).write(to: root.appendingPathComponent("DJI_0001.MP4")) }
        await coord.resolveReview(review.id, as: .alreadyProcessed)
        XCTAssertTrue(coord.reviewRecords.isEmpty)
        XCTAssertNil(ProcessedGroupLedger(storageDirectory: ledgerDirectory).resolution(for: review.descriptor.identity),
            "A pending review cannot seal a descriptor after its membership evidence becomes obsolete")
        XCTAssertTrue(queue.jobs.isEmpty)
        coord.disable()
    }

    func testSuspendedMembershipReadsShareWorkerCapAndFenceLateCompletion() async {
        let census = ControlledWork<[URL]?>()
        let deadlines = ControlledWork<Void>()
        let reader = ControlledWork<[RecordGroup]>()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let coord = WatchFolderCoordinator(discover: { _ in await reader.run() },
            sample: { _ in .init(size: 100, modified: Date(timeIntervalSince1970: 100)) },
            now: { Date() }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: "test.membership.stall.\(UUID().uuidString)")!, key: "root"),
            settings: settings, storageDirectory: freshTmpDir(),
            membershipReader: { _ in await census.run() },
            membershipTimeoutSleep: { _ in await deadlines.run() })
        let root = sourceRoot
        let first = Task { await coord.reconcile(rootURL: root, rediscover: true) }
        await census.waitForCalls(1)
        await deadlines.waitForCalls(1)
        XCTAssertEqual(coord.discoveryBudget.workerCount, 1)
        await deadlines.finish(0, ())
        await first.value
        XCTAssertEqual(coord.status, .discoveryStalled)
        let second = Task { await coord.reconcile(rootURL: root, rediscover: true) }
        await census.waitForCalls(2)
        await deadlines.waitForCalls(2)
        await deadlines.finish(1, ())
        await second.value
        await coord.reconcile(rootURL: root, rediscover: false)
        let censusCalls = await census.count
        let discoveryCalls = await reader.count
        XCTAssertEqual(censusCalls, 2)
        XCTAssertEqual(discoveryCalls, 0)
        XCTAssertEqual(coord.discoveryBudget.workerCount, 2, "Timeout retains census worker ownership")
        coord.disable()
        await census.finish(0, [root.appendingPathComponent("DJI_0001.MP4")])
        await census.finish(1, [])
        await waitUntil { coord.discoveryBudget.workerCount == 0 }
        XCTAssertEqual(coord.status, .idle)
        XCTAssertTrue(queue.jobs.isEmpty)
    }

    func testEventJoiningOlderCensusCannotAdmitAndRetainsTrailingDiscovery() async {
        let census = ControlledWork<[URL]?>()
        let reader = ControlledWork<[RecordGroup]>()
        let clock = ManualClock()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        let root = sourceRoot
        let group = makeGroup()
        let paths = group.clips.map(\.videoURL)
        let coord = WatchFolderCoordinator(discover: { _ in await reader.run() },
            sample: { _ in .init(size: 100, modified: Date(timeIntervalSince1970: 100)) },
            now: { clock.date }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: "test.membership.event.\(UUID().uuidString)")!, key: "root"),
            settings: settings, storageDirectory: freshTmpDir(), membershipReader: { _ in await census.run() })
        let initial = Task { await coord.reconcile(rootURL: root, rediscover: true) }
        await census.waitForCalls(1)
        await census.finish(0, paths)
        await reader.waitForCalls(1)
        await reader.finish(0, [group])
        await census.waitForCalls(2)
        await census.finish(1, paths)
        await initial.value
        clock.date.addTimeInterval(31)
        let oldPoll = Task { await coord.reconcile(rootURL: root, rediscover: false) }
        await census.waitForCalls(3)
        let event = Task { await coord.sourceDidChange(rootURL: root) }
        await waitUntil { coord.eventGeneration == 1 }
        await census.finish(2, paths)
        await oldPoll.value
        await event.value
        XCTAssertTrue(queue.jobs.isEmpty, "Neither caller may authorize admission from a pre-event census")
        let retry = Task { await coord.reconcile(rootURL: root, rediscover: false) }
        await census.waitForCalls(4)
        // A new independent bucket must still trigger discovery, even though cached membership
        // of the earlier group is unchanged and that group may now finish normally.
        let newPath = root.appendingPathComponent("DJI_20261010120000_0003_W.MP4")
        await census.finish(3, paths + [newPath])
        await retry.value
        await census.waitForCalls(5)
        await census.finish(4, paths + [newPath])
        await reader.waitForCalls(2)
        let calls = await reader.count
        XCTAssertEqual(calls, 2, "The source event survives joining an obsolete census")
        let trailing = coord.refreshTask
        coord.disable()
        await reader.finish(1, [])
        await trailing?.value
    }

    func testFailedPostDiscoveryCensusRetainsStallAndRetriesFromPoll() async {
        let reads = CallCounter()
        let clock = ManualClock()
        let group = makeGroup()
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        var tunables = settings
        tunables.quietWindow = 0
        let coord = WatchFolderCoordinator(discover: { _ in [group] },
            sample: { _ in .init(size: 100, modified: Date(timeIntervalSince1970: 100)) },
            now: { clock.date }, queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
            bookmark: WatchFolderBookmark(defaults: UserDefaults(suiteName: "test.membership.retry.\(UUID().uuidString)")!, key: "root"),
            settings: tunables, storageDirectory: freshTmpDir(),
            membershipReader: { _ in reads.bump() == 1 ? nil : [] })
        await coord.reconcile(rootURL: sourceRoot, rediscover: true)
        XCTAssertEqual(coord.status, .discoveryStalled)
        XCTAssertTrue(queue.jobs.isEmpty)
        clock.date.addTimeInterval(1)
        await coord.reconcile(rootURL: sourceRoot, rediscover: false)
        await coord.refreshTask?.value
        XCTAssertEqual(queue.jobs.count, 1)
        XCTAssertNotEqual(coord.status, .discoveryStalled)
        coord.disable()
    }

}
