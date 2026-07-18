import XCTest
@testable import Conjoyn

// MARK: - Saved Rename Templates Tests

final class RenameTemplatesTests: XCTestCase {

    // Each test gets its own throwaway suite so no test pollutes another or the real app defaults.
    private var store: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "test.\(UUID().uuidString)"
        store = UserDefaults(suiteName: suiteName)
    }

    override func tearDownWithError() throws {
        store.removePersistentDomain(forName: suiteName)
        store = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Add

    func testAddAppendsInOrder() {
        var t = RenameTemplates.empty
        t.add("{name}_A")
        t.add("{name}_B")
        XCTAssertEqual(t.patterns, ["{name}_A", "{name}_B"], "save order is preserved")
    }

    func testAddTrimsWhitespace() {
        var t = RenameTemplates.empty
        t.add("  {name}_{date} ")
        XCTAssertEqual(t.patterns, ["{name}_{date}"])
    }

    func testAddIgnoresDuplicate() {
        var t = RenameTemplates.empty
        t.add("{name}_x")
        t.add("{name}_x")
        t.add(" {name}_x ")
        XCTAssertEqual(t.patterns, ["{name}_x"], "exact duplicate (post-trim) must not be re-added")
    }

    func testAddIgnoresEmptyAndWhitespaceOnly() {
        var t = RenameTemplates.empty
        t.add("")
        t.add("   ")
        XCTAssertTrue(t.patterns.isEmpty)
    }

    // MARK: - Remove

    func testRemoveDeletesOnlyTheMatch() {
        var t = RenameTemplates.empty
        t.add("{name}_A")
        t.add("{name}_B")
        t.remove("{name}_A")
        XCTAssertEqual(t.patterns, ["{name}_B"])
    }

    func testRemoveUnknownPatternIsNoOp() {
        var t = RenameTemplates.empty
        t.add("{name}_A")
        t.remove("{name}_missing")
        XCTAssertEqual(t.patterns, ["{name}_A"])
    }

    // MARK: - canSave (drives the popover's ＋ chip visibility)

    func testCanSaveRejectsEmptyAndWhitespace() {
        let t = RenameTemplates.empty
        XCTAssertFalse(t.canSave(""))
        XCTAssertFalse(t.canSave("   "))
    }

    func testCanSaveRejectsBuiltInPresets() {
        let t = RenameTemplates.empty
        for preset in RenamePatternEngine.presets {
            XCTAssertFalse(t.canSave(preset.pattern),
                           "built-in preset \(preset.pattern) must not be re-savable")
        }
    }

    func testCanSaveRejectsAlreadySaved() {
        var t = RenameTemplates.empty
        t.add("{name}_custom")
        XCTAssertFalse(t.canSave("{name}_custom"))
        XCTAssertFalse(t.canSave(" {name}_custom "), "trimmed comparison, same as add")
    }

    func testCanSaveAcceptsNewPattern() {
        let t = RenameTemplates.empty
        XCTAssertTrue(t.canSave("{name}_{time}_custom"))
    }

    // MARK: - UserDefaults persistence round-trip

    func testUserDefaultsRoundTrip() {
        var t = RenameTemplates.empty
        t.add("{name}_A")
        t.add("{date}_flight")

        t.save(to: store)
        let loaded = RenameTemplates.load(from: store)
        XCTAssertEqual(loaded, t)
    }

    func testLoadWithNoStoredValueReturnsEmpty() {
        let loaded = RenameTemplates.load(from: store)
        XCTAssertEqual(loaded, .empty)
    }

    func testLoadWithCorruptDataReturnsEmpty() {
        store.set("not-json".data(using: .utf8)!, forKey: RenameTemplates.defaultsKey)
        let loaded = RenameTemplates.load(from: store)
        XCTAssertEqual(loaded, .empty,
                       "corrupt stored blob must fall back to empty silently")
    }
}
