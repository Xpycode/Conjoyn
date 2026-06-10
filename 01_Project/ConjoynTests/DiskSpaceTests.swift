import XCTest
@testable import Conjoyn

final class DiskSpaceTests: XCTestCase {

    private let temp = FileManager.default.temporaryDirectory

    func testAvailableCapacityForRealVolumeIsPositive() {
        let capacity = DiskSpace.availableCapacity(for: temp)
        XCTAssertNotNil(capacity, "the boot volume should report a capacity")
        XCTAssertGreaterThan(capacity ?? 0, 0)
    }

    func testAvailableCapacityForNonexistentPathIsNil() {
        let bogus = URL(fileURLWithPath: "/this/path/does/not/exist/\(UUID().uuidString)")
        XCTAssertNil(DiskSpace.availableCapacity(for: bogus))
    }

    func testVolumeNameForRealVolume() {
        // The boot volume always has a name; we don't assert the exact string (machine-dependent).
        XCTAssertNotNil(DiskSpace.volumeName(for: temp))
    }

    func testSameVolumeIsReflexive() {
        XCTAssertTrue(DiskSpace.sameVolume(temp, temp))
    }

    func testSameVolumeIsFalseWhenAVolumeCannotBeQueried() {
        let bogus = URL(fileURLWithPath: "/no/such/volume/\(UUID().uuidString)")
        // Conservative: an unqueryable path is treated as a different volume.
        XCTAssertFalse(DiskSpace.sameVolume(temp, bogus))
    }

    // MARK: - usableCapacity selection (the external-volume fix)

    func testUsableCapacityPrefersPositiveImportantUsage() {
        // Boot volume: important usage (counts purgeable) > legacy; we want the larger, accurate figure.
        XCTAssertEqual(DiskSpace.usableCapacity(importantUsage: 59_814_108_237, legacy: 45_004_926_976),
                       59_814_108_237)
    }

    func testUsableCapacityFallsBackWhenImportantUsageIsZero() {
        // External/secondary APFS volume (e.g. 2CULL): important usage returns 0, not nil.
        // Regression guard: must fall back to the real legacy capacity, not report "Zero KB free".
        XCTAssertEqual(DiskSpace.usableCapacity(importantUsage: 0, legacy: 882_323_107_840),
                       882_323_107_840)
    }

    func testUsableCapacityFallsBackWhenImportantUsageIsNil() {
        XCTAssertEqual(DiskSpace.usableCapacity(importantUsage: nil, legacy: 45_004_926_976),
                       45_004_926_976)
    }

    func testUsableCapacityIsNilWhenBothMissing() {
        XCTAssertNil(DiskSpace.usableCapacity(importantUsage: nil, legacy: nil))
        // A zero important-usage with no legacy fallback is still unknown, not "zero free".
        XCTAssertNil(DiskSpace.usableCapacity(importantUsage: 0, legacy: nil))
    }

    func testFormatBytesUsesFileStyle() {
        // File style => decimal GB (not GiB): 2e9 bytes is ~2 GB, not ~1.86 GiB.
        // Assert the unit rather than the exact glyphs (ByteCountFormatter is locale/OS-sensitive).
        XCTAssertTrue(DiskSpace.formatBytes(2_000_000_000).contains("GB"),
                      "got: \(DiskSpace.formatBytes(2_000_000_000))")
        XCTAssertFalse(DiskSpace.formatBytes(0).isEmpty)
    }
}
