import XCTest
@testable import Conjoyn

/// Waves G5.1 + G5.2 — proves the Tier 0/1 pass and the Tier 2 byte-exact hash both genuinely check
/// the gpmd telemetry stream through the **real** join + verify path, not a synthetic stand-in.
/// Reuses the same real Hero 11 seam fixtures `GoProJoinIntegrationTests` joins
/// (`Fixtures/gopro-seam/`), builds a `SourceTargetVerifier.SourceTargetInput` the way
/// `QueueManager+Verification.makeVerifierInput` does, and asserts the emitted checks both pass
/// when the output genuinely carries the joined gpmd stream and — falsified — flag loudly when the
/// output has no gpmd stream (the join silently dropped it) or the source's telemetry index was
/// never resolved (a discovery-time probe hiccup) — the two failure modes a formula-derived output
/// index couldn't distinguish, and a `d:0` selector could confuse with the regenerated `tmcd` track
/// (decision 4).
///
/// Skips cleanly when the bundled ffmpeg/ffprobe or the fixtures are unavailable.
final class GoProVerificationIntegrationTests: XCTestCase {

    // MARK: - Measured baselines (see Fixtures/gopro-seam/README.md, shared with GoProJoinIntegrationTests)

    private enum Expected {
        static let gpmdPackets = 2
        static let gpmdBytes = 14_000
    }

    // MARK: - Harness (mirrors GoProJoinIntegrationTests' skip-cleanly idiom)

