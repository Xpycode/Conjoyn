import XCTest
@testable import Conjoyn

/// Card-aware folder resolution (`DJIFolderReader.resolveMediaFolders`): when the user drops a card
/// *root* (or a `DCIM`) instead of the leaf media folder, discovery descends one level through
/// `DCIM/*` to find the clips — bounded to real card layouts, never a deep recursive walk.
///
/// Fixtures are dummy DJI-named files (resolution only enumerates filenames, no media decode), so
/// these run fast and offline.
final class DJIFolderResolveTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ConjoynResolveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: Helpers

    @discardableResult
    private func dir(_ path: String) throws -> URL {
        let url = root.appendingPathComponent(path, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Drops a zero-byte DJI-named clip into `folder` (the name is all `resolveMediaFolders` reads).
    private func clip(_ name: String, in folder: URL) throws {
        try Data().write(to: folder.appendingPathComponent(name))
    }

    private func names(_ urls: [URL]) -> [String] { urls.map(\.lastPathComponent) }

    /// Symlink-resolved paths, so comparisons survive `/var`→`/private/var` (the temp dir) — what
    /// `contentsOfDirectory` returns is canonicalised, what the test builds is not.
    private func resolved(_ urls: [URL]) -> [String] { urls.map { $0.resolvingSymlinksInPath().path } }
    private func assertResolved(_ got: [URL], _ want: [URL], _ file: StaticString = #filePath, _ line: UInt = #line) {
        XCTAssertEqual(resolved(got), resolved(want), file: file, line: line)
    }

    // MARK: - Tests

    /// A leaf media folder was picked directly — return it unchanged (the common, fast path).
    func testFolderWithMediaIsReturnedUnchanged() throws {
        let media = try dir("DCIM/DJI_001")
        try clip("DJI_0001.MP4", in: media)

        assertResolved(DJIFolderReader.resolveMediaFolders(startingAt: media), [media])
    }

    /// Dropping the card root: clips live in `DCIM/DJI_001`, so descend and find that folder.
    func testCardRootDescendsThroughDCIM() throws {
        let media = try dir("DCIM/DJI_001")
        try clip("DJI_0001.MP4", in: media)
        try clip("DJI_0002.MP4", in: media)

        assertResolved(DJIFolderReader.resolveMediaFolders(startingAt: root), [media])
    }

    /// Dropping the `DCIM` folder itself also resolves to its media subfolder.
    func testDroppingDCIMResolvesToMediaSubfolder() throws {
        let dcim = try dir("DCIM")
        let media = try dir("DCIM/100MEDIA")
        try clip("DJI_20260521195303_0006_D.MP4", in: media)

        assertResolved(DJIFolderReader.resolveMediaFolders(startingAt: dcim), [media])
    }

    /// A card with several media folders pools them all, sorted by name (DJI_001 before DJI_002).
    func testMultipleMediaSubfoldersAreSortedAndPooled() throws {
        let a = try dir("DCIM/DJI_002")
        let b = try dir("DCIM/DJI_001")
        try clip("DJI_0009.MP4", in: a)
        try clip("DJI_0001.MP4", in: b)

        let resolved = DJIFolderReader.resolveMediaFolders(startingAt: root)
        XCTAssertEqual(names(resolved), ["DJI_001", "DJI_002"])
    }

    /// DCIM-less layout: media folders sit directly under the dropped folder.
    func testDCIMlessLayoutFindsDirectSubfolders() throws {
        let media = try dir("MyClips")
        try clip("DJI_0001.MP4", in: media)

        assertResolved(DJIFolderReader.resolveMediaFolders(startingAt: root), [media])
    }

    /// Nothing media-like anywhere: fall back to the original folder so the caller still reports an
    /// empty scan against the dropped folder's name (rather than silently scanning nothing).
    func testNoMediaFallsBackToOriginalFolder() throws {
        try dir("DCIM/EMPTY")
        try clip("notes.txt", in: root)

        assertResolved(DJIFolderReader.resolveMediaFolders(startingAt: root), [root])
    }

    /// The descent is bounded: a clip two levels below `DCIM/*` (i.e. depth 3 from root) is NOT
    /// found — guards against deep walks of an arbitrary dropped directory.
    func testDescentIsBoundedAndDoesNotRecurseDeeply() throws {
        let tooDeep = try dir("DCIM/DJI_001/NESTED")
        try clip("DJI_0001.MP4", in: tooDeep)

        // DCIM/DJI_001 holds no media itself (only the NESTED subdir), so nothing is found.
        assertResolved(DJIFolderReader.resolveMediaFolders(startingAt: root), [root])
    }
}
