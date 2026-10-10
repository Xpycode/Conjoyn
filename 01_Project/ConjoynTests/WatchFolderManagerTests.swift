import XCTest
import Combine
@testable import Conjoyn

// MARK: - Watch Folder Manager Tests (Wave 5D)

/// Tests the multi-folder manager: the overlap policy (the correctness guard against two roots
/// double-processing the same clips), entry persistence across launches, and the add/remove/enable/
/// output mutations. Coordinators activated against empty temp dirs are inert (discovery finds no
/// media), so no FFmpeg runs; each test disables its entries in teardown to stop FSEvents cleanly.
@MainActor
final class WatchFolderManagerTests: XCTestCase {

    private var tmpDirs: [URL] = []
    private var managers: [WatchFolderManager] = []

    private func freshTmpDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("cj.mgr.\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tmpDirs.append(url)
        return url
    }

    private func makeManager(defaults: UserDefaults, base: URL) -> WatchFolderManager {
        let m = WatchFolderManager(
            queue: QueueManager(storageDirectory: freshTmpDir()),
            defaults: defaults,
            storeKey: "watchFolder.entries.test",
            baseStorageDirectory: base
        )
        managers.append(m)
        return m
    }

    override func tearDownWithError() throws {
        // Stop any live FSEvents monitors before the managers deallocate.
        for m in managers {
            for entry in m.entries where entry.enabled { m.setEnabled(entry.id, false) }
        }
        managers = []
        for url in tmpDirs { try? FileManager.default.removeItem(at: url) }
        tmpDirs = []
    }

    @MainActor
    private final class FakeCoordinator: WatchFolderManagingCoordinator {
        let status = CurrentValueSubject<WatchFolderCoordinator.Status, Never>(.idle)
        var managerStatusPublisher: AnyPublisher<WatchFolderCoordinator.Status, Never> {
            status.eraseToAnyPublisher()
        }
        var resolveOutputDestination: () -> WatchFolderEntry.OutputDestination = { .unconfigured }
        var starts: [URL] = []
        var stops = 0
        func enable(rootURL: URL) { starts.append(rootURL); status.send(.watching(settlingCount: 0)) }
        func disable() { stops += 1; status.send(.idle) }
    }

    @MainActor
    private final class RecoveryHarness {
        var roots: [UUID: URL] = [:]
        var available: Set<URL> = []
        var receive: (@MainActor (WatchFolderManager.RootEvent) -> Void)?
        var tick: (@MainActor () -> Void)?
        var observerStarts = 0
        var observerStops = 0
        var timerStarts = 0
        var timerStops = 0
        var interval: TimeInterval?
        var made: [UUID: [FakeCoordinator]] = [:]

        var dependencies: WatchFolderManager.RecoveryDependencies {
            .init(resolveRoot: { [self] in roots[$0.id] },
                  isAvailable: { [self] in available.contains($0) },
                  observe: { [self] callback in
                      observerStarts += 1
                      receive = callback
                      return AnyCancellable { [weak self] in
                          MainActor.assumeIsolated {
                              self?.observerStops += 1
                              self?.receive = nil
                          }
                      }
                  },
                  schedule: { [self] seconds, callback in
                      interval = seconds
                      timerStarts += 1
                      tick = callback
                      return AnyCancellable { [weak self] in
                          MainActor.assumeIsolated {
                              self?.timerStops += 1
                              self?.tick = nil
                          }
                      }
                  })
        }
        func make(_ entry: WatchFolderEntry, _ root: URL) -> any WatchFolderManagingCoordinator {
            let coordinator = FakeCoordinator()
            made[entry.id, default: []].append(coordinator)
            return coordinator
        }
    }

    private func recoveryManager(_ entries: [WatchFolderEntry], _ harness: RecoveryHarness,
                                 retain: Bool = true) throws -> (WatchFolderManager, UserDefaults) {
        let defaults = UserDefaults(suiteName: "test.recovery.\(UUID().uuidString)")!
        defaults.set(try JSONEncoder().encode(entries), forKey: "watchFolder.entries.test")
        let manager = WatchFolderManager(queue: QueueManager(storageDirectory: freshTmpDir()),
                                        defaults: defaults, storeKey: "watchFolder.entries.test",
                                        baseStorageDirectory: freshTmpDir(), recovery: harness.dependencies,
                                        coordinatorFactory: harness.make)
        if retain { managers.append(manager) }
        return (manager, defaults)
    }

