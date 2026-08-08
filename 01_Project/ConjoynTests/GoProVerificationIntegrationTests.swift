import XCTest
@testable import Conjoyn

/// Wave G5.1 — proves the Tier 0/1 pass genuinely checks the gpmd telemetry stream through the
/// **real** join + verify path, not a synthetic stand-in. Reuses the same real Hero 11 seam
/// fixtures `GoProJoinIntegrationTests` joins (`Fixtures/gopro-seam/`), builds a
/// `SourceTargetVerifier.SourceTargetInput` the way `QueueManager+Verification.makeVerifierInput`
/// does, and asserts the emitted telemetry check both passes when pointed at the correct gpmd
/// indices and — falsified — fails when pointed at the wrong stream instead (the exact hazard
/// decision 4 exists to rule out: a `d:0` selector can resolve to `tmcd`, not `gpmd`).
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
            outputGpmdIndex: 2
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

    // MARK: - Falsification (hard rule 3 / decision 4): the wrong stream must FAIL, never pass

    /// Stands in for the exact hazard decision 4 rules out: a `d:0` stream-specifier resolving to
    /// the regenerated `tmcd` track instead of `gpmd`. Points `outputGpmdIndex` at the output's
    /// real (probed, not guessed) `tmcd` index and asserts the telemetry check goes **red** — a
    /// green result here would mean the mechanism can't actually distinguish the two streams, i.e.
    /// the exact "passing check that verified the wrong thing" failure mode the decision exists to
    /// prevent.
    func testTelemetryCheckFailsWhenPointedAtTheRegeneratedTmcdInstead() async throws {
        let (_, ffprobe) = try tools()
        let (segments, output, infos, dir) = try await joinFixtures()
        defer { try? FileManager.default.removeItem(at: dir) }

        let tmcdIndex = try XCTUnwrap(
            try probeStreamIndex(ffprobe: ffprobe, url: output, codecTag: "tmcd"),
            "expected a regenerated tmcd stream in the joined output"
        )

        let input = SourceTargetVerifier.SourceTargetInput(
            sourceSegments: segments,
            outputURL: output,
            hasAudio: true,
            sourceParams: infos,
            appliedTimecode: "00:00:00:00",
            sourceGpmdIndex: infos.first?.dataStreamIndex,   // still correct on the source side
            outputGpmdIndex: tmcdIndex                        // wrong: tmcd, not gpmd
        )

        let result = await SourceTargetVerifier().verifyFast(input)
        let countCheck = try XCTUnwrap(result.checks.first { $0.label == "Packet count (telemetry)" })
        XCTAssertEqual(countCheck.severity, .fail,
                       "selecting the wrong stream must fail loudly, never pass silently — detail: \(countCheck.detail)")
    }
}
