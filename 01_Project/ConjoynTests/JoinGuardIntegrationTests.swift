import XCTest
@testable import Conjoyn

/// Wave 6.5 — closing the "footage-gated" join-guard edge cases with **synthetic real-tool
/// fixtures** instead of real multi-lens drone footage. The project's Mini 4 Pro is single-camera
/// (every clip is `_D`), and real DJI multi-lens *split* video + original filenames + SRT is not
/// downloadable anywhere (verified 2026-06-24). So rather than leave the variant / mixed-codec
/// guards proven only by hand-built params, these tests drive the **production** guard path against
/// clips made by the bundled LGPL ffmpeg and probed by the bundled ffprobe — exercising the real
/// ffprobe-JSON shape and the real refusal / no-merge decisions on actual files.
///
/// What is proven end-to-end here that the pure unit tests do not cover:
///   • mixed **codec name** → `ensureJoinable` refuses. (`StreamParameterGuardTests`' real-probe
///     test only varies *resolution*; this varies the codec itself — the headline 6.5 case.)
///   • mixed **frame rate** → refused (DJI's real cross-mode mismatch).
///   • camera/lens **variant** suffixes parsed by the real `DJIFilenameParser` never share a group,
///     even when size / time / index would otherwise chain them.
///
/// What stays genuinely footage-gated (documented, not papered over):
///   • The LGPL ffmpeg build ships **no x264/x265**, so the codec pair below is `mpeg4`/`mjpeg`,
///     not the `h264`/`hevc` a real card carries. The guard compares codec-name *strings*, so the
///     code path is identical — but the exact DJI bytes cannot be synthesized on this build.
///   • Real **multi-lens index numbering** (Mavic 3 Pro / thermal) is unknowable without such a
///     drone; the variant test asserts the documented single-camera consecutive-numbering model.
///
/// Skips cleanly when no ffmpeg/ffprobe is present (e.g. CI without the bundled binaries).
final class JoinGuardIntegrationTests: XCTestCase {

    typealias Guard = StreamParameterGuard

    // MARK: - Harness

    private func tools() throws -> (ffmpeg: URL, ffprobe: URL) {
        let r = BundledToolResolver.shared
        guard let ffmpeg = r.path(for: .ffmpeg), let ffprobe = r.path(for: .ffprobe) else {
            throw XCTSkip("No ffmpeg/ffprobe available (bundled or Homebrew)")
        }
        return (ffmpeg, ffprobe)
    }

    private func makeTempDir() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("conjoyn-joinguard-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Generates a 1-second synthetic clip with an explicit codec / fps / size, so exactly one
    /// join-relevant field can be varied at a time. Returns the written URL.
    @discardableResult
    private func generateClip(ffmpeg: URL, to url: URL, codec: String = "mpeg4",
                             fps: Int = 30, size: String = "160x120",
                             pixelFormat: String = "yuv420p") throws -> URL {
        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=\(size):rate=\(fps)",
                       "-c:v", codec, "-pix_fmt", pixelFormat, url.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        XCTAssertEqual(p.terminationStatus, 0, "ffmpeg failed to generate \(codec)@\(fps)fps clip")
        return url
    }

    private func fileSize(_ url: URL) throws -> Int64 {
        let n = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
        return n?.int64Value ?? 0
    }

    // MARK: - Codec / frame-rate refusal (the real-ffprobe → guard path)

    /// Mixed **codec** is refused end-to-end: an `mpeg4` clip + an `mjpeg` clip, probed by the real
    /// ffprobe, fail `ensureJoinable` with a codec-named reason. (mpeg4/mjpeg stands in for the
    /// h264/hevc a real card carries — the LGPL build can't encode the latter; the guard compares
    /// codec-name strings, so the path is identical.)
    func testRealCodecMismatchRefused() throws {
        let (ffmpeg, _) = try tools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }

        let a = try generateClip(ffmpeg: ffmpeg, to: dir.appendingPathComponent("a.mp4"), codec: "mpeg4")
        let b = try generateClip(ffmpeg: ffmpeg, to: dir.appendingPathComponent("b.mp4"),
                                 codec: "mjpeg", pixelFormat: "yuvj420p")

        XCTAssertThrowsError(try FFmpegWrapper().ensureJoinable([a, b])) { error in
            guard case Guard.GuardError.incompatible(let reason) = error else {
                return XCTFail("expected .incompatible, got \(error)")
            }
            XCTAssertTrue(reason.lowercased().contains("codec"),
                          "refusal should name the codec field, got: \(reason)")
        }
    }

    /// Mixed **frame rate** (25 vs 30 fps, identical codec/resolution) is refused — DJI's real
    /// cross-mode mismatch (e.g. a 25 fps clip dropped next to a 30 fps one).
    func testRealFrameRateMismatchRefused() throws {
        let (ffmpeg, _) = try tools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }

        let a = try generateClip(ffmpeg: ffmpeg, to: dir.appendingPathComponent("a.mp4"), fps: 30)
        let b = try generateClip(ffmpeg: ffmpeg, to: dir.appendingPathComponent("b.mp4"), fps: 25)