    func testAbsentAtLaunchRecoversOnceFromClockAndMountWithoutRestartingHealthyRoot() throws {
        let offline = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/Volumes/Card/DCIM")
        let healthy = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/healthy")
        let harness = RecoveryHarness()
        let healthyURL = URL(fileURLWithPath: healthy.rootPath)
        harness.roots[healthy.id] = healthyURL
        harness.available.insert(healthyURL)
        let (manager, defaults) = try recoveryManager([offline, healthy], harness)
        manager.resumeAll()
        XCTAssertEqual(manager.unavailableEntryIDs, [offline.id])
        XCTAssertNil(harness.made[offline.id])
        XCTAssertEqual(harness.made[healthy.id]?.count, 1)
        XCTAssertEqual(harness.interval, 5)
        for _ in 0..<20 { harness.tick?() }
        XCTAssertNil(harness.made[offline.id])
        let recovered = URL(fileURLWithPath: "/Volumes/Card 1/DCIM")
        harness.roots[offline.id] = recovered
        harness.available.insert(recovered)
        harness.tick?()
        harness.receive?(.mounted)
        manager.resumeAll()
        XCTAssertEqual(harness.made[offline.id]?.count, 1)
        XCTAssertEqual(harness.made[offline.id]?.first?.starts, [recovered])
        XCTAssertEqual(harness.made[healthy.id]?.count, 1)
        XCTAssertEqual(harness.made[healthy.id]?.first?.stops, 0)
        XCTAssertTrue(manager.unavailableEntryIDs.isEmpty)
        XCTAssertEqual(manager.entries.first?.rootPath, recovered.path)
        XCTAssertEqual(WatchFolderManager.loadEntries(from: defaults, key: "watchFolder.entries.test").first?.rootPath,
                       recovered.path)
        XCTAssertEqual(harness.observerStarts, 1)
        XCTAssertEqual(harness.timerStarts, 1)
    }

