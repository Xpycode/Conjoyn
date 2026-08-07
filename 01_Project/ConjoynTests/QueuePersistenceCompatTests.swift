import XCTest
import CoreMedia
@testable import Conjoyn

/// **Wave G0.1 — the persisted-queue safety net. Treat a failure here as stop-the-line.**
///
/// `ConjoynTests/Fixtures/queue-1.0.4.json` is a real `queue.json` written by the **shipped 1.0.4**
/// build (2026-07-18), trimmed to four jobs. Two are verbatim; the last two are the same real job
/// hand-edited to carry `pending` and `failed(String)` — the only two statuses `QueueManager.loadQueue`
/// actually restores, and neither occurs in a queue whose jobs all finished.
///
/// The point of this file is that it was written **before** any GoPro field touched the models. A
/// non-Optional stored property added to `DJIClip` — *even one with a default value* — makes the
/// synthesized decoder throw `keyNotFound` at `QueueManager.swift:256`, and the `catch` at `:301`
/// swallows it: the user's entire persisted queue silently disappears on the first launch after
/// updating. This test is what makes that failure loud.
///
/// **If this test goes red, the model change is wrong — do not update the fixture or the
/// expectations to match it.** Fix the decoder (see `DJIClip.init(from:)`, G0.2) instead.
final class QueuePersistenceCompatTests: XCTestCase {

    // MARK: - Fixture loading

