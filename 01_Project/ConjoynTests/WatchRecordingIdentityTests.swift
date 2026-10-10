import XCTest
import CoreMedia
@testable import Conjoyn

/// Pure contract tests: freshness/stability gates and production admission are tested by W3/W4.
final class WatchRecordingIdentityTests: XCTestCase {
    private func clip() -> WatchRecordingDescriptor.Clip {
        .init(cameraFamily: "goPro", stem: "GX016338", index: 1, variant: nil,
              recordingNumber: 6338, captureDate: Date(timeIntervalSince1970: 1_785_500_000.125),
              duration: CMTime(value: 60_000, timescale: 1000),
              relativePath: "100GOPRO/GX016338.MP4", settledVideoBytes: 123456)
    }

    func testFreshDescriptorsAndJSONRoundTripHaveStableIdentity() throws {
        let first = WatchRecordingDescriptor(clips: [clip()])
        let fresh = WatchRecordingDescriptor(clips: [clip()])
        XCTAssertEqual(first.identity, fresh.identity)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let restored = try JSONDecoder().decode(WatchRecordingDescriptor.self, from: encoder.encode(first))
        XCTAssertEqual(first.identity, restored.identity)
        XCTAssertEqual(first.identity.strength, .strong)
        XCTAssertEqual(first.identity.version, 2)
        XCTAssertEqual(first.identity.digest.count, 64)
        // Independently calculated with Python struct.pack('>Q', byteCount) + hashlib.sha256.
        XCTAssertEqual(first.canonicalData.count, 190)
        XCTAssertEqual(first.identity.digest, "a3e80837fd2a6c949bea0501b2d98d0da0cce3625f4e4a81f00d0fc3fc6296d8")
    }

    func testEachCaptureFactAndClipOrderDistinguishesReusedFilenames() {
        let original = clip()
        let baseline = WatchRecordingDescriptor(clips: [original]).identity
        let changes: [(inout WatchRecordingDescriptor.Clip) -> Void] = [
            { $0.cameraFamily = "dji" }, { $0.stem += "x" }, { $0.index += 1 },
            { $0.variant = "D" }, { $0.recordingNumber = 6339 },
            { $0.captureMicroseconds = ($0.captureMicroseconds ?? 0) + 1 },
            { $0.duration = .init(value: 61, timescale: 1) },
            { $0.relativePath = "other/GX016338.MP4" }, { $0.settledVideoBytes = 123457 }
        ]
        for change in changes {
            var changed = original
            change(&changed)
            XCTAssertNotEqual(baseline, WatchRecordingDescriptor(clips: [changed]).identity)
        }
        var second = original
        second.index = 2
        XCTAssertNotEqual(WatchRecordingDescriptor(clips: [original, second]).identity,
                          WatchRecordingDescriptor(clips: [second, original]).identity)
    }

    func testCanonicalEncodingCannotConfuseDelimitersOrNilWithEmpty() {
        var a = clip()
        a.stem = "a|b"
        a.variant = "c"
        var b = a
        b.stem = "a"
        b.variant = "b|c"
        XCTAssertNotEqual(WatchRecordingDescriptor(clips: [a]).identity,
                          WatchRecordingDescriptor(clips: [b]).identity)
        b = a
        b.variant = nil
        a.variant = ""
        XCTAssertNotEqual(WatchRecordingDescriptor(clips: [a]).identity,
                          WatchRecordingDescriptor(clips: [b]).identity)
    }

    func testExactRationalNormalizationAndInvalidDurations() {
        var a = clip()
        var b = a
        a.duration = .init(value: 1001, timescale: 30)
        b.duration = .init(value: 2002, timescale: 60)
        XCTAssertEqual(WatchRecordingDescriptor(clips: [a]).identity,
                       WatchRecordingDescriptor(clips: [b]).identity)
        XCTAssertNil(WatchRecordingDescriptor.ExactDuration(value: -1, timescale: 30))
        XCTAssertNil(WatchRecordingDescriptor.ExactDuration(value: Int64.min, timescale: 30))
        XCTAssertNil(WatchRecordingDescriptor.ExactDuration(value: 1, timescale: 0))
        XCTAssertNil(WatchRecordingDescriptor.ExactDuration(value: 1, timescale: -1))
        XCTAssertEqual(WatchRecordingDescriptor.ExactDuration(value: 0, timescale: 30),
                       WatchRecordingDescriptor.ExactDuration(value: 0, timescale: 1))
        XCTAssertNotNil(WatchRecordingDescriptor.ExactDuration(value: Int64.max, timescale: Int32.max))
    }

