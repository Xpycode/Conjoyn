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

    private var tmpDirs: [URL] = []

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
            videoURL: URL(fileURLWithPath: "/tmp/DJI_0001.MP4"),
            index: 1,
            variantSuffix: nil,
            stem: "DJI_0001",
            duration: .zero
        )
        return RecordGroup(clips: [clip], groupIndex: 1)
    }

    /// Builds a coordinator whose group is always discovered, always reads as a small frozen file,
    /// and whose clock advances past the quiet window between pass 1 and pass 2.
    private func makeCoordinator(ledger: ProcessedGroupLedger,
                                 queue: QueueManager) -> WatchFolderCoordinator {
        let group = makeGroup()
        let t0 = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let clock = FakeClock([t0, t0.addingTimeInterval(31)])   // 31s > quietWindow(30)
        let frozenSample = FileStabilityGate.Sample(size: 800_000_000, modified: t0) // < splitThreshold
        return WatchFolderCoordinator(
            discover: { _ in [group] },
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
        let coord = makeCoordinator(ledger: reloaded, queue: queue)

        let root = freshTmpDir()
        await coord.reconcile(rootURL: root, rediscover: true)   // pass 1
        await coord.reconcile(rootURL: root, rediscover: false)  // pass 2 (quiet elapsed)

        // Group is settled + complete + quiet — but already in the ledger → must NOT enqueue.
        XCTAssertEqual(queue.jobs.count, 0,
                       "a previously-joined group whose clips remain on the card must not re-enqueue")
    }

    // MARK: - Control: a fresh group enqueues exactly once, then is sealed

    func testFreshGroupEnqueuesOnceAndIsSealed() async {
        let group = makeGroup()
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir())
        let queue = QueueManager(storageDirectory: freshTmpDir())
        let coord = makeCoordinator(ledger: ledger, queue: queue)

        let root = freshTmpDir()
        await coord.reconcile(rootURL: root, rediscover: true)   // pass 1: settled but not yet quiet
        XCTAssertEqual(queue.jobs.count, 0, "not enqueued before the quiet window elapses")

        await coord.reconcile(rootURL: root, rediscover: false)  // pass 2: quiet window elapsed
        XCTAssertEqual(queue.jobs.count, 1, "ready group enqueues exactly one job")
        XCTAssertEqual(queue.jobs.first?.clips.map(\.stem), group.clips.map(\.stem))

        // A further pass must not double-enqueue — the group is now sealed in the ledger.
        await coord.reconcile(rootURL: root, rediscover: false)  // pass 3
        XCTAssertEqual(queue.jobs.count, 1, "a sealed group must not be enqueued again")
    }

    // MARK: - Disable stops cleanly

    func testDisablePersistsDisabledState() {
        let ledger = ProcessedGroupLedger(storageDirectory: freshTmpDir())
        let queue = QueueManager(storageDirectory: freshTmpDir())
        let coord = makeCoordinator(ledger: ledger, queue: queue)
        coord.disable()
        XCTAssertEqual(coord.status, .idle)
    }
}
