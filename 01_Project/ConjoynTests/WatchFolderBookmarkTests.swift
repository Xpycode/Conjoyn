import XCTest
@testable import Conjoyn

// MARK: - Watch Folder Bookmark Tests (Wave 5B, task 5.7)

final class WatchFolderBookmarkTests: XCTestCase {

    // MARK: - Per-test isolation

    /// A unique UserDefaults suite that never touches the real `.standard` domain.
    private var suiteName: String!
    private var isolatedDefaults: UserDefaults!
    private var bookmark: WatchFolderBookmark!

    /// A real temporary directory used as the bookmark target.
    private var tempDir: URL!

    override func setUp() {
        super.setUp()

        suiteName = "test.watchFolder.\(UUID().uuidString)"
        isolatedDefaults = UserDefaults(suiteName: suiteName)!
        bookmark = WatchFolderBookmark(defaults: isolatedDefaults)

        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try! FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        // Remove the isolated UserDefaults suite so it doesn't leak between tests.
        isolatedDefaults.removePersistentDomain(forName: suiteName)
        isolatedDefaults.synchronize()

        // Remove the temp directory created for this test.
        try? FileManager.default.removeItem(at: tempDir)

        super.tearDown()
    }

    // MARK: - Tests

    /// A fresh instance with no stored bookmark must return nil.
    func testResolveNilWhenNothingStored() {
        XCTAssertNil(bookmark.resolve(), "resolve() must return nil when no bookmark has been saved")
    }

    /// After save(url:), resolve() must return a URL pointing at the same directory.
    ///
    /// macOS temporary directories live under `/var/folders/…` which is a symlink to
    /// `/private/var/folders/…`. We compare `resolvingSymlinksInPath` paths to avoid a
    /// spurious failure caused by the symlink discrepancy.
    func testRoundTrip() throws {
        try bookmark.save(url: tempDir)

        let resolved = try XCTUnwrap(bookmark.resolve(), "resolve() must return a URL after save()")

        let expectedPath = tempDir.resolvingSymlinksInPath().path
        let actualPath   = resolved.resolvingSymlinksInPath().path
        XCTAssertEqual(actualPath, expectedPath, "resolved path must match the saved directory")
    }

    /// After save followed by clear, resolve() must return nil.
    func testClearRemovesBookmark() throws {
        try bookmark.save(url: tempDir)
        bookmark.clear()

        XCTAssertNil(bookmark.resolve(), "resolve() must return nil after clear()")
    }

    /// A second WatchFolderBookmark instance sharing the same defaults+key must resolve
    /// the same directory — simulating an app relaunch that reconstructs the service.
    func testPersistenceAcrossInstances() throws {
        try bookmark.save(url: tempDir)

        // Build a second instance on the SAME suite and key (simulates a fresh app launch).
        let bookmark2 = WatchFolderBookmark(defaults: isolatedDefaults)
        let resolved = try XCTUnwrap(bookmark2.resolve(), "second instance must resolve the saved bookmark")

        let expectedPath = tempDir.resolvingSymlinksInPath().path
        let actualPath   = resolved.resolvingSymlinksInPath().path
        XCTAssertEqual(actualPath, expectedPath, "second instance must resolve to the same directory")
    }

    /// A WatchFolderBookmark with a different key must not see another key's stored bookmark,
    /// proving the key parameter provides proper namespace isolation.
    func testIsolationByKey() throws {
        let bookmarkA = WatchFolderBookmark(defaults: isolatedDefaults, key: "keyA")
        let bookmarkB = WatchFolderBookmark(defaults: isolatedDefaults, key: "keyB")

        try bookmarkA.save(url: tempDir)

        XCTAssertNotNil(bookmarkA.resolve(), "bookmarkA must resolve after its own save()")
        XCTAssertNil(bookmarkB.resolve(), "bookmarkB must not see a bookmark saved under a different key")
    }

    /// `makeBookmark(for:)` must produce non-empty Data for an existing directory.
    func testMakeBookmarkProducesData() throws {
        let data = try WatchFolderBookmark.makeBookmark(for: tempDir)
        XCTAssertFalse(data.isEmpty, "makeBookmark must produce non-empty Data")
    }

    /// `makeBookmark(for:)` must throw when the target URL does not exist.
    func testMakeBookmarkThrowsForMissingURL() {
        let missing = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString)", isDirectory: true)
        XCTAssertThrowsError(
            try WatchFolderBookmark.makeBookmark(for: missing),
            "makeBookmark must throw for a URL that does not exist on disk"
        )
    }

    // MARK: - Stale-bookmark note
    //
    // The isStale → re-create path is exercised only when the kernel marks a bookmark stale,
    // which requires the target to have been moved/renamed between the save() and resolve()
    // calls at the HFS/APFS inode level. This is not reliably reproducible in a unit-test
    // environment (FileManager.moveItem does update APFS catalog records but the kernel may
    // or may not set the stale flag in the same process run). The stale path is covered by
    // manual testing: launch the app, select a watch folder, quit, move/rename the folder in
    // Finder, relaunch — resolve() must still return the renamed location and re-persist a
    // fresh bookmark. The unit test below merely asserts that a normal resolve() after save()
    // does not crash and returns a valid URL (the non-stale hot path).
    func testResolveDoesNotCrashOrReturnNilAfterNormalSave() throws {
        try bookmark.save(url: tempDir)
        let resolved = bookmark.resolve()
        XCTAssertNotNil(resolved, "resolve() must return a non-nil URL after a normal save()")
    }
}