    func testUnmountStopsImmediatelyAndChangedBookmarkPathRecoversPreservingOutputIntent() throws {
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/Volumes/Card/DCIM",
                                    outputBookmark: Data([1]), outputPath: "/Volumes/Output")
        let healthy = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/healthy")
        let harness = RecoveryHarness()
        let oldRoot = URL(fileURLWithPath: entry.rootPath)
        let healthyRoot = URL(fileURLWithPath: healthy.rootPath)
        harness.roots = [entry.id: oldRoot, healthy.id: healthyRoot]
        harness.available = [oldRoot, healthyRoot]
        let (manager, _) = try recoveryManager([entry, healthy], harness)
        manager.resumeAll()
        let old = try XCTUnwrap(harness.made[entry.id]?.first)
        // Availability deliberately lags behind the unmount notification.
        harness.receive?(.unmounted(URL(fileURLWithPath: "/Volumes/Card")))
        XCTAssertEqual(old.stops, 1)
        XCTAssertEqual(manager.unavailableEntryIDs, [entry.id])
        XCTAssertEqual(harness.made[healthy.id]?.first?.stops, 0)
        old.status.send(.queued(count: 8))
        XCTAssertEqual(manager.statuses[entry.id], .idle, "retired coordinator cannot publish status")
        // A same-name path exists, but the bookmark cannot resolve the original volume.
        harness.roots[entry.id] = nil
        harness.receive?(.mounted)
        harness.tick?()
        XCTAssertEqual(harness.made[entry.id]?.count, 1)
        let moved = URL(fileURLWithPath: "/Volumes/Card 1/DCIM")
        harness.roots[entry.id] = moved
        harness.available.insert(moved)
        harness.receive?(.mounted)
        harness.tick?()
        XCTAssertEqual(harness.made[entry.id]?.count, 2)
        XCTAssertEqual(harness.made[entry.id]?.last?.starts, [moved])
        XCTAssertEqual(harness.made[entry.id]?.last?.resolveOutputDestination(), .unavailable)
        XCTAssertEqual(manager.entries.first?.outputBookmark, entry.outputBookmark)
        XCTAssertEqual(manager.entries.first?.outputPath, entry.outputPath)
        XCTAssertEqual(harness.made[healthy.id]?.count, 1)
    }

    func testPollingReplacesActiveRootWhenBookmarkMovesWithoutUnmount() throws {
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/Volumes/Card/DCIM")
        let harness = RecoveryHarness()
        let original = URL(fileURLWithPath: entry.rootPath)
        let moved = URL(fileURLWithPath: "/Volumes/Card 1/DCIM")
        harness.roots[entry.id] = original
        harness.available = [original, moved]
        let (manager, _) = try recoveryManager([entry], harness)
        manager.resumeAll()
        let retired = try XCTUnwrap(harness.made[entry.id]?.first)

        // The old path remains reachable; bookmark identity, not path availability, owns recovery.
        harness.roots[entry.id] = moved
        harness.tick?()
        XCTAssertEqual(retired.stops, 1)
        XCTAssertEqual(harness.made[entry.id]?.count, 2)
        XCTAssertEqual(harness.made[entry.id]?.last?.starts, [moved])
        XCTAssertEqual(manager.entries.first?.rootPath, moved.path)
        XCTAssertTrue(manager.unavailableEntryIDs.isEmpty)
        retired.status.send(.queued(count: 7))
        XCTAssertEqual(manager.statuses[entry.id], .watching(settlingCount: 0))
        harness.tick?()
        harness.receive?(.mounted)
        XCTAssertEqual(harness.made[entry.id]?.count, 2)
        XCTAssertEqual(harness.made[entry.id]?.last?.stops, 0)
    }

    func testPollingDetectsLostAvailabilityAndDisabledRemovedEntriesNeverRecover() throws {
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/watched")
        let harness = RecoveryHarness()
        let root = URL(fileURLWithPath: entry.rootPath)
        harness.roots[entry.id] = root
        harness.available = [root]
        let (manager, _) = try recoveryManager([entry], harness)
        manager.resumeAll()
        harness.available = []
        harness.tick?()
        XCTAssertEqual(harness.made[entry.id]?.first?.stops, 1)
        XCTAssertEqual(manager.unavailableEntryIDs, [entry.id])
        let staleEvent = harness.receive
        let staleTick = harness.tick
        manager.setEnabled(entry.id, false)
        harness.available = [root]
        staleEvent?(.mounted)
        staleTick?()
        XCTAssertEqual(harness.made[entry.id]?.count, 1)
        XCTAssertEqual(harness.observerStops, 1)
        XCTAssertEqual(harness.timerStops, 1)
        manager.setEnabled(entry.id, true)
        XCTAssertEqual(harness.made[entry.id]?.count, 2)
        manager.remove(entry.id)
        staleEvent?(.mounted)
        staleTick?()
        XCTAssertEqual(harness.made[entry.id]?.count, 2)
        XCTAssertEqual(harness.observerStops, 2)
        XCTAssertEqual(harness.timerStops, 2)
        XCTAssertNil(manager.statuses[entry.id])
        XCTAssertTrue(manager.unavailableEntryIDs.isEmpty)
    }

    func testRecoveryObserverAndTimerReleaseWhenManagerDeallocates() throws {
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/offline")
        let harness = RecoveryHarness()
        var manager: WatchFolderManager? = try recoveryManager([entry], harness, retain: false).0
        weak var released = manager
        manager?.resumeAll()
        XCTAssertEqual(harness.observerStarts, 1)
        manager = nil
        XCTAssertNil(released)
        XCTAssertEqual(harness.observerStops, 1)
        XCTAssertEqual(harness.timerStops, 1)
        XCTAssertNil(harness.receive)
        XCTAssertNil(harness.tick)
    }

    // MARK: - pathsOverlap (the mechanical helper behind the policy)

    func testPathsOverlapDetectsSameAndNested() {
        let root = URL(fileURLWithPath: "/Volumes/Card/DCIM")
        let nested = URL(fileURLWithPath: "/Volumes/Card/DCIM/100MEDIA")
        let disjoint = URL(fileURLWithPath: "/Volumes/Other/DCIM")

        XCTAssertTrue(WatchFolderManager.pathsOverlap(root, root), "same path overlaps")
        XCTAssertTrue(WatchFolderManager.pathsOverlap(root, nested), "parent/child overlaps")
        XCTAssertTrue(WatchFolderManager.pathsOverlap(nested, root), "overlap is symmetric")
        XCTAssertFalse(WatchFolderManager.pathsOverlap(root, disjoint), "sibling trees don't overlap")
    }

    // MARK: - rejectionReason (the authored overlap policy)

    func testRejectionReasonBlocksOverlapAllowsDisjoint() {
        let root = freshTmpDir()
        let entry = WatchFolderEntry(
            id: UUID(),
            rootBookmark: try! WatchFolderEntry.makeBookmark(for: root),
            rootPath: root.path
        )

        let nested = root.appendingPathComponent("DCIM", isDirectory: true)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        XCTAssertNotNil(
            WatchFolderManager.rejectionReason(forAdding: nested, existing: [entry]),
            "a folder nested inside an existing root must be rejected (double-processing hazard)"
        )

        let disjoint = freshTmpDir()
        XCTAssertNil(
            WatchFolderManager.rejectionReason(forAdding: disjoint, existing: [entry]),
            "a disjoint folder is allowed"
        )

        XCTAssertNil(
            WatchFolderManager.rejectionReason(forAdding: root, existing: []),
            "with no existing folders, anything is allowed"
        )
    }

    /// Policy decision (2026-06-20): an existing watch folder whose volume is **offline** (its
    /// bookmark can't resolve) must STILL block an overlapping add — we fall back to its persisted
    /// `rootPath`, so a later re-mount can't silently resurrect an overlapping pair into a double join.
    func testRejectionReasonBlocksOfflineEntryViaLastKnownPath() {
        let offlinePath = "/Volumes/OfflineCard/DCIM/100MEDIA"
        let entry = WatchFolderEntry(
            id: UUID(),
            rootBookmark: Data([0x00, 0x01, 0x02]),   // garbage → resolvedRootURL is nil
            rootPath: offlinePath
        )
        XCTAssertNil(entry.resolvedRootURL, "precondition: the offline entry's bookmark must not resolve")

        XCTAssertNotNil(
            WatchFolderManager.rejectionReason(forAdding: URL(fileURLWithPath: offlinePath), existing: [entry]),
            "the same offline path must be rejected via the last-known rootPath"
        )
        XCTAssertNotNil(
            WatchFolderManager.rejectionReason(forAdding: URL(fileURLWithPath: offlinePath + "/sub"), existing: [entry]),
            "a folder nested under an offline root must be rejected too"
        )
        XCTAssertNil(
            WatchFolderManager.rejectionReason(forAdding: URL(fileURLWithPath: "/Volumes/OtherCard/DCIM"), existing: [entry]),
            "a disjoint path is still allowed even against an offline entry"
        )
    }

    // MARK: - Add / reject through the manager

    func testAddFolderRejectsOverlapAndLeavesListUnchanged() {
        let m = makeManager(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!, base: freshTmpDir())
        let root = freshTmpDir()
        guard case .added = m.addFolder(rootURL: root) else { return XCTFail("first add should succeed") }
        XCTAssertEqual(m.entries.count, 1)

        let nested = root.appendingPathComponent("DCIM", isDirectory: true)
        try? FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        guard case .rejected = m.addFolder(rootURL: nested) else { return XCTFail("overlap should be rejected") }
        XCTAssertEqual(m.entries.count, 1, "a rejected add must not mutate the list")
    }

    // MARK: - Persistence across "relaunch"

    func testEntriesPersistAcrossManagerInstances() {
        let defaults = UserDefaults(suiteName: "test.\(UUID().uuidString)")!
        let base = freshTmpDir()
        let m1 = makeManager(defaults: defaults, base: base)
        let root = freshTmpDir()
        guard case .added(let entry) = m1.addFolder(rootURL: root) else { return XCTFail() }
        m1.setEnabled(entry.id, false)   // also stops the monitor

        let m2 = makeManager(defaults: defaults, base: base)
        XCTAssertEqual(m2.entries.count, 1, "entries must reload from persistence")
        XCTAssertEqual(m2.entries.first?.id, entry.id)
        XCTAssertEqual(m2.entries.first?.enabled, false)
    }

    // MARK: - Output folder mutation

    func testSetOutputFolderSetsAndClears() {
        let m = makeManager(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!, base: freshTmpDir())
        let root = freshTmpDir()
        guard case .added(let entry) = m.addFolder(rootURL: root) else { return XCTFail() }

        let output = freshTmpDir()
        m.setOutputFolder(entry.id, url: output)
        XCTAssertEqual(m.entries.first?.outputPath, output.path)
        XCTAssertNotNil(m.entries.first?.outputBookmark)

        m.setOutputFolder(entry.id, url: nil)
        XCTAssertNil(m.entries.first?.outputPath)
        XCTAssertNil(m.entries.first?.outputBookmark)
    }

    func testUnavailableBookmarkAndPathOnlyIntentSurvivePersistence() throws {
        let suite = "test.output.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = freshTmpDir()
        let output = freshTmpDir()
        let corrupt = Data([0, 1, 2])
        let entries = [
            WatchFolderEntry(id: UUID(), rootBookmark: try WatchFolderEntry.makeBookmark(for: root),
                             rootPath: root.path, outputBookmark: corrupt, outputPath: output.path),
            WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: root.path,
                             outputPath: output.path)
        ]
        defaults.set(try JSONEncoder().encode(entries), forKey: "watchFolder.entries.test")
        let manager = makeManager(defaults: defaults, base: freshTmpDir())
        XCTAssertEqual(manager.entries, entries)
        XCTAssertTrue(manager.entries.allSatisfy { $0.outputDestination == .unavailable })
        manager.resumeAll()
        XCTAssertEqual(manager.statuses[entries[0].id], .outputUnavailable)
        XCTAssertEqual(manager.entries[0].outputBookmark, corrupt)
        XCTAssertEqual(manager.entries[0].outputPath, output.path)

        manager.setOutputFolder(entries[0].id, url: output)
        guard case .resolved(let resolved) = manager.entries[0].outputDestination else {
            return XCTFail("reselecting a reachable output must recover")
        }
        XCTAssertEqual(resolved.resolvingSymlinksInPath(), output.resolvingSymlinksInPath())
        XCTAssertNotEqual(manager.statuses[entries[0].id], .outputUnavailable)
        manager.setOutputFolder(entries[0].id, url: nil)
        XCTAssertEqual(manager.entries[0].outputDestination, .unconfigured)
    }

    func testOutputResolutionRequiresWritableDirectoryAndKeepsBookmarkWhenMissing() throws {
        let output = freshTmpDir()
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/unused",
                                    outputBookmark: try WatchFolderEntry.makeBookmark(for: output),
                                    outputPath: output.path)
        guard case .resolved = entry.outputDestination else { return XCTFail("folder must resolve") }
        let savedData = try JSONEncoder().encode(entry)
        try FileManager.default.removeItem(at: output)
        XCTAssertEqual(entry.outputDestination, .unavailable)
        XCTAssertEqual(try JSONDecoder().decode(WatchFolderEntry.self, from: savedData), entry)
        // A file occupying the same path is never a usable output directory.
        try Data("sentinel".utf8).write(to: output)
        XCTAssertEqual(entry.outputDestination, .unavailable)
    }

    func testOutputWithoutDirectorySearchPermissionPausesAndRecovers() throws {
        let output = freshTmpDir()
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: "/unused",
                                    outputBookmark: try WatchFolderEntry.makeBookmark(for: output),
                                    outputPath: output.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: output.path) }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: output.path)
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: output.path))
        XCTAssertFalse(WatchFolderEntry.isUsableOutputDirectory(output))
        XCTAssertEqual(entry.outputDestination, .unavailable)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: output.path)
        guard case .resolved = entry.outputDestination else { return XCTFail("restored access must recover") }
    }

    // MARK: - Remove

    func testRemoveDropsEntryAndStatus() {
        let m = makeManager(defaults: UserDefaults(suiteName: "test.\(UUID().uuidString)")!, base: freshTmpDir())
        let root = freshTmpDir()
        guard case .added(let entry) = m.addFolder(rootURL: root) else { return XCTFail() }
        XCTAssertEqual(m.entries.count, 1)

        m.remove(entry.id)
        XCTAssertEqual(m.entries.count, 0)
        XCTAssertNil(m.statuses[entry.id])
    }
    func testWorkerBudgetSurvivesSettingsToggleRemovalAndChangedMountPath() throws {
        let harness = RecoveryHarness()
        let suite = "test.budget.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let originalRoot = freshTmpDir()
        let movedRoot = freshTmpDir()
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: originalRoot.path, enabled: true)
        harness.roots[entry.id] = originalRoot
        harness.available = [originalRoot, movedRoot]
        defaults.set(try JSONEncoder().encode([entry]), forKey: "entries")
        let manager = WatchFolderManager(queue: QueueManager(storageDirectory: freshTmpDir()), defaults: defaults,
            storeKey: "entries", baseStorageDirectory: freshTmpDir(), recovery: harness.dependencies,
            coordinatorFactory: harness.make)
        managers.append(manager)
        manager.resumeAll()
        let budget = manager.discoveryBudget(for: entry, rootURL: originalRoot)
        let first = try XCTUnwrap(budget.acquire())
        let second = try XCTUnwrap(budget.acquire())
        manager.updateSettings(entry.id, .defaults)
        manager.setEnabled(entry.id, false)
        manager.setEnabled(entry.id, true)
        XCTAssertTrue(manager.discoveryBudget(for: entry, rootURL: originalRoot) === budget)
        harness.receive?(.unmounted(originalRoot))
        harness.roots[entry.id] = movedRoot
        harness.receive?(.mounted)
        XCTAssertTrue(manager.discoveryBudget(for: entry, rootURL: movedRoot) === budget)
        XCTAssertNil(budget.acquire())
        manager.remove(entry.id)
        let readded = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: movedRoot.path, enabled: true)
        XCTAssertTrue(manager.discoveryBudget(for: readded, rootURL: movedRoot) === budget)
        // The old canonical alias remains protected too.
        let oldAlias = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: originalRoot.path, enabled: true)
        XCTAssertTrue(manager.discoveryBudget(for: oldAlias, rootURL: originalRoot) === budget)
        XCTAssertEqual(budget.workerCount, 2)
        budget.complete(first)
        let replacement = try XCTUnwrap(budget.acquire())
        XCTAssertNil(budget.acquire())
        budget.complete(second)
        budget.complete(replacement)
        XCTAssertEqual(budget.workerCount, 0)
    }

    func testRemovedEntryBookmarkCarriesWorkerBudgetToNewMountPath() throws {
        let harness = RecoveryHarness()
        let manager = WatchFolderManager(queue: QueueManager(storageDirectory: freshTmpDir()),
            defaults: UserDefaults(suiteName: "test.budget.removed.\(UUID().uuidString)")!,
            baseStorageDirectory: freshTmpDir(), recovery: harness.dependencies, coordinatorFactory: harness.make)
        managers.append(manager)
        let root = freshTmpDir()
        let moved = freshTmpDir()
        let old = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: root.path, enabled: true)
        harness.roots[old.id] = root
        let budget = manager.discoveryBudget(for: old, rootURL: root)
        let slot = try XCTUnwrap(budget.acquire())
        manager.remove(old.id)
        harness.roots[old.id] = moved
        let readded = WatchFolderEntry(id: UUID(), rootBookmark: Data(), rootPath: moved.path, enabled: true)
        XCTAssertTrue(manager.discoveryBudget(for: readded, rootURL: moved) === budget)
        XCTAssertEqual(budget.workerCount, 1)
        budget.complete(slot)
    }

    private actor SuspendedReads {
        private var continuations: [CheckedContinuation<[RecordGroup], Never>?] = []
        private var waiters: [(Int, CheckedContinuation<Void, Never>)] = []
        func read() async -> [RecordGroup] {
            await withCheckedContinuation { continuation in
                continuations.append(continuation)
                let ready = waiters.filter { continuations.count >= $0.0 }
                waiters.removeAll { continuations.count >= $0.0 }
                ready.forEach { $0.1.resume() }
            }
        }
        func waitForCalls(_ count: Int) async {
            if continuations.count >= count { return }
            await withCheckedContinuation { waiters.append((count, $0)) }
        }
        func finish(_ index: Int, groups: [RecordGroup]) {
            let continuation = continuations[index]
            continuations[index] = nil
            continuation?.resume(returning: groups)
        }
        var count: Int { continuations.count }
    }

    private func waitUntil(_ condition: @MainActor () -> Bool, file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0..<10_000 {
            if condition() { return }
            await Task.yield()
        }
        XCTFail("Controlled coordinator did not reach expected state", file: file, line: line)
    }

    func testSuspendedWorkersCannotAdmitAfterUnmountSettingsToggleOrRemoveReadd() async throws {
        let reader = SuspendedReads()
        let harness = RecoveryHarness()
        let suite = "test.actual.lifecycle.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let root = freshTmpDir()
        let moved = freshTmpDir()
        var settings = WatchFolderSettings.defaults
        settings.requiredStablePolls = 1
        settings.quietWindow = 0
        settings.pollInterval = 10_000 // Real timer cannot drive these deterministic tests.
        let entry = WatchFolderEntry(id: UUID(), rootBookmark: try WatchFolderEntry.makeBookmark(for: root),
                                    rootPath: root.path, enabled: true, settings: settings)
        harness.roots[entry.id] = root
        harness.available = [root, moved]
        defaults.set(try JSONEncoder().encode([entry]), forKey: "entries")
        let queue = QueueManager(storageDirectory: freshTmpDir())
        queue.isProcessing = true
        var made: [WatchFolderCoordinator] = []
        var dependencies = harness.dependencies
        dependencies.resolveRoot = { harness.roots[$0.id] ?? $0.resolvedRootURL }
        dependencies.isAvailable = { url in
            harness.available.contains { $0.resolvingSymlinksInPath() == url.resolvingSymlinksInPath() }
        }
        let manager = WatchFolderManager(queue: queue, defaults: defaults, storeKey: "entries",
            baseStorageDirectory: freshTmpDir(), recovery: dependencies, coordinatorFactory: { [self] entry, _ in
                let coordinator = WatchFolderCoordinator(discover: { _ in await reader.read() },
                    sample: { _ in .init(size: 100, modified: Date(timeIntervalSince1970: 100)) },
                    now: { Date(timeIntervalSince1970: 1000) }, queue: queue,
                    ledger: ProcessedGroupLedger(storageDirectory: freshTmpDir()),
                    bookmark: WatchFolderBookmark(defaults: defaults, key: UUID().uuidString),
                    settings: settings, storageDirectory: freshTmpDir(), watchEntryID: entry.id)
                made.append(coordinator)
                return coordinator
            })
        managers.append(manager)
        manager.resumeAll()
        await reader.waitForCalls(1)
        let first = try XCTUnwrap(made.first)
        let budget = first.discoveryBudget
        harness.receive?(.unmounted(root))
        XCTAssertEqual(first.status, .idle)
        XCTAssertEqual(budget.workerCount, 1)
        harness.roots[entry.id] = moved
        harness.receive?(.mounted)
        await reader.waitForCalls(2)
        XCTAssertTrue(made.last?.discoveryBudget === budget)
        manager.updateSettings(entry.id, settings)
        manager.setEnabled(entry.id, false)
        manager.setEnabled(entry.id, true)
        manager.remove(entry.id)
        guard case .added(let readded) = manager.addFolder(rootURL: moved) else { return XCTFail("Re-add failed") }
        let current = try XCTUnwrap(made.last)
        let activeRoot = try XCTUnwrap(readded.resolvedRootURL)
        await waitUntil { current.status == .discoveryStalled }
        XCTAssertTrue(current.discoveryBudget === budget)
        XCTAssertEqual(budget.workerCount, 2)
        let callsBeforeCompletion = await reader.count
        XCTAssertEqual(callsBeforeCompletion, 2)
        let stale = RecordGroup(clips: [DJIClip(videoURL: root.appendingPathComponent("DJI_0001.MP4"),
            index: 1, variantSuffix: nil, stem: "DJI_0001", creationDate: Date(timeIntervalSince1970: 1000), duration: .zero)], groupIndex: 1)
        await reader.finish(0, groups: [stale])
        await reader.finish(1, groups: [stale])
        await waitUntil { budget.workerCount == 0 }
        XCTAssertTrue(queue.jobs.isEmpty, "Retired work cannot admit across unmount/removal")
        XCTAssertEqual(first.status, .idle)
        XCTAssertNil(manager.statuses[entry.id])
        guard current.status == .discoveryStalled else {
            manager.setEnabled(readded.id, false)
            return XCTFail("Re-added coordinator must have retained a pending refresh")
        }
        await current.reconcile(rootURL: activeRoot, rediscover: false)
        await reader.waitForCalls(3)
        await reader.finish(2, groups: [])
        await current.refreshTask?.value
        XCTAssertNotEqual(manager.statuses[readded.id], .discoveryStalled,
                          "A successful empty retry clears stalled status")
        XCTAssertTrue(queue.jobs.isEmpty)
        manager.setEnabled(readded.id, false)
    }

}