    /// Locates the checked-in fixture. Prefers the test bundle's copy (XcodeGen files it as a
    /// resource); falls back to the source tree beside this file, so the test still runs if the
    /// resource ever stops being copied rather than failing for an unrelated reason.
    private func fixtureURL(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> URL {
        if let url = Bundle(for: Self.self).url(forResource: name, withExtension: "json") {
            return url
        }
        let sibling = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/\(name).json")
        guard FileManager.default.fileExists(atPath: sibling.path) else {
            XCTFail("Fixture \(name).json not found in the test bundle or at \(sibling.path)", file: file, line: line)
            throw CocoaError(.fileNoSuchFile)
        }
        return sibling
    }

    /// Decodes the fixture with **exactly** `QueueManager.loadQueue`'s decoder configuration
    /// (`QueueManager.swift:253-254`). Any divergence here would make the test prove the wrong thing.
    private func decodeFixture(_ name: String = "queue-1.0.4") throws -> [ConversionJob] {
        let data = try Data(contentsOf: try fixtureURL(name))
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([ConversionJob].self, from: data)
    }

    // MARK: - Shape

    func testFixtureDecodesIntoTheExpectedJobAndClipCounts() throws {
        let jobs = try decodeFixture()

        XCTAssertEqual(jobs.count, 4)
        XCTAssertEqual(jobs.map(\.clips.count), [4, 5, 2, 2])
        XCTAssertEqual(jobs.map(\.folderName), [
            "DJI-M4P--2026-05-21",
            "DJI-M4P--2026-05-21",
            "DJI-M4P--2026-03-22",
            "DJI-M4P--2026-03-22",
        ])
    }

    // MARK: - Job-level fields

    func testJobScalarsSurviveTheRoundTripFromDisk() throws {
        let job = try XCTUnwrap(try decodeFixture().first)

        XCTAssertEqual(job.id, UUID(uuidString: "7C30DF6A-3DA5-4031-AEE1-307E3C5BC08F"))
        XCTAssertEqual(job.sourceFolderURL.path, "/Volumes/2CULL/2JOIN-IN/IN-M4P/DJI-M4P--2026-05-21")
        XCTAssertEqual(job.destinationURL.path, "/Volumes/2CULL/2CULL-IN/IN-M4P/M4P--2026-05-21--19.53.03.mp4")
        XCTAssertEqual(job.displayName, "M4P--2026-05-21--19.53.03.mp4")
        XCTAssertEqual(job.appliedTimecode, "19:53:03:11")
        XCTAssertEqual(job.progress, 1.0)
        XCTAssertEqual(job.verificationProgress, 1.0)
        XCTAssertEqual(job.createdAt, ISO8601DateFormatter().date(from: "2026-07-18T20:21:56Z"))
        XCTAssertEqual(job.startedAt, ISO8601DateFormatter().date(from: "2026-07-18T20:25:37Z"))
        XCTAssertEqual(job.actualOutputURLs.map(\.path),
                       ["/Volumes/2CULL/2CULL-IN/IN-M4P/M4P--2026-05-21--19.53.03.mp4"])

        // Security-scoped bookmarks are the reason a restored job can still reach its files.
        XCTAssertNotNil(job.sourceBookmarkData)
        XCTAssertNotNil(job.outputBookmarkData)

        // Transient (non-persisted) fields come back at their defaults, not as decode failures.
        XCTAssertNil(job.timecodeStringOverride)
        XCTAssertFalse(job.isDeepVerifying)
        XCTAssertFalse(job.isFinishing)
        XCTAssertTrue(job.sourceIdentities.isEmpty)
    }

    func testSettingsSurvive() throws {
        let settings = try XCTUnwrap(try decodeFixture().first).settings

        XCTAssertEqual(settings.outputContainer, .mp4)
        XCTAssertEqual(settings.outputFilename, "")
        XCTAssertFalse(settings.useFolderNameAsFilename)
        XCTAssertTrue(settings.preserveTimecode)
        XCTAssertTrue(settings.fixCreationDate)
        XCTAssertTrue(settings.stitchSRT)
        XCTAssertFalse(settings.reEncodeOnMismatch)
        XCTAssertFalse(settings.deleteOriginalsAfterVerify)
        XCTAssertNil(settings.dateOverride)
    }

    /// The statuses `loadQueue` restores. `failed` carries an associated `String` through its
    /// hand-written Codable — the shape a synthesized enum decoder would not produce.
    func testEveryPersistedStatusDecodesToTheRightCase() throws {
        let jobs = try decodeFixture()

        XCTAssertEqual(jobs[0].status, .completed)
        XCTAssertEqual(jobs[1].status, .completed)
        XCTAssertEqual(jobs[2].status, .pending)
        XCTAssertEqual(jobs[3].status, .failed("Cannot access source folder (permission lost)"))

        XCTAssertEqual(jobs[0].verificationStatus, .verified)
        XCTAssertEqual(jobs[2].verificationStatus, .unverified)
    }

    func testVerificationResultSurvivesWithEveryCheckKind() throws {
        let result = try XCTUnwrap(try XCTUnwrap(try decodeFixture().first).sourceTargetResult)

        XCTAssertEqual(result.tier, .fast)
        XCTAssertEqual(result.verifiedAt, ISO8601DateFormatter().date(from: "2026-07-18T20:30:37Z"))
        XCTAssertEqual(result.checks.map(\.kind),
                       [.readability, .packetCount, .packetBytes, .duration, .codecParams, .timecodeWriteback])
        XCTAssertEqual(result.checks.map(\.severity),
                       [.pass, .pass, .pass, .info, .pass, .pass])
        XCTAssertEqual(result.checks[3].detail, "Δ 0ms (within ±1 frame)")
        XCTAssertTrue(result.passed)
    }

    // MARK: - Clip-level fields

    func testClipsSurviveWithPathsIndicesAndSidecars() throws {
        let clips = try XCTUnwrap(try decodeFixture().first).clips
        let folder = "/Volumes/2CULL/2JOIN-IN/IN-M4P/DJI-M4P--2026-05-21"

        XCTAssertEqual(clips.map(\.index), [6, 7, 8, 9])
        XCTAssertEqual(clips.map(\.stem), [
            "DJI_20260521195303_0006_D",
            "DJI_20260521195621_0007_D",
            "DJI_20260521195940_0008_D",
            "DJI_20260521200259_0009_D",
        ])
        XCTAssertEqual(clips.map(\.variantSuffix), ["D", "D", "D", "D"])
        XCTAssertEqual(clips[0].videoURL.path, "\(folder)/DJI_20260521195303_0006_D.MP4")

        // Every segment in this group carried a telemetry sidecar; none had an `.LRF` proxy, so
        // `lrfFilePath` is absent from the JSON entirely — the shape a nil Optional encodes to.
        XCTAssertTrue(clips.allSatisfy(\.hasSRT))
        XCTAssertEqual(clips[0].srtURL?.path, "\(folder)/DJI_20260521195303_0006_D.SRT")
        XCTAssertTrue(clips.allSatisfy { !$0.hasProxy })
        XCTAssertTrue(clips.allSatisfy { $0.cameraModel == nil })
    }

    /// Duration is persisted as an `Int64`/`Int32` backing pair and rebuilt into a `CMTime`. A
    /// seconds-only comparison would hide a timescale regression, so assert the exact components.
    func testClipDurationsRebuildTheExactCMTime() throws {
        let clips = try XCTUnwrap(try decodeFixture().first).clips

        XCTAssertEqual(clips.map(\.duration.value), [79_484_000, 79_432_000, 79_456_000, 48_800_000])
        XCTAssertTrue(clips.allSatisfy { $0.duration.timescale == 100_000 })
        XCTAssertEqual(clips[0].durationInSeconds, 794.84, accuracy: 0.0001)

        let job = try XCTUnwrap(try decodeFixture().first)
        XCTAssertEqual(job.totalContentDurationSeconds, 2871.72, accuracy: 0.001)
    }

    func testClipMetadataFieldsSurvive() throws {
        let clip = try XCTUnwrap(try XCTUnwrap(try decodeFixture().first).clips.first)

        XCTAssertEqual(clip.creationDate, ISO8601DateFormatter().date(from: "2026-05-21T17:53:03Z"))

        let stamp = try XCTUnwrap(clip.filenameTimestamp)
        XCTAssertEqual(stamp.year, 2026)
        XCTAssertEqual(stamp.month, 5)
        XCTAssertEqual(stamp.day, 21)
        XCTAssertEqual(stamp.hour, 19)
        XCTAssertEqual(stamp.minute, 53)
        XCTAssertEqual(stamp.second, 3)
    }

    /// `streamInfo` drives the join's parameter guard and the grouping engine. This group has no
    /// audio stream, so `audio` is absent from the JSON — it must decode as `nil`, not throw.
    func testStreamInfoSurvives() throws {
        let clip = try XCTUnwrap(try XCTUnwrap(try decodeFixture().first).clips.first)
        let info = try XCTUnwrap(clip.streamInfo)

        XCTAssertEqual(info.video.codecName, "hevc")
        XCTAssertEqual(info.video.width, 3840)
        XCTAssertEqual(info.video.height, 2160)
        XCTAssertEqual(info.video.pixelFormat, "yuv420p10le")
        XCTAssertEqual(info.video.avgFrameRate, "25/1")
        XCTAssertEqual(info.video.timeBase, "1/100000")
        XCTAssertEqual(info.video.framesPerSecond, 25.0)
        XCTAssertNil(info.audio)

        // Frame-count estimation reads through `streamInfo`; a lost frame rate would nil it out.
        let job = try XCTUnwrap(try decodeFixture().first)
        XCTAssertEqual(job.estimatedFrameCount, 71_793)
    }

    /// The 5-segment group, decoded independently of the 4-segment one — a split whose segments
    /// must stay in file order for the concat list to be correct.
    func testSecondJobKeepsItsFiveSegmentsInOrder() throws {
        let job = try decodeFixture()[1]

        XCTAssertEqual(job.clips.map(\.index), [14, 15, 16, 17, 18])
        XCTAssertEqual(job.appliedTimecode, "20:48:13:18")
        XCTAssertEqual(job.clips.last?.stem, "DJI_20260521210127_0018_D")
    }

    // MARK: - G0.2: the hand-written decoder

    /// `DJIClip.init(from:)` is hand-written; `encode(to:)` is still synthesized. This proves the
    /// two halves agree — a decoder that quietly dropped a field would round-trip to a different
    /// value, and the queue would degrade a little on every save/load cycle.
    func testDecodedClipsSurviveAnEncodeDecodeRoundTrip() throws {
        let original = try decodeFixture()

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601     // matches QueueManager.saveQueue
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let reloaded = try decoder.decode([ConversionJob].self, from: encoder.encode(original))

        XCTAssertEqual(reloaded.count, original.count)
        for (before, after) in zip(original, reloaded) {
            XCTAssertEqual(before.clips, after.clips)   // DJIClip is Hashable/Equatable — all 13 fields
        }
    }

    /// Re-encoding what 1.0.4 wrote must produce the same JSON keys 1.0.4 wrote — no more, no
    /// fewer. This is the half the fixture can't check on its own: a new field that lands in
    /// `CodingKeys` starts appearing on disk, and a *downgrade* (or a rollback DMG) then has to
    /// tolerate it. Absent-when-nil is the shape the synthesized encoder produces, and this pins it.
    func testReEncodingAClipProducesTheSameKeysAsShipped104() throws {
        let clips = try XCTUnwrap(try decodeFixture().first).clips

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: encoder.encode(clips[0])) as? [String: Any]
        )

