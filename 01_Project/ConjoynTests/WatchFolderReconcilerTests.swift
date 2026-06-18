import XCTest
import CoreMedia
@testable import Conjoyn

// MARK: - Watch Folder Reconciler Tests (Wave 5C, task 5.9 + 5.10)

/// Tests for `WatchFolderReconciler` — the pure, stateless decision engine.
///
/// All tests are against static functions and synthetic data: no FSEvents, no FFmpeg, no
/// MainActor, no real filesystem. This is the benefit of the pure-reconciler design —
/// the enqueue policy is fully deterministic and can be exercised in-process.
final class WatchFolderReconcilerTests: XCTestCase {

    // MARK: - Fixtures

    /// Default settings tuned for the tests below so thresholds are easy to reason about.
    private let settings = WatchFolderSettings(
        enabled: true,
        requiredStablePolls: 3,
        quietWindow: 30.0,
        splitThreshold: 3_900_000_000,
        pollInterval: 0.75
    )

    /// A fixed reference date for all mtime fixtures.
    private let baseDate = Date(timeIntervalSinceReferenceDate: 1_000_000)

    /// Builds a minimal `DJIClip` with distinct stable identity fields.
    private func makeClip(stem: String, index: Int, variant: String? = nil) -> DJIClip {
        DJIClip(
            videoURL: URL(fileURLWithPath: "/tmp/\(stem).MP4"),
            index: index,
            variantSuffix: variant,
            stem: stem,
            duration: .zero
        )
    }

    /// Builds a `RecordGroup` from `clips`.
    private func makeGroup(_ clips: [DJIClip], groupIndex: Int = 1) -> RecordGroup {
        RecordGroup(clips: clips, groupIndex: groupIndex)
    }

    /// Builds `requiredStablePolls` identical samples (frozen file), representing a settled clip.
    private func settledSamples(size: Int64, date: Date, count: Int = 3) -> [FileStabilityGate.Sample] {
        (0..<count).map { _ in FileStabilityGate.Sample(size: size, modified: date) }
    }

    /// Builds samples with incrementally growing sizes — simulating an actively-writing file.
    private func growingSamples(startSize: Int64, count: Int = 3) -> [FileStabilityGate.Sample] {
        (0..<count).map { i in
            FileStabilityGate.Sample(size: startSize + Int64(i) * 1_024, modified: baseDate)
        }
    }

    // MARK: - Filling-folder simulation

