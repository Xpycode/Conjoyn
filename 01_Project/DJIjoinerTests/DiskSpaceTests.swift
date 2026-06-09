import XCTest
@testable import DJIjoiner

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

    func testFormatBytesUsesFileStyle() {
        // File style => decimal GB (not GiB): 2e9 bytes is ~2 GB, not ~1.86 GiB.
        // Assert the unit rather than the exact glyphs (ByteCountFormatter is locale/OS-sensitive).
        XCTAssertTrue(DiskSpace.formatBytes(2_000_000_000).contains("GB"),
                      "got: \(DiskSpace.formatBytes(2_000_000_000))")
        XCTAssertFalse(DiskSpace.formatBytes(0).isEmpty)
    }
}