    private func tools() throws -> (ffmpeg: URL, ffprobe: URL) {
        let r = BundledToolResolver.shared
        guard let ffmpeg = r.path(for: .ffmpeg), let ffprobe = r.path(for: .ffprobe) else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }
        return (ffmpeg, ffprobe)
    }

    private func fixtureURL(_ name: String, file: StaticString = #filePath) throws -> URL {
        if let url = Bundle(for: Self.self).url(forResource: name, withExtension: "MP4") {
            return url
        }
        let sibling = URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/gopro-seam/\(name).MP4")
        guard FileManager.default.fileExists(atPath: sibling.path) else {
            throw XCTSkip("Fixture \(name).MP4 not found in the test bundle or at \(sibling.path)")
        }
        return sibling
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conjoyn-goproverify-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private struct ProbedStream: Decodable {
        let index: Int
        let codec_tag_string: String?
    }

    private struct ProbedStreams: Decodable {
        let streams: [ProbedStream]
    }

    /// The absolute index of the joined output's stream carrying `codecTag`, via a standalone
    /// ffprobe call (independent of production probing, so the assertion is external).
    private func probeStreamIndex(ffprobe: URL, url: URL, codecTag: String) throws -> Int? {
        let p = Process()
        p.executableURL = ffprobe
        p.arguments = ["-v", "quiet", "-print_format", "json", "-show_streams", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ffprobe -show_streams failed for \(url.lastPathComponent)")
        let streams = try JSONDecoder().decode(ProbedStreams.self, from: data).streams
        return streams.first { $0.codec_tag_string == codecTag }?.index
    }

    /// Joins the two seam fixtures through the real `.preserveTelemetry` path (same production
    /// entry point `QueueManager+Processing.processConcatenateJob` drives for a GoPro job), and
    /// returns the output plus each source segment's probed `SegmentStreamInfo` — the same data
    /// `makeVerifierInput` reads `sourceGpmdIndex` from.
    private func joinFixtures() async throws -> (
        segments: [URL], output: URL, sourceInfos: [StreamParameterGuard.SegmentStreamInfo], dir: URL
    ) {
        let seg1 = try fixtureURL("GX016349")
        let seg2 = try fixtureURL("GX026349")
        let dir = try makeTempDir()
        let outputURL = dir.appendingPathComponent("joined.mp4")

        let ffmpeg = FFmpegWrapper()
        let infos = try [seg1, seg2].map { try ffmpeg.probeStreamInfo($0) }

        try await ffmpeg.mergeClips(
            [seg1, seg2],
            to: outputURL,
            metadata: .init(timecode: "00:00:00:00"),
            dataStreamPolicy: .preserveTelemetry,
            progress: { _, _ in },
            logHandler: { _ in }
        )
        return ([seg1, seg2], outputURL, infos, dir)
    }

    // MARK: - Positive: the correct indices pass, with the measured parity

    func testTelemetryCheckPassesOnCorrectlyResolvedIndices() async throws {
        _ = try tools()
        let (segments, output, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        // Both fixtures carry gpmd at source index 2 (the fixture's re-mux layout — see
        // Fixtures/gopro-seam/README.md), and both are read with audio present, so the join's
        // fixed -map order (video, audio, gpmd) lands the output gpmd at index 2 too — the same
        // formula `makeVerifierInput` applies (`hasAudio ? 2 : 1`).
        let sourceGpmdIndex = infos.first?.dataStreamIndex
        XCTAssertEqual(sourceGpmdIndex, 2, "fixture's measured gpmd index (Fixtures/gopro-seam/README.md)")

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: output,
            hasAudio: true,
            sourceParams: infos,
            appliedTimecode: "00:00:00:00",
            sourceGpmdIndex: sourceGpmdIndex,
            isGoProFamily: true
        )

        let result = await SourceTargetVerifier().verifyFast(input)

        let countCheck = try XCTUnwrap(result.checks.first { $0.label == "Packet count (telemetry)" })
        let bytesCheck = try XCTUnwrap(result.checks.first { $0.label == "Packet bytes (telemetry)" })
        XCTAssertEqual(countCheck.kind, .gpmdParity)
        XCTAssertEqual(bytesCheck.kind, .gpmdParity)
        XCTAssertEqual(countCheck.severity, .pass, "detail: \(countCheck.detail)")
        XCTAssertEqual(bytesCheck.severity, .pass, "detail: \(bytesCheck.detail)")

        // Cross-check against the same measured baseline GoProJoinIntegrationTests pins, via a
        // standalone probe of the joined output — proves the verifier's own packetCount/
        // packetByteSize helpers agree with an independent read, not just with each other.
        let (_, ffprobe) = try tools()
        let outStats = try packetStats(ffprobe: ffprobe, url: output, streamSpecifier: "2")
        XCTAssertEqual(outStats.packets, Expected.gpmdPackets)
        XCTAssertEqual(outStats.bytes, Expected.gpmdBytes)
    }

    private func packetStats(ffprobe: URL, url: URL, streamSpecifier: String) throws -> (packets: Int, bytes: Int) {
        let p = Process()
        p.executableURL = ffprobe
        p.arguments = ["-v", "quiet", "-select_streams", streamSpecifier,
                       "-show_entries", "packet=size", "-of", "csv=p=0", url.path]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        try p.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ffprobe packet query failed for \(url.lastPathComponent)")
        let sizes = String(data: data, encoding: .utf8)?
            .split(separator: "\n")
            .compactMap { Int($0.trimmingCharacters(in: .whitespaces)) } ?? []
        return (sizes.count, sizes.reduce(0, +))
    }

    // MARK: - Falsification: the output index comes from a real probe, never a guessed position

    /// The mechanism this replaces derived the output's gpmd index from the join's `-map` position
    /// (`hasAudio ? 2 : 1`) instead of probing the output file directly. Proves the output side is
    /// resolved by `codec_tag_string == "gpmd"` on the joined file itself, not by position: the
    /// output genuinely carries both a `tmcd` stream (regenerated by `-timecode`) and a `gpmd`
    /// stream at *different* absolute indices, and the resolved gpmd index must land on the real
    /// gpmd stream — never coincide with tmcd, which the formula-based hazard (decision 4) and a
    /// bare `d:0` selector could both produce.
    func testTelemetryCheckResolvesTheRealGpmdStreamNotTheRegeneratedTmcd() async throws {
        let (_, ffprobe) = try tools()
        let (segments, output, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tmcdIndex = try XCTUnwrap(
            try probeStreamIndex(ffprobe: ffprobe, url: output, codecTag: "tmcd"),
            "expected a regenerated tmcd stream in the joined output"
        )
        let gpmdIndex = try XCTUnwrap(
            try probeStreamIndex(ffprobe: ffprobe, url: output, codecTag: "gpmd"),
            "expected a gpmd stream in the joined output"
        )
        XCTAssertNotEqual(tmcdIndex, gpmdIndex,
                          "the fixture must exercise two distinct data streams for this to prove anything")

        let outputInfo = try FFmpegWrapper().probeStreamInfo(output)
        let resolution = SourceTargetVerifier.resolveGpmd(
            isGoProFamily: true,
            sourceGpmdIndex: infos.first?.dataStreamIndex,
            outputInfo: outputInfo
        )
        guard case .resolved(_, let resolvedOutputIndex) = resolution else {
            XCTFail("expected a resolved gpmd index, got \(resolution)")
            return
        }
        XCTAssertEqual(resolvedOutputIndex, gpmdIndex)
        XCTAssertNotEqual(resolvedOutputIndex, tmcdIndex,
                          "must never resolve to the regenerated tmcd track")
    }

    /// Finding 1's bonus: a GoPro job whose source resolved a gpmd index but whose joined output
    /// demonstrably has none — "the join silently dropped telemetry" — must surface as a named,
    /// detectable failure, never a skipped check. Simulated with a real `.drop`-policy join of the
    /// same source segments (the DJI-default data-stream policy), so the output genuinely has no
    /// gpmd stream — not a synthetic stand-in.
    func testTelemetryCheckFailsWhenTheJoinedOutputHasNoGpmdStream() async throws {
        _ = try tools()
        let (segments, _, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let noGpmdOutput = dir.appendingPathComponent("no-gpmd-output.mp4")
        try await FFmpegWrapper().mergeClips(
            segments, to: noGpmdOutput, dataStreamPolicy: .drop,
            progress: { _, _ in }, logHandler: { _ in }
        )

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: noGpmdOutput,
            hasAudio: true,
            sourceParams: infos,
            appliedTimecode: nil,
            sourceGpmdIndex: infos.first?.dataStreamIndex,
            isGoProFamily: true
        )

        let result = await SourceTargetVerifier().verifyFast(input)
        let telemetryCheck = try XCTUnwrap(result.checks.first { $0.label == "Telemetry (gpmd)" })
        XCTAssertEqual(telemetryCheck.kind, .gpmdParity)
        XCTAssertEqual(telemetryCheck.severity, .fail,
                       "a GoPro job whose output has no gpmd stream must fail loudly, never skip silently — detail: \(telemetryCheck.detail)")
    }

    /// Finding 2: a GoPro job whose `sourceGpmdIndex` never resolved (`DJIFolderReader`'s `try?`
    /// probe hiccup) must still surface a flagged check — never seal green on a skipped check.
    func testTelemetryCheckWarnsWhenSourceLayoutNeverResolvedForGoProJob() async throws {
        _ = try tools()
        let (segments, output, _, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: output,
            hasAudio: true,
            sourceParams: [nil, nil],
            appliedTimecode: nil,
            sourceGpmdIndex: nil,
            isGoProFamily: true
        )

        let result = await SourceTargetVerifier().verifyFast(input)
        let telemetryCheck = try XCTUnwrap(result.checks.first { $0.label == "Telemetry (gpmd)" })
        XCTAssertEqual(telemetryCheck.kind, .gpmdParity)
        XCTAssertEqual(telemetryCheck.severity, .warning,
                       "unresolved telemetry on a GoPro job must warn, never silently skip — detail: \(telemetryCheck.detail)")
    }

    /// Counterpart to the warning above: the exact same "never resolved" input, but for a DJI job
    /// (`isGoProFamily: false`), must stay completely silent — a nil `sourceGpmdIndex` is DJI's
    /// permanent, expected case, not an anomaly.
    func testTelemetryCheckStaysSilentForDJIJobRegardlessOfStreamInfo() async throws {
        _ = try tools()
        let (segments, output, _, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: output,
            hasAudio: true,
            sourceParams: [nil, nil],
            appliedTimecode: nil,
            sourceGpmdIndex: nil,
            isGoProFamily: false
        )

        let result = await SourceTargetVerifier().verifyFast(input)
        XCTAssertNil(result.checks.first { $0.kind == .gpmdParity },
                    "a DJI job must never emit a telemetry check, resolved or not")
    }

    /// Finding 3: `QueuePanel` renders flagged checks keyed on `label` — every label in one result
    /// must be unique, or SwiftUI's `ForEach` collides. Exercised over the GoPro thorough-verify
    /// path (the widest check list: Tier 0/1/2 plus the telemetry checks).
    func testAllCheckLabelsAreUniqueForAGoProThoroughVerify() async throws {
        _ = try tools()
        let (segments, output, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: output,
            hasAudio: true,
            sourceParams: infos,
            appliedTimecode: "00:00:00:00",
            sourceGpmdIndex: infos.first?.dataStreamIndex,
            isGoProFamily: true
        )

        let result = await SourceTargetVerifier().verifyThorough(input)
        let labels = result.checks.map(\.label)
        XCTAssertEqual(Set(labels).count, labels.count,
                       "QueuePanel's ForEach(id: \\.label) requires every check's label to be unique — duplicates: \(labels)")
    }

    // MARK: - Tier 2 (G5.2): the byte-exact hash also covers gpmd

    /// Companion to `testTelemetryCheckPassesOnCorrectlyResolvedIndices`, one tier deeper:
    /// `verifyThorough` hashes v:0/a:0/gpmd end-to-end, so this proves the mechanism through the
    /// real join + real ffmpeg `-f streamhash`, not a synthetic vector.
    func testTier2HashPassesOnCorrectlyResolvedIndices() async throws {
        _ = try tools()
        let (segments, output, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let sourceGpmdIndex = infos.first?.dataStreamIndex
        XCTAssertEqual(sourceGpmdIndex, 2, "fixture's measured gpmd index (Fixtures/gopro-seam/README.md)")

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: output,
            hasAudio: true,
            sourceParams: infos,
            appliedTimecode: "00:00:00:00",
            sourceGpmdIndex: sourceGpmdIndex,
            isGoProFamily: true
        )

        let result = await SourceTargetVerifier().verifyThorough(input)
        let hashCheck = try XCTUnwrap(result.checks.first { $0.kind == .hashMatch })
        XCTAssertEqual(hashCheck.severity, .pass, "detail: \(hashCheck.detail)")
    }

    /// Falsification counterpart to `testTelemetryCheckFailsWhenTheJoinedOutputHasNoGpmdStream`, one
    /// tier deeper: when the output demonstrably has no gpmd stream, Tier 2 must not itself try to
    /// hash a stream that doesn't exist — it hashes only what it safely can (v:0/a:0), the same
    /// two-entry vector DJI has always produced. Tier 1 is what fails the job overall; Tier 2 must
    /// stay well-behaved alongside that, not crash or silently fabricate a pass on gpmd.
    func testTier2HashSkipsGpmdWhenTheJoinedOutputHasNoGpmdStream() async throws {
        _ = try tools()
        let (segments, _, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let noGpmdOutput = dir.appendingPathComponent("no-gpmd-output-tier2.mp4")
        try await FFmpegWrapper().mergeClips(
            segments, to: noGpmdOutput, dataStreamPolicy: .drop,
            progress: { _, _ in }, logHandler: { _ in }
        )

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: noGpmdOutput,
            hasAudio: true,
            sourceParams: infos,
            appliedTimecode: nil,
            sourceGpmdIndex: infos.first?.dataStreamIndex,
            isGoProFamily: true
        )

        let result = await SourceTargetVerifier().verifyThorough(input)
        let hashCheck = try XCTUnwrap(result.checks.first { $0.kind == .hashMatch })
        XCTAssertEqual(hashCheck.severity, .pass,
                       "v:0/a:0 are genuinely identical — the missing gpmd must not corrupt the hash check too: \(hashCheck.detail)")
        let telemetryCheck = try XCTUnwrap(result.checks.first { $0.label == "Telemetry (gpmd)" })
        XCTAssertEqual(telemetryCheck.severity, .fail,
                       "the overall result must still read as failed via the Tier-1 telemetry check")
        XCTAssertEqual(result.overall, .fail)
    }

    /// The seal-level bug: without a carve-out, `QueueManager.mapStatus`'s "Tier 2 hash pass forgives
    /// Tier 1" rule doesn't know gpmd was never in the hashed set (it fell back to v:0/a:0-only —
    /// see `testTier2HashSkipsGpmdWhenTheJoinedOutputHasNoGpmdStream`) — so a job whose join
    /// **silently dropped telemetry** would seal `.verified`, discarding the one thing Wave G5 exists
    /// to catch. Drives the real `.drop`-policy join → `verifyThorough` → `mapStatus` path end to end,
    /// not a synthetic `SourceTargetResult`, so this proves the production seal, not just the
    /// intermediate check list.
    func testMapStatusSinksTheSealWhenTheJoinedOutputHasNoGpmdStream() async throws {
        _ = try tools()
        let (segments, _, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let noGpmdOutput = dir.appendingPathComponent("no-gpmd-output-mapstatus.mp4")
        try await FFmpegWrapper().mergeClips(
            segments, to: noGpmdOutput, dataStreamPolicy: .drop,
            progress: { _, _ in }, logHandler: { _ in }
        )

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: noGpmdOutput,
            hasAudio: true,
            sourceParams: infos,
            appliedTimecode: nil,
            sourceGpmdIndex: infos.first?.dataStreamIndex,
            isGoProFamily: true
        )
        let result = await SourceTargetVerifier().verifyThorough(input)

        // Sanity: this is exactly the shape the bug needs — hash pass, no tcWriteBack check at all
        // (appliedTimecode is nil), gpmd failed.
        XCTAssertEqual(result.checks.first { $0.kind == .hashMatch }?.severity, .pass)
        XCTAssertNil(result.checks.first { $0.kind == .timecodeWriteback })
        XCTAssertEqual(result.checks.first { $0.kind == .gpmdParity }?.severity, .fail)

        let status = await MainActor.run { QueueManager(storageDirectory: dir).mapStatus(result) }
        guard case .failed = status else {
            return XCTFail("a GoPro job whose join dropped gpmd must seal .failed, not \(status) — " +
                           "hashMatch passing must not launder a proven telemetry loss into .verified")
        }
    }
}
