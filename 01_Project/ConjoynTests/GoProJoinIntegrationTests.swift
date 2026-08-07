import XCTest
@testable import Conjoyn

/// Wave G4.3 — proves the **production** `FFmpegWrapper.mergeClips(...)` join path, not a
/// hand-built argument vector, carries a GoPro `gpmd` telemetry stream across a real chapter seam
/// byte-for-byte. Drives `.preserveTelemetry` against two real Hero 11 slices with the bundled
/// ffmpeg/ffprobe and asserts packet counts *and* byte totals on the joined output — the shipping
/// code path that a wrong `-map` index, a `d:0` selection that grabs `tmcd` instead of `gpmd`, or
/// a dropped data stream would all fail.
///
/// What is proven end-to-end here that the pure unit tests (`FFmpegConcatArgsTests`) do not cover:
///   • The gpmd index is genuinely **probed at join time**, not hardcoded — asserted by capturing
///     `mergeClips`' logged command line and requiring the exact `-map 0:<probed-index>` it used.
///   • The real `-c copy -copy_unknown` join actually preserves telemetry byte-for-byte across a
///     genuine chapter boundary (last GOP of chapter 01 against the first GOP of chapter 02,
///     recording 6349 — see `Fixtures/gopro-seam/README.md` for provenance), not just that the
///     argument vector looks right.
///   • The regenerated `tmcd` track (from `-timecode`) coexists with the preserved `gpmd` track
///     without either being mistaken for the other.
///
/// What stays genuinely footage-gated (documented, not papered over):
///   • Both fixtures probe as `hvc1 | mp4a | gpmd | tmcd` — **gpmd at index 2** — because they were
///     re-muxed to fit under the fixture size cap (ffmpeg cannot copy GoPro's source `tmcd` track,
///     so the cut process drops and regenerates it, after gpmd). A camera-original Hero 11 file
///     carries `hvc1 | mp4a | tmcd | gpmd` — **gpmd at index 3**. That shape is covered by
///     `FFmpegConcatArgsTests`' exact-vector assertions and by the join-time probe in
///     `resolveGpmdStreamIndex`, but not end-to-end here. Task **G8.2** (a real full join of an
///     unsliced GoPro group) closes that gap. This is a known, deliberate limit of the fixture.
///
/// Skips cleanly when the bundled ffmpeg/ffprobe or the fixtures are unavailable.
final class GoProJoinIntegrationTests: XCTestCase {

    // MARK: - Measured baselines (see Fixtures/gopro-seam/README.md)

    private enum Expected {
        static let gpmdPackets = 2
        static let gpmdBytes = 14_000
        static let videoPackets = 52
        static let videoBytes = 12_164_470
        static let audioPackets = 98
        static let audioBytes = 49_459
    }

    // MARK: - Harness

    private func tools() throws -> (ffmpeg: URL, ffprobe: URL) {
        let r = BundledToolResolver.shared
        guard let ffmpeg = r.path(for: .ffmpeg), let ffprobe = r.path(for: .ffprobe) else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }
        return (ffmpeg, ffprobe)
    }

    /// Locates a checked-in gopro-seam fixture. Prefers the test bundle's copy; falls back to the
    /// source tree beside this file. The fallback matters here — the `.MP4` fixtures may not be
    /// copied into the test bundle as resources, and the test must work either way. Skips (rather
    /// than failing) when the fixture is genuinely absent.
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
            .appendingPathComponent("conjoyn-goprojoin-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Thread-safe log-line collector for `mergeClips`' `logHandler`, mirroring
    /// `FFmpegWrapper.OutputCollector`'s lock discipline.
    private final class LogCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var lines: [String] = []
        func append(_ line: String) {
            lock.lock(); lines.append(line); lock.unlock()
        }
        var joined: String {
            lock.lock(); defer { lock.unlock() }
            return lines.joined(separator: "\n")
        }
    }

    // MARK: - ffprobe helpers (independent of production probing, so the assertion is external)

    private struct ProbedStream: Decodable {
        let index: Int
        let codec_type: String?
        let codec_tag_string: String?
    }

    private struct ProbedStreams: Decodable {
        let streams: [ProbedStream]
    }

    private func probeStreams(ffprobe: URL, url: URL) throws -> [ProbedStream] {
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
        return try JSONDecoder().decode(ProbedStreams.self, from: data).streams
    }

    /// Packet count and summed byte size for a stream, selected by ffprobe stream specifier
    /// (`"v:0"`, `"a:0"`, or a plain absolute index such as `"2"`).
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

    // MARK: - The end-to-end join

    func testGoProSeamJoinPreservesTelemetryByteForByte() async throws {
        let (_, ffprobe) = try tools()
        let seg1 = try fixtureURL("GX016349")
        let seg2 = try fixtureURL("GX026349")

        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        let outputURL = dir.appendingPathComponent("joined.mp4")

        let logs = LogCollector()

        try await FFmpegWrapper().mergeClips(
            [seg1, seg2],
            to: outputURL,
            metadata: .init(timecode: "00:00:00:00"),
            dataStreamPolicy: .preserveTelemetry,
            progress: { _, _ in },
            logHandler: { logs.append($0) }
        )

        // 1. The join succeeded and produced a real, non-empty file.
        let attrs = try FileManager.default.attributesOfItem(atPath: outputURL.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0
        XCTAssertGreaterThan(size, 0, "joined output should be non-empty")

        // 2. Exactly one gpmd stream, plus a regenerated tmcd — neither dropped, neither
        //    conflated with the other.
        let outputStreams = try probeStreams(ffprobe: ffprobe, url: outputURL)
        let gpmdStreams = outputStreams.filter { $0.codec_tag_string == "gpmd" }
        let tmcdStreams = outputStreams.filter { $0.codec_tag_string == "tmcd" }
        XCTAssertEqual(gpmdStreams.count, 1, "expected exactly one gpmd stream in the joined output")
        XCTAssertEqual(tmcdStreams.count, 1, "expected exactly one regenerated tmcd stream in the joined output")

        // 3. gpmd packet count and byte total match the measured sums (the byte check is what
        //    catches a dropped track or a d:0 selection that grabbed tmcd instead of gpmd — the
        //    packet count alone is too thin at 1/second against a 1.04 s GOP floor).
        let gpmdIndex = try XCTUnwrap(gpmdStreams.first?.index)
        let gpmdStats = try packetStats(ffprobe: ffprobe, url: outputURL, streamSpecifier: "\(gpmdIndex)")
        XCTAssertEqual(gpmdStats.packets, Expected.gpmdPackets)
        XCTAssertEqual(gpmdStats.bytes, Expected.gpmdBytes)

        // 4. Video and audio parity likewise.
        let videoStats = try packetStats(ffprobe: ffprobe, url: outputURL, streamSpecifier: "v:0")
        XCTAssertEqual(videoStats.packets, Expected.videoPackets)
        XCTAssertEqual(videoStats.bytes, Expected.videoBytes)

        let audioStats = try packetStats(ffprobe: ffprobe, url: outputURL, streamSpecifier: "a:0")
        XCTAssertEqual(audioStats.packets, Expected.audioPackets)
        XCTAssertEqual(audioStats.bytes, Expected.audioBytes)

        // 5. The resolved index was genuinely probed, not assumed: the logged command line must
        //    carry the exact -map for the fixtures' measured gpmd index (2).
        XCTAssertTrue(logs.joined.contains("-map 0:2"),
                      "expected the logged ffmpeg command to map the probed gpmd index (0:2)")
    }
}
