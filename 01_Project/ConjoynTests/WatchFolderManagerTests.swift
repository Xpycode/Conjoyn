import XCTest
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
}
