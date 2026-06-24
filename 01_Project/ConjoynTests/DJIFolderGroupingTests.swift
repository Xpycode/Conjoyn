import XCTest
@testable import Conjoyn

/// Backpressure for task 2.4 — metadata-continuity grouping (`DJIFolderReader.groupMetas`).
///
/// Fixtures are taken **verbatim from real DJI card footage** (`/Volumes/2CULL/2CULL-IN/DJI_001`,
/// 2026-06): a slow-motion split chain (where playback duration is 4× real elapsed and would break
/// a naive duration-continuity rule), a normal-speed chain, a near-cap final segment, filename
/// indices that reset and collide, and the camera-variant boundary. The grouping core chains on the
/// **file-size split cap + real wall-clock start**, never on playback duration or filename order.
final class DJIFolderGroupingTests: XCTestCase {

    typealias Meta = DJIFolderReader.SegmentMeta
    typealias Guard = StreamParameterGuard

    // MARK: Helpers

    /// `creation_time` as DJI writes it (UTC). e.g. `"17:53:03"` on the fixture day.
    private func utc(_ hms: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: "2026-05-21T\(hms)Z")!
    }

    /// HEVC 4K params shared by the fixture clips (the real footage is all hevc 3840×2160).
    private func params(fps: String = "25/1") -> Guard.SegmentStreamInfo {
        .init(video: .init(codecName: "hevc", width: 3840, height: 2160,
                           pixelFormat: "yuv420p10le", avgFrameRate: fps, timeBase: "1/100000"),
              audio: nil)
    }

    private func meta(_ stem: String, idx: Int, start: Date, durS: Double, size: Int64,
                      variant: String? = "D", info: Guard.SegmentStreamInfo? = nil) -> Meta {
        Meta(id: UUID(), variantSuffix: variant, creationDate: start, containerSeconds: durS,
             sizeBytes: size, streamInfo: info ?? params(), index: idx, stem: stem)
    }

    /// Maps a grouping result to runs of stems for readable assertions.
    private func stems(_ runs: [[Meta]]) -> [[String]] {
        runs.map { $0.map(\.stem) }
    }

    // MARK: - Slow-motion split chain (the keystone case)

    /// May 21 100fps footage: container duration ~794 s but real elapsed only ~199 s. Two recordings
    /// back-to-back; each ends at its first sub-cap segment, the next capped segment starts a new one.
    func testSlowMotionChainGroupsByCapAndRealTime() {
        let metas = [
            meta("0006", idx: 6, start: utc("17:53:03"), durS: 794.84, size: 3_764_025_581),
            meta("0007", idx: 7, start: utc("17:56:23"), durS: 794.32, size: 3_761_046_584),
            meta("0008", idx: 8, start: utc("17:59:41"), durS: 794.56, size: 3_762_590_379),
            meta("0009", idx: 9, start: utc("18:03:00"), durS: 488.00, size: 2_311_478_850), // sub-cap → ends
            meta("0010", idx: 10, start: utc("18:06:16"), durS: 794.48, size: 3_762_964_936), // new recording
            meta("0011", idx: 11, start: utc("18:09:35"), durS: 794.16, size: 3_760_925_114),
            meta("0012", idx: 12, start: utc("18:12:53"), durS: 794.20, size: 3_761_093_109),
            meta("0013", idx: 13, start: utc("18:16:12"), durS: 212.32, size: 1_006_038_008), // sub-cap → ends
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)),
                       [["0006", "0007", "0008", "0009"], ["0010", "0011", "0012", "0013"]])
    }

    // MARK: - Normal-speed chain + near-cap final

    /// Jun 7 normal speed: 0104/0105 capped, 0106 (3.22 GB) under cap → final of the same recording.
    /// 0107 is a separate single. (Times reused on the fixture day; only gaps matter.)
    func testNormalSpeedChainIncludesSubCapFinalThenSplitsNextClip() {
        let metas = [
            meta("0104", idx: 104, start: utc("14:44:34"), durS: 326.8, size: 3_760_858_167),
            meta("0105", idx: 105, start: utc("14:50:01"), durS: 327.0, size: 3_760_921_664),
            meta("0106", idx: 106, start: utc("14:55:28"), durS: 279.6, size: 3_216_770_202), // under cap → final
            meta("0107", idx: 107, start: utc("15:00:12"), durS: 62.8, size: 724_458_971),    // separate single
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)),
                       [["0104", "0105", "0106"], ["0107"]])
    }

    /// A 3.41 GB segment sits just under the cap of a 3.76 GB set — it must END the recording, not
    /// be mistaken for a continuing segment. (Mar 18 {0009..0012}: 0012 is the 3.41 GB final.)
    func testNearCapSegmentEndsTheRecording() {
        let metas = [
            meta("0009", idx: 9, start: utc("16:44:42"), durS: 793.32, size: 3_761_098_478),
            meta("0010", idx: 10, start: utc("16:48:01"), durS: 793.24, size: 3_760_680_106),
            meta("0011", idx: 11, start: utc("16:51:20"), durS: 793.44, size: 3_760_771_842),
            meta("0012", idx: 12, start: utc("16:54:38"), durS: 718.72, size: 3_407_698_668), // 3.41 GB → final
            meta("0013", idx: 13, start: utc("16:58:29"), durS: 83.24, size: 396_311_112),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)),
                       [["0009", "0010", "0011", "0012"], ["0013"]])
    }

    // MARK: - Boundaries & defensiveness

    /// A long pause: the previous recording's final is sub-cap, so even a same-params clip soon after
    /// starts a new group. And a capped segment whose next clip is far beyond its playback length is
    /// NOT chained.
    func testCappedSegmentNotChainedWhenNextStartsTooLate() {
        let metas = [
            // Capped, but the next clip starts ~30 min later → new recording, not a continuation.
            meta("0014", idx: 14, start: utc("18:48:13"), durS: 794.56, size: 3_762_939_588),
            meta("0099", idx: 99, start: utc("19:20:00"), durS: 100.0, size: 500_000_000),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["0014"], ["0099"]])
    }

    /// The hard no-merge boundary: clips of different camera/lens variants never share a group, even
    /// when capped and time-adjacent.
    func testNeverMergesAcrossCameraVariants() {
        let metas = [
            meta("W0006", idx: 6, start: utc("17:53:03"), durS: 794.84, size: 3_764_025_581, variant: "W"),
            meta("T0006", idx: 6, start: utc("17:53:04"), durS: 794.84, size: 3_764_025_581, variant: "T"),
            meta("W0007", idx: 7, start: utc("17:56:23"), durS: 794.32, size: 3_761_046_584, variant: "W"),
            meta("T0007", idx: 7, start: utc("17:56:24"), durS: 794.32, size: 3_761_046_584, variant: "T"),
        ]
        let result = Set(stems(DJIFolderReader.groupMetas(metas)).map { Set($0) })
        XCTAssertEqual(result, [Set(["W0006", "W0007"]), Set(["T0006", "T0007"])])
    }

    /// Stream-parameter mismatch (different frame rate) breaks a chain even if size/time would allow
    /// it — a `-c copy` join across mismatched params would corrupt.
    func testParamMismatchBreaksChain() {
        let metas = [
            meta("0006", idx: 6, start: utc("17:53:03"), durS: 794.84, size: 3_764_025_581, info: params(fps: "25/1")),
            meta("0007", idx: 7, start: utc("17:56:23"), durS: 794.32, size: 3_761_046_584, info: params(fps: "30000/1001")),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["0006"], ["0007"]])
    }

    // MARK: - Missing middle segment (deleted / dropped / lost on the card)

    /// Baseline: four contiguous normal-speed segments (each ~327 s, real elapsed ≈ playback) form a
    /// single recording. Used as the control for the missing-middle cases below.
    func testContiguousNormalChainIsOneGroup() {
        let metas = [
            meta("0006", idx: 6, start: utc("10:00:00"), durS: 327.0, size: 3_760_000_000),
            meta("0007", idx: 7, start: utc("10:05:27"), durS: 327.0, size: 3_760_000_000),
            meta("0008", idx: 8, start: utc("10:10:54"), durS: 327.0, size: 3_760_000_000),
            meta("0009", idx: 9, start: utc("10:16:21"), durS: 220.0, size: 2_500_000_000), // sub-cap → final
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)),
                       [["0006", "0007", "0008", "0009"]])
    }

    /// Missing middle, **normal speed** — the emergent protection works. Drop `0008` from the chain
    /// above. The deleted segment's own ~327 s of recording still occupies the wall-clock gap between
    /// its neighbours, so `0007`→`0009` is 654 s apart — far past `0007`'s 327 s playback length + 12 s
    /// slack. The chain therefore SPLITS at the hole: continuity is preserved on each side
    /// (`0006,0007` stay merged) and the orphaned tail (`0009`) becomes its own group. No silent
    /// bridge across the missing segment. There is no explicit index-gap check — this falls out of the
    /// real wall-clock continuity rule alone.
    func testMissingMiddleSegmentSplitsChainAtGap_normalSpeed() {
        let metas = [
            meta("0006", idx: 6, start: utc("10:00:00"), durS: 327.0, size: 3_760_000_000),
            meta("0007", idx: 7, start: utc("10:05:27"), durS: 327.0, size: 3_760_000_000),
            // 0008 deleted — the hole.
            meta("0009", idx: 9, start: utc("10:16:21"), durS: 220.0, size: 2_500_000_000),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)),
                       [["0006", "0007"], ["0009"]])
    }

    /// Missing middle, **slow motion** — the case the wall-clock bound alone cannot catch, now closed
    /// by the index-gap guard (`continues` step 3). These are the real May-21 100 fps fixture numbers
    /// (container ≈ 794 s, real elapsed ≈ 199 s). Drop `0007`: `0006`→`0008` is only ~398 s of real
    /// time apart, which still fits inside `0006`'s 794 s *playback* length + slack — so the wall-clock
    /// rule would have silently merged them across the hole (a join with a ~3.3-minute discontinuity
    /// and an SRT misaligned after the seam). The index jump 6→8 trips the guard first, so the chain
    /// SPLITS instead. Regression lock for the slow-mo missing-middle fix (decisions.md, 2026-06-24).
    func testMissingMiddleSegmentSplitsChainAtGap_slowMotion() {
        let metas = [
            meta("0006", idx: 6, start: utc("17:53:03"), durS: 794.84, size: 3_764_025_581),
            // 0007 deleted — the hole that slow-mo's loose wall-clock bound cannot detect, but the
            // index jump 6→8 does.
            meta("0008", idx: 8, start: utc("17:59:41"), durS: 794.56, size: 3_762_590_379),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)),
                       [["0006"], ["0008"]])
    }

    /// Defensive: without a real `creation_time` we can't confirm continuity, so a capped segment is
    /// not chained (matches the decision to treat DJI's zeroed/wrong timecode defensively).
    func testMissingCreationDatePreventsChaining() {
        let metas = [
            Meta(id: UUID(), variantSuffix: "D", creationDate: nil, containerSeconds: 794.84,
                 sizeBytes: 3_764_025_581, streamInfo: params(), index: 6, stem: "0006"),
            Meta(id: UUID(), variantSuffix: "D", creationDate: nil, containerSeconds: 794.32,
                 sizeBytes: 3_761_046_584, streamInfo: params(), index: 7, stem: "0007"),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["0006"], ["0007"]])
    }

    /// A folder of only short clips (none near a 4 GB cap) → every clip is its own single group.
    func testAllShortClipsAreSingles() {
        let metas = [
            meta("0001", idx: 1, start: utc("17:43:29"), durS: 457.68, size: 2_168_247_308),
            meta("0003", idx: 3, start: utc("17:45:45"), durS: 268.64, size: 1_275_048_307),
            meta("0004", idx: 4, start: utc("17:47:15"), durS: 222.16, size: 1_054_476_707),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["0001"], ["0003"], ["0004"]])
    }

    func testEmptyInputYieldsNoGroups() {
        XCTAssertTrue(DJIFolderReader.groupMetas([]).isEmpty)
    }
}
