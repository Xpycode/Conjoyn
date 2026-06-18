import XCTest
@testable import Conjoyn

// MARK: - Watch-Folder Settings Tests (Wave 5B, task 5.8)

final class WatchFolderSettingsTests: XCTestCase {

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

    // MARK: - Defaults

    func testDefaultValues() {
        let s = WatchFolderSettings.defaults
        XCTAssertFalse(s.enabled,                          "watch-folder off by default")
        XCTAssertEqual(s.requiredStablePolls, 3)
        XCTAssertEqual(s.quietWindow, 45,                  accuracy: 0.001)
        XCTAssertLessThan(s.splitThreshold, 4_000_000_000, "split threshold must be under 4 GB")
        XCTAssertEqual(s.pollInterval, 0.75,               accuracy: 0.001)
    }

    // MARK: - Full Codable round-trip

    func testFullRoundTripViaJSONEncoderDecoder() throws {
        var s = WatchFolderSettings.defaults
        s.enabled = true
        s.requiredStablePolls = 5
        s.quietWindow = 60

        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(WatchFolderSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    // MARK: - Partial-JSON forward-compat

    func testPartialJSONFallsBackToDefaults() throws {
        // Only "enabled" is present — all other keys are missing, must fall back to defaults.
        let json = #"{"enabled": true}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WatchFolderSettings.self, from: json)

        XCTAssertTrue(decoded.enabled,                           "explicit field decoded correctly")
        XCTAssertEqual(decoded.requiredStablePolls,
                       WatchFolderSettings.defaults.requiredStablePolls,
                       "missing key falls back to default")
        XCTAssertEqual(decoded.quietWindow,
                       WatchFolderSettings.defaults.quietWindow,       accuracy: 0.001)
        XCTAssertEqual(decoded.splitThreshold,
                       WatchFolderSettings.defaults.splitThreshold)
        XCTAssertEqual(decoded.pollInterval,
                       WatchFolderSettings.defaults.pollInterval,      accuracy: 0.001)
    }

    func testPartialJSONWithSeveralFields() throws {
        let json = #"{"enabled": true, "quietWindow": 30}"#.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(WatchFolderSettings.self, from: json)

        XCTAssertTrue(decoded.enabled)
        XCTAssertEqual(decoded.quietWindow, 30, accuracy: 0.001)
        XCTAssertEqual(decoded.requiredStablePolls,
                       WatchFolderSettings.defaults.requiredStablePolls,
                       "unlisted key falls back to default")
    }

    // MARK: - UserDefaults persistence round-trip

    func testUserDefaultsRoundTrip() {
        var s = WatchFolderSettings.defaults
        s.enabled = true
        s.pollInterval = 1.5
        s.splitThreshold = 2_000_000_000

        s.save(to: store)
        let loaded = WatchFolderSettings.load(from: store)
        XCTAssertEqual(loaded, s)
    }

    func testLoadWithNoStoredValueReturnsDefaults() {
        // Nothing has been saved to this fresh suite — must return .defaults.
        let loaded = WatchFolderSettings.load(from: store)
        XCTAssertEqual(loaded, WatchFolderSettings.defaults)
    }

    func testLoadWithCorruptDataReturnsDefaults() {
        // Simulate a corrupt blob (plain string, not valid JSON for this type).
        store.set("not-json".data(using: .utf8)!, forKey: WatchFolderSettings.defaultsKey)
        let loaded = WatchFolderSettings.load(from: store)
        XCTAssertEqual(loaded, WatchFolderSettings.defaults,
                       "corrupt stored blob must fall back to defaults silently")
    }
}
