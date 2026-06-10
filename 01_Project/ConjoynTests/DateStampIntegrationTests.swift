import XCTest
@testable import Conjoyn

/// Integration coverage for task 2.8 (date + start-timecode stamping). Drives the **real**
/// `FFmpegWrapper.mergeClips` path with synthetic clips and reads the stamp back with real ffprobe,
/// so the production arg vector (`buildMergeArguments` → `-metadata creation_time` + `-timecode`,
/// with `-map -0:d` clearing any source data/`tmcd`) is exercised, not just the pure resolver.
///
/// The resolver's signal-priority logic is unit-tested in `RecordingStartResolverTests`; this file
/// proves the bytes actually land in the container. Skips cleanly when no ffmpeg/ffprobe is present.
final class DateStampIntegrationTests: XCTestCase {

    private func tools() throws -> (ffmpeg: URL, ffprobe: URL) {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg),
              let ffprobe = resolver.path(for: .ffprobe) else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }
        return (ffmpeg, ffprobe)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-stamp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func generateClip(ffmpeg: URL, to url: URL) throws {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=160x120:rate=25",
                       "-pix_fmt", "yuv420p", url.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ffmpeg failed to generate clip")
    }

    /// Runs ffprobe and returns the trimmed value of a single `-show_entries` field.
    private func probe(_ ffprobe: URL, _ args: [String]) -> String {
        let p = Process()
        p.executableURL = ffprobe
        p.arguments = ["-v", "error"] + args
        let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
        let data = out.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The real join stamps both `creation_time` and a `tmcd` start timecode, and ffprobe reads
    /// them back verbatim from the muxed output.
    func testMergeStampsCreationTimeAndTimecode() async throws {
        let (ffmpeg, ffprobe) = try tools()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.mp4")
        let b = dir.appendingPathComponent("b.mp4")
        let out = dir.appendingPathComponent("joined.mp4")
        try generateClip(ffmpeg: ffmpeg, to: a)
        try generateClip(ffmpeg: ffmpeg, to: b)

        // Mirror what `resolveJoinMetadata` builds from a resolved 19:53:03.448 local start at 25 fps.
        let metadata = FFmpegWrapper.JoinMetadata(
            creationTime: "2026-05-21T17:53:03.000Z",
            timecode: "19:53:03:11"
        )

        try await FFmpegWrapper().mergeClips([a, b], to: out, metadata: metadata, progress: { _, _ in })

        XCTAssertTrue(FileManager.default.fileExists(atPath: out.path), "join produced no output")

        let creation = probe(ffprobe, ["-show_entries", "format_tags=creation_time",
                                       "-of", "default=nokey=1:noprint_wrappers=1", out.path])
        XCTAssertTrue(creation.hasPrefix("2026-05-21T17:53:03"),
                      "creation_time not stamped, got '\(creation)'")

        let timecode = probe(ffprobe, ["-select_streams", "d", "-show_entries", "stream_tags=timecode",
                                       "-of", "default=nokey=1:noprint_wrappers=1", out.path])
        XCTAssertEqual(timecode, "19:53:03:11", "start timecode not stamped (got '\(timecode)')")
    }

    /// With both stamps suppressed (the toggles are off upstream), the join writes neither tag —
    /// guarding against an accidental always-stamp regression.
    func testEmptyMetadataStampsNothing() async throws {
        let (ffmpeg, ffprobe) = try tools()
        let dir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: dir) }

        let a = dir.appendingPathComponent("a.mp4")
        let b = dir.appendingPathComponent("b.mp4")
        let out = dir.appendingPathComponent("joined.mp4")
        try generateClip(ffmpeg: ffmpeg, to: a)
        try generateClip(ffmpeg: ffmpeg, to: b)

        try await FFmpegWrapper().mergeClips([a, b], to: out, metadata: .init(), progress: { _, _ in })

        let timecode = probe(ffprobe, ["-select_streams", "d", "-show_entries", "stream_tags=timecode",
                                       "-of", "default=nokey=1:noprint_wrappers=1", out.path])
        XCTAssertTrue(timecode.isEmpty, "expected no timecode track, got '\(timecode)'")
    }
}
