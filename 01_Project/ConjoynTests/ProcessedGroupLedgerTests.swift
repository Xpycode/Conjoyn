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
    // These tests exercise the ledger boundary. Queue durability/readiness integration belongs to W3.
    private var legacyURL: URL { tempDir.appendingPathComponent("processed_groups.json") }
    private var v2URL: URL { tempDir.appendingPathComponent("processed_groups_v2.json") }

    private func identity(capture: TimeInterval? = 100) -> WatchRecordingIdentity {
        WatchRecordingDescriptor(clips: [.init(
            cameraFamily: "dji", stem: "DJI_0001", index: 1, variant: nil,
            recordingNumber: nil, captureDate: capture.map { Date(timeIntervalSince1970: $0) },
            duration: CMTime(value: 10, timescale: 1), relativePath: "DJI_0001.MP4",
            settledVideoBytes: 1000
        )]).identity
    }

    func testLegacyCollisionsReprocessSeparatelyAndNeverPromoteFirstSeen() throws {
        let original = Data("[ \"legacy-hash\" ]\n".utf8)
        try original.write(to: legacyURL)
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let first = identity()
        let replacement = identity(capture: 200)
        XCTAssertEqual(ledger.classify(first, legacyFingerprint: "legacy-hash"), .legacyAmbiguous)
        XCTAssertEqual(ledger.classify(replacement, legacyFingerprint: "legacy-hash"), .legacyAmbiguous)
        try ledger.resolve(first, as: .processOnce)
        XCTAssertEqual(ledger.classify(first, legacyFingerprint: "legacy-hash"), .newRecording)
        XCTAssertEqual(ledger.resolution(for: first), .processOnce)
        var restored = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertEqual(restored.resolution(for: first), .processOnce)
        try restored.commitAdmission(first)
        XCTAssertEqual(restored.classify(first, legacyFingerprint: "legacy-hash"), .knownV2)
        XCTAssertEqual(restored.classify(replacement, legacyFingerprint: "legacy-hash"), .legacyAmbiguous)
        try restored.resolve(replacement, as: .processOnce)
        try restored.commitAdmission(replacement)
        let final = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertEqual(final.classify(first, legacyFingerprint: "legacy-hash"), .knownV2)
        XCTAssertEqual(final.classify(replacement, legacyFingerprint: "legacy-hash"), .knownV2)
        XCTAssertEqual(try Data(contentsOf: legacyURL), original)
        // A repeated authorization must never reopen already admitted work.
        var repeated = final
        try repeated.resolve(first, as: .processOnce)
        XCTAssertEqual(repeated.resolution(for: first), .admitted)
    }

    func testNewIdentityAndExplicitAlreadyProcessedResolution() throws {
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let candidate = identity()
        XCTAssertEqual(ledger.classify(candidate, legacyFingerprint: "absent"), .newRecording)
        try ledger.resolve(candidate, as: .alreadyProcessed)
        let restored = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertEqual(restored.classify(candidate, legacyFingerprint: "absent"), .knownV2)
        XCTAssertEqual(restored.resolution(for: candidate), .alreadyProcessed)
        XCTAssertEqual(restored.classify(identity(capture: 201), legacyFingerprint: "absent"), .newRecording)
    }

    func testWeakIdentityRequiresExplicitDecisionAndStaysVisiblyWeak() throws {
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let weak = identity(capture: nil)
        XCTAssertEqual(ledger.classify(weak, legacyFingerprint: "absent"), .weak(weak.weakReasons))
        XCTAssertThrowsError(try ledger.commitAdmission(weak))
        XCTAssertNil(ledger.resolution(for: weak))
        XCTAssertNil(ledger.persistenceError)
        try ledger.resolve(weak, as: .processOnce)
        var restored = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertEqual(restored.resolution(for: weak), .processOnce)
        XCTAssertEqual(restored.classify(weak, legacyFingerprint: "absent"), .weak(weak.weakReasons))
        try restored.commitAdmission(weak)
        let admitted = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertEqual(admitted.resolution(for: weak), .admitted)
        XCTAssertEqual(admitted.classify(weak, legacyFingerprint: "absent"), .weak(weak.weakReasons))
        // Any changed descriptor loses the prior approval even if still weak.
        let changed = WatchRecordingDescriptor(clips: []).identity
        XCTAssertEqual(admitted.classify(changed, legacyFingerprint: "absent"), .weak(changed.weakReasons))
        XCTAssertNil(admitted.resolution(for: changed))
        var review = admitted
        try review.resolve(changed, as: .alreadyProcessed)
        let reviewed = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertEqual(reviewed.resolution(for: changed), .alreadyProcessed)
        XCTAssertEqual(reviewed.classify(changed, legacyFingerprint: "absent"), .weak(changed.weakReasons))
    }

    func testUnknownAndCorruptFilesRemainUntouchedAndBlockWrites() throws {
        for (url, data) in [
            (legacyURL, Data("{\"version\":99}".utf8)),
            (legacyURL, Data("broken".utf8)),
            (v2URL, Data("{\"version\":99,\"legacyFingerprints\":[],\"resolutions\":{}}".utf8)),
            (v2URL, Data("broken".utf8)),
            (v2URL, Data("{\"version\":2,\"legacyFingerprints\":[],\"resolutions\":{\"v2:bad\":\"admitted\"}}".utf8))
        ] {
            try? FileManager.default.removeItem(at: legacyURL)
            try? FileManager.default.removeItem(at: v2URL)
            try data.write(to: url)
            var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
            XCTAssertNotNil(ledger.persistenceError)
            guard case .storageUnavailable = ledger.classify(identity(), legacyFingerprint: "absent") else {
                return XCTFail("Unreadable history must block admission")
            }
            XCTAssertThrowsError(try ledger.commitAdmission(identity()))
            XCTAssertFalse(ledger.save())
            ledger.insert(makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)]))
            XCTAssertEqual(try Data(contentsOf: url), data)
            if url == legacyURL { XCTAssertFalse(FileManager.default.fileExists(atPath: v2URL.path)) }
        }
    }

    func testFailedWriteDoesNotPublishHistoryAndCanBeRetried() throws {
        let blocker = tempDir.appendingPathComponent("block-writes")
        try Data().write(to: blocker)
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir, write: { data, url in
            if FileManager.default.fileExists(atPath: blocker.path) {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: .atomic)
        })
        let candidate = identity()
        XCTAssertThrowsError(try ledger.commitAdmission(candidate))
        XCTAssertNotNil(ledger.persistenceError)
        XCTAssertNil(ledger.resolution(for: candidate))
        guard case .storageUnavailable = ledger.classify(candidate, legacyFingerprint: "absent") else {
            return XCTFail("Failed persistence must pause admission")
        }
        XCTAssertEqual(ProcessedGroupLedger(storageDirectory: tempDir)
            .classify(candidate, legacyFingerprint: "absent"), .newRecording)
        try FileManager.default.removeItem(at: blocker)
        try ledger.commitAdmission(candidate)
        XCTAssertNil(ledger.persistenceError)
        XCTAssertEqual(ledger.classify(candidate, legacyFingerprint: "absent"), .knownV2)
        XCTAssertEqual(ProcessedGroupLedger(storageDirectory: tempDir)
            .classify(candidate, legacyFingerprint: "absent"), .knownV2)
    }

    func testFailedResolutionPreservesPriorDurableDecision() throws {
        var initial = ProcessedGroupLedger(storageDirectory: tempDir)
        try initial.resolve(identity(), as: .processOnce)
        let before = try Data(contentsOf: v2URL)
        var failing = ProcessedGroupLedger(storageDirectory: tempDir, write: { _, _ in
            throw CocoaError(.fileWriteOutOfSpace)
        })
        XCTAssertThrowsError(try failing.commitAdmission(identity()))
        XCTAssertEqual(failing.resolution(for: identity()), .processOnce)
        XCTAssertEqual(try Data(contentsOf: v2URL), before)
        XCTAssertEqual(ProcessedGroupLedger(storageDirectory: tempDir).resolution(for: identity()), .processOnce)
    }

    func testLegacyCompatibilityInsertPreservesOriginalBytes() throws {
        let original = Data("[\"old\"]\n".utf8)
        try original.write(to: legacyURL)
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        let group = makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)])
        ledger.insert(group)
        XCTAssertTrue(ledger.contains(group))
        XCTAssertTrue(ProcessedGroupLedger(storageDirectory: tempDir).contains(group))
        XCTAssertEqual(try Data(contentsOf: legacyURL), original)
        XCTAssertEqual(ledger.classify(identity(), legacyFingerprint: ProcessedGroupLedger.fingerprint(for: group)),
                       .legacyAmbiguous)
    }
    func testIndependentV2FixtureLoadsWithoutOriginalV1File() throws {
        let candidate = identity()
        let fixture: [String: Any] = [
            "version": 2, "legacyFingerprints": ["legacy-hash"],
            "resolutions": [candidate.ledgerKey: "admitted"]
        ]
        try JSONSerialization.data(withJSONObject: fixture).write(to: v2URL)
        let ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertNil(ledger.persistenceError)
        XCTAssertEqual(ledger.classify(candidate, legacyFingerprint: "legacy-hash"), .knownV2)
        XCTAssertEqual(ledger.classify(identity(capture: 500), legacyFingerprint: "legacy-hash"), .legacyAmbiguous)
        XCTAssertEqual(ledger.classify(identity(capture: 501), legacyFingerprint: "unrelated"), .newRecording)
    }

    func testReadFailureIsNotTreatedAsMissingHistory() throws {
        try FileManager.default.createDirectory(at: legacyURL, withIntermediateDirectories: false)
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertNotNil(ledger.persistenceError)
        XCTAssertFalse(ledger.save())
        XCTAssertThrowsError(try ledger.commitAdmission(identity()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: v2URL.path))
        // A valid sibling cannot hide an unreadable original.
        try JSONSerialization.data(withJSONObject: [
            "version": 2, "legacyFingerprints": [], "resolutions": [:]
        ] as [String: Any]).write(to: v2URL)
        let reloaded = ProcessedGroupLedger(storageDirectory: tempDir)
        XCTAssertNotNil(reloaded.persistenceError)
    }

    func testFailedLegacyInsertIsNotPublishedOrReplayedBySave() throws {
        let blocker = tempDir.appendingPathComponent("block-writes")
        try Data().write(to: blocker)
        var ledger = ProcessedGroupLedger(storageDirectory: tempDir, write: { data, url in
            if FileManager.default.fileExists(atPath: blocker.path) {
                throw CocoaError(.fileWriteOutOfSpace)
            }
            try data.write(to: url, options: .atomic)
        })
        let group = makeGroup(clips: [makeClip(stem: "DJI_0001", index: 1)])
        XCTAssertFalse(ledger.insert(group))
        XCTAssertFalse(ledger.contains(group))
        XCTAssertTrue(ledger.allFingerprints.isEmpty)
        XCTAssertNotNil(ledger.persistenceError)
        try FileManager.default.removeItem(at: blocker)
        XCTAssertTrue(ledger.save())
        XCTAssertNil(ledger.persistenceError)
        XCTAssertFalse(ProcessedGroupLedger(storageDirectory: tempDir).contains(group))
        XCTAssertTrue(ledger.insert(group))
        XCTAssertTrue(ProcessedGroupLedger(storageDirectory: tempDir).contains(group))
    }
}