        XCTAssertThrowsError(try FFmpegWrapper().ensureJoinable([a, b])) { error in
            guard case Guard.GuardError.incompatible(let reason) = error else {
                return XCTFail("expected .incompatible, got \(error)")
            }
            XCTAssertTrue(reason.lowercased().contains("frame rate"),
                          "refusal should name the frame-rate field, got: \(reason)")
        }
    }

    /// Positive control on the same real path: two identical clips pass `ensureJoinable`, proving the
    /// refusals above are caused by the varied field and not by the probe pipeline itself.
    func testRealMatchingPairIsJoinable() throws {
        let (ffmpeg, _) = try tools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }
        let a = try generateClip(ffmpeg: ffmpeg, to: dir.appendingPathComponent("a.mp4"))
        let b = try generateClip(ffmpeg: ffmpeg, to: dir.appendingPathComponent("b.mp4"))
        XCTAssertNoThrow(try FFmpegWrapper().ensureJoinable([a, b]))
    }

    // MARK: - Variant no-merge (real parser + real probe → grouping)

    /// Camera/lens **variant** suffixes never share a group. Four clips are *written to disk* with
    /// authentic DJI timestamped names (`_W` / `_T`), then run through the **real**
    /// `DJIFilenameParser` (variant + index extraction) and **real** `probeStreamInfo` (ffprobe
    /// stream params) before grouping — so the no-merge boundary is proven on the production
    /// parse+probe path, not on hand-set fields. The two segments of each lens are written one
    /// second apart so that, *within a lens*, they genuinely chain — which is what makes the
    /// assertion meaningful: the split is the variant boundary doing work, not everything trivially
    /// falling out as under-cap singles.
    ///
    /// Cap floor is lowered for this fixture only: `groupMetas`' 3 GB floor exists so a folder of
    /// *short* clips doesn't read as split-capped, but synthetic clips are bytes-tiny, so the test
    /// drops the floor to let them register as "capped" and attempt to chain.
    ///
    /// Footage-gated caveat: this asserts the single-camera consecutive-numbering model. Real
    /// multi-lens enterprise numbering (Mavic 3 Pro / thermal) needs such a drone and is not
    /// reproducible on this hardware.
    func testVariantSuffixesNeverMergeThroughRealParseAndProbe() throws {
        let (ffmpeg, _) = try tools()
        let dir = try makeTempDir(); defer { try? FileManager.default.removeItem(at: dir) }

        // Two lenses (W, T), two consecutive capped segments each, written 1 s apart so same-lens
        // segments chain. Cross-lens clips share size/index and near-identical times — only the
        // variant suffix differs, so any merge across them would be the bug this guards against.
        let base = utc("17:53:03")
        let specs: [(name: String, date: Date)] = [
            ("DJI_20260521175303_0006_W.MP4", base),
            ("DJI_20260521175304_0007_W.MP4", base.addingTimeInterval(1)),
            ("DJI_20260521175303_0006_T.MP4", base),
            ("DJI_20260521175304_0007_T.MP4", base.addingTimeInterval(1)),
        ]

        var metas: [DJIFolderReader.SegmentMeta] = []
        for spec in specs {
            let url = dir.appendingPathComponent(spec.name)
            try generateClip(ffmpeg: ffmpeg, to: url)

            let parsed = try XCTUnwrap(DJIFilenameParser.parse(url), "parser returned nil for \(spec.name)")
            let info = try FFmpegWrapper().probeStreamInfo(url)
            metas.append(.init(
                id: UUID(),
                variantSuffix: parsed.variantSuffix,
                creationDate: spec.date,
                containerSeconds: 1.0,
                sizeBytes: try fileSize(url),
                streamInfo: info,
                index: parsed.index,
                stem: parsed.stem
            ))
        }

        // Let the tiny synthetic clips read as split-capped (default floor is 3 GB; fraction lowered
        // too so trivial size variance between clips can't drop one below the cap).
        var tolerances = DJIFolderReader.GroupingTolerances()
        tolerances.capSizeFloorBytes = 1
        tolerances.capSizeFraction = 0.5

        let groups = DJIFolderReader.groupMetas(metas, tolerances: tolerances)

        // No group may span more than one variant.
        for group in groups {
            let variants = Set(group.map(\.variantSuffix))
            XCTAssertEqual(variants.count, 1, "a group spans multiple variants: \(variants)")
        }

        // Exactly one recording per lens, each chaining its two consecutive segments.
        XCTAssertEqual(groups.count, 2, "expected one group per lens (W, T)")
        let byVariant = Dictionary(grouping: groups.flatMap { $0 }) { $0.variantSuffix ?? "?" }
        XCTAssertEqual(byVariant["W"]?.map(\.index).sorted(), [6, 7], "W lens should chain 0006→0007")
        XCTAssertEqual(byVariant["T"]?.map(\.index).sorted(), [6, 7], "T lens should chain 0006→0007")
    }

    /// `creation_time` as DJI writes it (UTC), matching the grouping unit tests' fixture day.
    private func utc(_ hms: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: "2026-05-21T\(hms)Z")!
    }
}
