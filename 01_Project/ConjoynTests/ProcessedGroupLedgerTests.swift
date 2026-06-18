import XCTest
import CoreMedia
@testable import Conjoyn

// MARK: - Processed Group Ledger Tests (Wave 5A, task 5.4)

final class ProcessedGroupLedgerTests: XCTestCase {

    // MARK: - Fixtures

    /// Builds a minimal `DJIClip` with distinct stable identity fields. Heavy fields (sidecar URLs,
    /// creationDate, streamInfo) are left at their defaults so fixtures stay terse.
    private func makeClip(stem: String, index: Int, variantSuffix: String? = nil) -> DJIClip {
        DJIClip(
            videoURL: URL(fileURLWithPath: "/tmp/\(stem).MP4"),
            index: index,
            variantSuffix: variantSuffix,
            stem: stem,
            duration: .zero
        )
    }

    private func makeGroup(clips: [DJIClip], groupIndex: Int = 1) -> RecordGroup {
        RecordGroup(clips: clips, groupIndex: groupIndex)
    }

    // MARK: - Temp directory lifecycle

    private var tempDir: URL!

    override func setUp() {
        super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
        super.tearDown()
    }

    // MARK: - Determinism

    /// Fingerprint for the same ordered clips equals itself across two freshly-built group instances,
    /// proving no per-process random seed leaked in (i.e., Swift.Hasher is not used).
    func testFingerprintIsDeterministic() {
        let clips = [
            makeClip(stem: "DJI_0001", index: 1),
            makeClip(stem: "DJI_0002", index: 2),
        ]
        // Build two separate RecordGroup instances from the same clip data.
        let groupA = makeGroup(clips: clips)
        let groupB = makeGroup(clips: clips)

        XCTAssertEqual(
            ProcessedGroupLedger.fingerprint(for: groupA),
            ProcessedGroupLedger.fingerprint(for: groupB),
            "Same ordered clips must produce the same fingerprint every time"
        )
    }

    // MARK: - Order sensitivity

    /// Clips in a different order must produce a different fingerprint.
    func testFingerprintDiffersForDifferentClipOrder() {
        let clip1 = makeClip(stem: "DJI_0001", index: 1)
        let clip2 = makeClip(stem: "DJI_0002", index: 2)

        let groupAB = makeGroup(clips: [clip1, clip2])
        let groupBA = makeGroup(clips: [clip2, clip1])

        XCTAssertNotEqual(
            ProcessedGroupLedger.fingerprint(for: groupAB),
            ProcessedGroupLedger.fingerprint(for: groupBA),
            "Different clip order must produce a different fingerprint"
        )
    }

    // MARK: - Variant sensitivity

    /// Same stems but different `variantSuffix` must produce a different fingerprint.
    func testFingerprintDiffersForDifferentVariantSuffix() {
        let clipWide = makeClip(stem: "DJI_0001", index: 1, variantSuffix: "W")
        let clipTele = makeClip(stem: "DJI_0001", index: 1, variantSuffix: "T")

        let groupW = makeGroup(clips: [clipWide])
        let groupT = makeGroup(clips: [clipTele])

        XCTAssertNotEqual(
            ProcessedGroupLedger.fingerprint(for: groupW),
            ProcessedGroupLedger.fingerprint(for: groupT),
            "Different variantSuffix must produce a different fingerprint"
        )
    }

    /// A nil suffix and a non-nil suffix with the same stem/index must differ.
    func testFingerprintDiffersForNilVsNonNilVariantSuffix() {
        let clipNoSuffix = makeClip(stem: "DJI_0001", index: 1, variantSuffix: nil)
        let clipWithSuffix = makeClip(stem: "DJI_0001", index: 1, variantSuffix: "D")

        let groupNil = makeGroup(clips: [clipNoSuffix])
        let groupD   = makeGroup(clips: [clipWithSuffix])

        XCTAssertNotEqual(
            ProcessedGroupLedger.fingerprint(for: groupNil),
            ProcessedGroupLedger.fingerprint(for: groupD),
            "nil suffix and non-nil suffix must produce different fingerprints"
        )
    }

    // MARK: - contains / insert

    /// A fresh (empty) ledger must not contain any group.
    func testFreshLedgerDoesNotContainGroup() {
        let ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let group = makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)])
        XCTAssertFalse(ledger.contains(group), "Fresh ledger must not contain any group")
    }

    /// After inserting a group, the ledger must contain it.
    func testLedgerContainsGroupAfterInsert() {
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let group = makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)])
        ledger.insert(group)
        XCTAssertTrue(ledger.contains(group), "Ledger must contain a group that was inserted")
    }

    /// Inserting group A must not cause the ledger to contain the distinct group B.
    func testLedgerDoesNotContainDifferentGroup() {
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let groupA = makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)])
        let groupB = makeGroup(clips: [makeClip(stem: "DJI_0002", index: 2)])
        ledger.insert(groupA)
        XCTAssertFalse(ledger.contains(groupB), "Inserting group A must not affect containment of group B")
    }

    // MARK: - Persistence round-trip

    /// Insert a group, save (implicit in `insert`), load a new ledger from the same directory,
    /// and verify the new instance contains the group — i.e., the fingerprint survived encode →
    /// disk → decode.
    func testPersistenceRoundTrip() {
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let group = makeGroup(clips: [
            makeClip(stem: "DJI_0001", index: 1),
            makeClip(stem: "DJI_0002", index: 2),
        ])
        ledger.insert(group) // writes processed_groups.json to tempDir

        // Build a fresh ledger instance that reads from the same directory.
        let reloadedLedger = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertTrue(
            reloadedLedger.contains(group),
            "Reloaded ledger must contain a group that was persisted by the previous instance"
        )
    }

    /// A group NOT inserted before save must NOT appear after reload.
    func testPersistenceDoesNotContainUninsertedGroup() {
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let inserted = makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)])
        let other    = makeGroup(clips: [makeClip(stem: "DJI_0099", index: 99)])
        ledger.insert(inserted)

        let reloadedLedger = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertFalse(
            reloadedLedger.contains(other),
            "Reloaded ledger must not contain a group that was never inserted"
        )
    }

    // MARK: - Missing file is non-fatal

    /// Loading from a directory that contains no JSON file must succeed silently and return an empty
    /// ledger (no crash, no thrown error).
    func testLoadFromEmptyDirectoryIsSilent() {
        let emptyDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: emptyDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: emptyDir) }

        let ledger = ProcessedGroupLedger(storageDirectory: emptyDir)
        let group = makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)])
        XCTAssertFalse(ledger.contains(group), "Ledger loaded from empty directory must be empty")
    }
}
