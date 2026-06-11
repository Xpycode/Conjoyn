import XCTest
@testable import Conjoyn

@MainActor
final class TempDirectoryManagerTests: XCTestCase {

    private let manager = TempDirectoryManager.shared

    override func tearDown() {
        // Never leave a custom directory behind in UserDefaults for other tests / runs.
        manager.setCustomTempDirectory(nil)
        super.tearDown()
    }

    func testEffectiveDefaultsToSystemTempWhenNoCustomSet() {
        manager.setCustomTempDirectory(nil)
        XCTAssertFalse(manager.hasCustomDirectory)
        XCTAssertEqual(manager.effectiveTempDirectory, FileManager.default.temporaryDirectory)
    }

    func testRejectsNonexistentCustomDirectory() {
        manager.setCustomTempDirectory(nil) // clean baseline: no stale value from a real app run
        let bogus = URL(fileURLWithPath: "/no/such/dir/\(UUID().uuidString)")
        XCTAssertFalse(manager.setCustomTempDirectory(bogus))
        XCTAssertFalse(manager.hasCustomDirectory)
        // A rejected directory must not be persisted.
        XCTAssertNil(UserDefaults.standard.string(forKey: "Conjoyn.customTempDirectoryPath"))
    }

    func testRejectsAFileAsCustomDirectory() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("conjoyn-not-a-dir-\(UUID().uuidString).txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        XCTAssertFalse(manager.setCustomTempDirectory(file), "a regular file is not a usable temp dir")
        XCTAssertFalse(manager.hasCustomDirectory)
    }

    func testAcceptsAndResolvesAValidCustomDirectory() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conjoyn-temp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        XCTAssertTrue(manager.setCustomTempDirectory(dir))
        XCTAssertTrue(manager.hasCustomDirectory)
        XCTAssertEqual(manager.effectiveTempDirectory.standardizedFileURL, dir.standardizedFileURL)

        // Clearing returns to the system default.
        manager.setCustomTempDirectory(nil)
        XCTAssertEqual(manager.effectiveTempDirectory, FileManager.default.temporaryDirectory)
    }
}