    /// An early-poll observation (file still growing, quiet window not elapsed) must return no groups.
    func testEarlyPoll_growingFile_returnsEmpty() {
        let clip1 = makeClip(stem: "DJI_0001", index: 1)
        let clip2 = makeClip(stem: "DJI_0002", index: 2)
        let group = makeGroup([clip1, clip2])

        let obs = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [growingSamples(startSize: 1_000_000), growingSamples(startSize: 1_500_000)],
            lastSegmentBytes: 1_500_000,
            quietElapsed: 5.0   // well under quietWindow: 30
        )

        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [obs],
            settings: settings,
            processedFingerprints: []
        )

        XCTAssertTrue(result.isEmpty, "Growing file must not be enqueued")
    }

    /// A poll where clips are settled but the quiet window has not elapsed must return no groups.
    func testSettledButQuietWindowNotElapsed_returnsEmpty() {
        let clip1 = makeClip(stem: "DJI_0001", index: 1)
        let clip2 = makeClip(stem: "DJI_0002", index: 2)
        let group = makeGroup([clip1, clip2])

        // Both clips frozen (settled), but last segment is below threshold only if quietElapsed is enough.
        // Here quietElapsed is too short.
        let obs = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [
                settledSamples(size: 500_000_000, date: baseDate),
                settledSamples(size: 200_000_000, date: baseDate)
            ],
            lastSegmentBytes: 200_000_000,   // below splitThreshold
            quietElapsed: 10.0               // < quietWindow 30
        )

        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [obs],
            settings: settings,
            processedFingerprints: []
        )

        XCTAssertTrue(result.isEmpty, "Quiet window not elapsed — must not enqueue")
    }

    /// A poll where the last segment is AT or ABOVE the split threshold must return no groups,
    /// even if settled and quiet — another segment is still expected.
    func testLastSegmentAtSplitThreshold_returnsEmpty() {
        let clip1 = makeClip(stem: "DJI_0001", index: 1)
        let group = makeGroup([clip1])

        let obs = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [settledSamples(size: 3_900_000_000, date: baseDate)],
            lastSegmentBytes: 3_900_000_000,  // exactly AT splitThreshold — not final
            quietElapsed: 60.0                // well past quietWindow
        )

        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [obs],
            settings: settings,
            processedFingerprints: []
        )

        XCTAssertTrue(result.isEmpty, "Last segment at splitThreshold — continuation expected, must not enqueue")
    }

    /// The happy path: all clips settled, last segment below threshold, quiet window elapsed,
    /// not yet processed. Exactly ONE group returned.
    func testFinalPoll_allGatesPassed_returnsGroup() {
        let clip1 = makeClip(stem: "DJI_0001", index: 1)
        let clip2 = makeClip(stem: "DJI_0002", index: 2)
        let group = makeGroup([clip1, clip2])

        let obs = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [
                settledSamples(size: 3_800_000_000, date: baseDate),  // 3.54 GiB — above threshold would be bad
                settledSamples(size: 500_000_000, date: baseDate)     // 500 MB final segment
            ],
            lastSegmentBytes: 500_000_000,   // < splitThreshold
            quietElapsed: 45.0               // > quietWindow
        )

        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [obs],
            settings: settings,
            processedFingerprints: []
        )

        XCTAssertEqual(result.count, 1, "One complete group must be returned")
        XCTAssertEqual(result.first?.clips.count, 2)
    }

    /// A group whose fingerprint is already in `processedFingerprints` must NEVER be returned,
    /// even when all other gates pass.
    func testAlreadyProcessed_neverReturned() {
        let clip1 = makeClip(stem: "DJI_0001", index: 1)
        let clip2 = makeClip(stem: "DJI_0002", index: 2)
        let group = makeGroup([clip1, clip2])
        let fp = ProcessedGroupLedger.fingerprint(for: group)

        let obs = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [
                settledSamples(size: 3_800_000_000, date: baseDate),
                settledSamples(size: 500_000_000, date: baseDate)
            ],
            lastSegmentBytes: 500_000_000,
            quietElapsed: 45.0
        )

        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [obs],
            settings: settings,
            processedFingerprints: [fp]
        )

        XCTAssertTrue(result.isEmpty, "Already-processed group must not be enqueued again")
    }

    /// An empty group (no clips) must never be returned.
    func testEmptyGroup_neverReturned() {
        let group = makeGroup([])

        let obs = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [],
            lastSegmentBytes: 0,
            quietElapsed: 120.0
        )

        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [obs],
            settings: settings,
            processedFingerprints: []
        )

        XCTAssertTrue(result.isEmpty, "Empty group must never be enqueued")
    }

    /// Two distinct complete groups in one observation set must BOTH be returned.
    func testTwoCompleteGroups_bothReturned() {
        let clipA = makeClip(stem: "DJI_0001", index: 1, variant: "D")
        let groupA = makeGroup([clipA], groupIndex: 1)

        let clipB = makeClip(stem: "DJI_0001", index: 1, variant: "W")
        let groupB = makeGroup([clipB], groupIndex: 2)

        let obsA = WatchFolderReconciler.GroupObservation(
            group: groupA,
            clipSamples: [settledSamples(size: 500_000_000, date: baseDate)],
            lastSegmentBytes: 500_000_000,
            quietElapsed: 45.0
        )
        let obsB = WatchFolderReconciler.GroupObservation(
            group: groupB,
            clipSamples: [settledSamples(size: 300_000_000, date: baseDate.addingTimeInterval(1))],
            lastSegmentBytes: 300_000_000,
            quietElapsed: 35.0
        )

        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [obsA, obsB],
            settings: settings,
            processedFingerprints: []
        )

        XCTAssertEqual(result.count, 2, "Both distinct groups must be returned")

        // Fingerprints must be distinct (camera-variant guard working).
        let fpA = ProcessedGroupLedger.fingerprint(for: groupA)
        let fpB = ProcessedGroupLedger.fingerprint(for: groupB)
        XCTAssertNotEqual(fpA, fpB, "Different variant suffixes must produce different fingerprints")
    }

    /// Verifies the multi-poll progression: early polls return nothing; only after
    /// `requiredStablePolls` identical trailing samples plus elapsed quiet window does the
    /// group become ready.
    func testFillingFolderProgression_exactlyOnceAtFinalPoll() {
        let clip = makeClip(stem: "DJI_0001", index: 1)
        let group = makeGroup([clip])

        // Poll 1: file growing, quiet window not elapsed.
        let poll1 = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [growingSamples(startSize: 100_000_000)],
            lastSegmentBytes: 100_100_000,
            quietElapsed: 1.0
        )
        XCTAssertTrue(
            WatchFolderReconciler.groupsToEnqueue(observations: [poll1], settings: settings, processedFingerprints: []).isEmpty,
            "Poll 1: growing + no quiet → empty"
        )

        // Poll 2: file frozen but only 2 identical samples (need 3).
        let twoSamples: [FileStabilityGate.Sample] = [
            FileStabilityGate.Sample(size: 500_000_000, modified: baseDate),
            FileStabilityGate.Sample(size: 500_000_000, modified: baseDate)
        ]
        let poll2 = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [twoSamples],
            lastSegmentBytes: 500_000_000,
            quietElapsed: 5.0   // still < quietWindow
        )
        XCTAssertTrue(
            WatchFolderReconciler.groupsToEnqueue(observations: [poll2], settings: settings, processedFingerprints: []).isEmpty,
            "Poll 2: only 2 stable samples + short quiet → empty"
        )

        // Poll 3: frozen for requiredStablePolls samples but quiet window still short.
        let poll3 = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [settledSamples(size: 500_000_000, date: baseDate)],
            lastSegmentBytes: 500_000_000,
            quietElapsed: 20.0  // still < quietWindow 30
        )
        XCTAssertTrue(
            WatchFolderReconciler.groupsToEnqueue(observations: [poll3], settings: settings, processedFingerprints: []).isEmpty,
            "Poll 3: settled but quiet window not elapsed → empty"
        )

        // Poll 4 (final): settled + complete + fresh.
        let poll4 = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [settledSamples(size: 500_000_000, date: baseDate)],
            lastSegmentBytes: 500_000_000,
            quietElapsed: 35.0  // > quietWindow
        )
        let result = WatchFolderReconciler.groupsToEnqueue(
            observations: [poll4],
            settings: settings,
            processedFingerprints: []
        )
        XCTAssertEqual(result.count, 1, "Poll 4: all gates pass → exactly one group returned")

        // Subsequent poll with same group but now in processedFingerprints → empty.
        let fp = ProcessedGroupLedger.fingerprint(for: group)
        let poll5 = WatchFolderReconciler.GroupObservation(
            group: group,
            clipSamples: [settledSamples(size: 500_000_000, date: baseDate)],
            lastSegmentBytes: 500_000_000,
            quietElapsed: 60.0
        )
        XCTAssertTrue(
            WatchFolderReconciler.groupsToEnqueue(observations: [poll5], settings: settings, processedFingerprints: [fp]).isEmpty,
            "Poll 5: same group now in ledger → never re-enqueued"
        )
    }

    // MARK: - shouldReenqueue (task 5.10)

    /// A fingerprint absent from both sets → should re-enqueue.
    func testShouldReenqueue_neitherSet_returnsTrue() {
        XCTAssertTrue(
            WatchFolderReconciler.shouldReenqueue(
                fingerprint: "abc123",
                processedFingerprints: [],
                liveQueueFingerprints: []
            )
        )
    }

    /// A fingerprint in the processed set → must NOT re-enqueue (job is done).
    func testShouldReenqueue_inLedger_returnsFalse() {
        XCTAssertFalse(
            WatchFolderReconciler.shouldReenqueue(
                fingerprint: "abc123",
                processedFingerprints: ["abc123"],
                liveQueueFingerprints: []
            )
        )
    }

    /// A fingerprint in the live queue set → must NOT re-enqueue (job already in queue).
    func testShouldReenqueue_inLiveQueue_returnsFalse() {
        XCTAssertFalse(
            WatchFolderReconciler.shouldReenqueue(
                fingerprint: "abc123",
                processedFingerprints: [],
                liveQueueFingerprints: ["abc123"]
            )
        )
    }

    /// A fingerprint in both sets → must NOT re-enqueue.
    func testShouldReenqueue_inBothSets_returnsFalse() {
        XCTAssertFalse(
            WatchFolderReconciler.shouldReenqueue(
                fingerprint: "abc123",
                processedFingerprints: ["abc123"],
                liveQueueFingerprints: ["abc123"]
            )
        )
    }

    /// Realistic relaunch scenario: a group was mid-flight (`.joining`) at quit. Its fingerprint
    /// appears in the live-queue set (QueueManager restored the pending job). shouldReenqueue
    /// must return false so it is not double-enqueued.
    func testShouldReenqueue_midFlightGroupMatchesLiveQueue_returnsFalse() {
        let clip1 = makeClip(stem: "DJI_0001", index: 1)
        let clip2 = makeClip(stem: "DJI_0002", index: 2)
        let group = makeGroup([clip1, clip2])
        let fp = ProcessedGroupLedger.fingerprint(for: group)

        // Simulate: the group's fingerprint is in the live queue (job restored from queue.json),
        // but NOT in the ledger (it never finished).
        let result = WatchFolderReconciler.shouldReenqueue(
            fingerprint: fp,
            processedFingerprints: [],      // not in ledger — it didn't finish
            liveQueueFingerprints: [fp]     // but it IS in the restored queue
        )

        XCTAssertFalse(result, "Mid-flight group already in live queue must not be double-enqueued")
    }

    /// A group that finished and is in the ledger, AND also coincidentally matches a live job
    /// (edge case: job persisted as pending but ledger was written), must not re-enqueue.
    func testShouldReenqueue_inLedgerAndLiveQueue_returnsFalse() {
        let clip = makeClip(stem: "DJI_0001", index: 1)
        let group = makeGroup([clip])
        let fp = ProcessedGroupLedger.fingerprint(for: group)

        XCTAssertFalse(
            WatchFolderReconciler.shouldReenqueue(
                fingerprint: fp,
                processedFingerprints: [fp],
                liveQueueFingerprints: [fp]
            )
        )
    }

    // MARK: - Codable group-state round-trip

    /// Verifies that `[String: WatchGroupState]` can be encoded to JSON and decoded back,
    /// preserving all non-terminal states. This is the persistence that `WatchFolderCoordinator`
    /// uses for relaunch resume.
    func testGroupStatesCodableRoundTrip() throws {
        let original: [String: WatchGroupState] = [
            "fingerprint_a": .discovered,
            "fingerprint_b": .settling,
            "fingerprint_c": .grouped,
            "fingerprint_d": .ready,
            "fingerprint_e": .joining,
            "fingerprint_f": .done,
            "fingerprint_g": .failed
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: WatchGroupState].self, from: data)

        XCTAssertEqual(decoded, original, "All WatchGroupState values must survive a JSON round-trip")
    }

    /// Verifies the round-trip against a temp directory (mirrors `ProcessedGroupLedgerTests`).
    func testGroupStatesPersistenceRoundTrip() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("watch_group_states.json")
        let states: [String: WatchGroupState] = [
            "fp_1": .joining,
            "fp_2": .done,
            "fp_3": .settling
        ]

        let written = try JSONEncoder().encode(states)
        try written.write(to: fileURL, options: .atomic)

        let readBack = try Data(contentsOf: fileURL)
        let decoded = try JSONDecoder().decode([String: WatchGroupState].self, from: readBack)

        XCTAssertEqual(decoded["fp_1"], .joining)
        XCTAssertEqual(decoded["fp_2"], .done)
        XCTAssertEqual(decoded["fp_3"], .settling)
    }

    // MARK: - Fingerprint stability across group variants

    /// A group built from clips with variant suffixes must have a different fingerprint than
    /// the same clips without suffixes. This is what prevents the camera-variant guard from
    /// ever producing accidental matches.
    func testFingerprintDiffersAcrossVariants() {
        let clipNoVariant = makeClip(stem: "DJI_0001", index: 1, variant: nil)
        let clipWithVariant = makeClip(stem: "DJI_0001", index: 1, variant: "D")

        let groupA = makeGroup([clipNoVariant])
        let groupB = makeGroup([clipWithVariant])

        XCTAssertNotEqual(
            ProcessedGroupLedger.fingerprint(for: groupA),
            ProcessedGroupLedger.fingerprint(for: groupB),
            "Variant suffix must produce a different fingerprint"
        )
    }

    /// Fingerprint must be stable across two independently-built group instances (no random UUIDs).
    func testFingerprintIsStableAcrossInstances() {
        let clips = [makeClip(stem: "DJI_0001", index: 1), makeClip(stem: "DJI_0002", index: 2)]
        let groupA = makeGroup(clips)
        let groupB = makeGroup(clips)

        XCTAssertEqual(
            ProcessedGroupLedger.fingerprint(for: groupA),
            ProcessedGroupLedger.fingerprint(for: groupB),
            "Same clip identity must produce identical fingerprint every call"
        )
    }
}