        XCTAssertEqual(Set(json.keys), [
            "id", "videoFilePath", "srtFilePath",
            "index", "variantSuffix", "filenameTimestamp", "stem",
            "creationDate",
            "durationValue", "durationTimescale",
            "streamInfo",
        ], "on-disk clip shape changed — a queue written here may not load on an older build")

        // `lrfFilePath` and `cameraModel` were nil on this clip, so they must be absent, not null.
        XCTAssertNil(json["lrfFilePath"])
        XCTAssertNil(json["cameraModel"])
    }

    /// The specific regression G0.2 exists to prevent: a field the JSON doesn't carry must decode
    /// to its default rather than throwing and taking the whole queue with it. Simulated by
    /// stripping a key the current model *does* know about — the same shape an old blob presents
    /// to a newer model.
    func testAClipMissingAnOptionalKeyStillDecodes() throws {
        let data = try Data(contentsOf: try fixtureURL("queue-1.0.4"))
        var raw = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])

        var jobs = raw
        var firstJob = jobs[0]
        var clips = try XCTUnwrap(firstJob["clips"] as? [[String: Any]])
        for index in clips.indices {
            clips[index].removeValue(forKey: "streamInfo")
            clips[index].removeValue(forKey: "variantSuffix")
            clips[index].removeValue(forKey: "filenameTimestamp")
            clips[index].removeValue(forKey: "creationDate")
        }
        firstJob["clips"] = clips
        jobs[0] = firstJob
        raw = jobs

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(
            [ConversionJob].self,
            from: try JSONSerialization.data(withJSONObject: raw)
        )

        XCTAssertEqual(decoded.count, 4)
        let stripped = decoded[0].clips
        XCTAssertEqual(stripped.count, 4)
        XCTAssertEqual(stripped.map(\.index), [6, 7, 8, 9])   // required fields still decoded
        XCTAssertTrue(stripped.allSatisfy { $0.streamInfo == nil })
        XCTAssertTrue(stripped.allSatisfy { $0.variantSuffix == nil })
        XCTAssertTrue(stripped.allSatisfy { $0.filenameTimestamp == nil })
        XCTAssertTrue(stripped.allSatisfy { $0.creationDate == nil })

        // A clip with no probed frame rate yields no estimate — degraded, never a decode failure.
        XCTAssertNil(decoded[0].estimatedFrameCount)
    }
}