    func testUnavailableFactsAreExplicitlyWeak() {
        var missing = clip()
        missing.captureMicroseconds = nil
        let identity = WatchRecordingDescriptor(clips: [missing]).identity
        XCTAssertEqual(identity.strength, .weak)
        XCTAssertTrue(identity.weakReasons.contains(.missingCaptureDate))
        missing.duration = nil
        missing.settledVideoBytes = nil
        missing.recordingNumber = nil
        let reasons = WatchRecordingDescriptor(clips: [missing]).identity.weakReasons
        XCTAssertTrue(reasons.contains(.missingDuration))
        XCTAssertTrue(reasons.contains(.missingSettledSize))
        XCTAssertTrue(reasons.contains(.missingRecordingNumber))
        XCTAssertEqual(WatchRecordingDescriptor(clips: []).identity.strength, .weak)
        let invalid = WatchRecordingDescriptor.Clip(cameraFamily: "dji", stem: "x", index: 1,
            variant: nil, recordingNumber: nil, captureDate: Date(timeIntervalSince1970: .infinity),
            duration: .indefinite, relativePath: "../outside.MP4", settledVideoBytes: -1)
        XCTAssertEqual(WatchRecordingDescriptor(clips: [invalid]).identity.strength, .weak)
    }

    func testDurationJSONNormalizesAndRejectsInvalidRationals() throws {
        let decoder = JSONDecoder()
        let duration = try decoder.decode(WatchRecordingDescriptor.ExactDuration.self,
                                         from: Data(#"{"value":2002,"timescale":60}"#.utf8))
        XCTAssertEqual(duration, try XCTUnwrap(WatchRecordingDescriptor.ExactDuration(value: 1001, timescale: 30)))
        XCTAssertThrowsError(try decoder.decode(WatchRecordingDescriptor.ExactDuration.self,
                                               from: Data(#"{"value":1,"timescale":0}"#.utf8)))
    }

    func testCaptureDateUsesNumericMicrosecondsAndNoFileSystemFallback() {
        let captured = clip()
        XCTAssertEqual(captured.captureMicroseconds, 1_785_500_000_125_000)
        let missing = WatchRecordingDescriptor.Clip(cameraFamily: "dji", stem: "x", index: 1,
            variant: nil, recordingNumber: nil, captureDate: nil, duration: .zero,
            relativePath: "x.MP4", settledVideoBytes: 0)
        XCTAssertNil(missing.captureMicroseconds)
        XCTAssertTrue(WatchRecordingDescriptor(clips: [missing]).identity.weakReasons.contains(.missingCaptureDate))
    }

    func testSnapshotPersistsOwnershipWithoutCurrentRootURL() throws {
        var job = manualJob()
        let snapshot = WatchIdentitySnapshot(watchEntryID: UUID(), ledgerNamespace: "stable-ledger-uuid",
                                              descriptor: .init(clips: [clip()]))
        job.watchIdentitySnapshot = snapshot
        let restored = try JSONDecoder().decode(ConversionJob.self, from: JSONEncoder().encode(job))
        XCTAssertEqual(restored.watchIdentitySnapshot, snapshot)
        XCTAssertEqual(restored.watchIdentitySnapshot?.identity, snapshot.identity)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any])
        object.removeValue(forKey: "ledgerNamespace")
        XCTAssertThrowsError(try JSONDecoder().decode(WatchIdentitySnapshot.self,
                                                     from: JSONSerialization.data(withJSONObject: object)))
    }

    func testManualAndOldQueueJobsOmitSnapshotAndDecodeUnchanged() throws {
        let encoder = JSONEncoder()
        let data = try encoder.encode(manualJob())
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["watchIdentitySnapshot"])
        XCTAssertNil(try JSONDecoder().decode(ConversionJob.self, from: data).watchIdentitySnapshot)
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/queue-1.0.4.json")
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let jobs = try decoder.decode([ConversionJob].self, from: Data(contentsOf: fixture))
        XCTAssertEqual(jobs.count, 4)
        XCTAssertTrue(jobs.allSatisfy { $0.watchIdentitySnapshot == nil })
    }

    private func manualJob() -> ConversionJob {
        ConversionJob(folderName: "DCIM", sourceFolderURL: URL(fileURLWithPath: "/source"),
                      clips: [], settings: ConversionSettings(), destinationURL: URL(fileURLWithPath: "/out/test.mp4"))
    }
}
