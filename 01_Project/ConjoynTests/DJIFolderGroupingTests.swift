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

    // MARK: - GoPro chaptered chain (G3.2, `continuesGoPro`)

    /// Fixtures below are transcribed from the real 71-file Hero 11 corpus (recordings 6338/6347/
    /// 6348, `gopro/corpus.csv`) — the same real numbers used to size
    /// `timecodeContinuitySlackSeconds`'s default.

    /// `creation_time` as ffprobe writes it (UTC) for a given calendar date, e.g.
    /// `gpUtc("2026-08-04", "16:40:00")`.
    private func gpUtc(_ date: String, _ hms: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: "\(date)T\(hms)Z")!
    }

    /// HEVC 4K params matching the real Hero 11 corpus footage (`hvc1|mp4a|tmcd|gpmd`, gpmd probed
    /// at stream index 3).
    private func goProParams(codec: String = "hevc", fps: String = "100/1") -> Guard.SegmentStreamInfo {
        .init(video: .init(codecName: codec, width: 3840, height: 2160, pixelFormat: "yuv420p",
                           avgFrameRate: fps, timeBase: "1/90000", rFrameRate: fps),
              audio: .init(codecName: "aac", sampleRate: "48000", channels: 2, channelLayout: "stereo"),
              dataStreamIndex: 3, dataCodecTag: "gpmd")
    }

    /// Builds a GoPro `SegmentMeta` fixture. `tc`/`fps` derive `startTimecodeSeconds` through the
    /// real production conversion (`DJIFolderReader.resolveStartTimecodeSeconds`) — the same path
    /// `group(_:)` uses for a probed `DJIClip` — so fixtures exercise the actual conversion instead
    /// of a hand-computed duplicate that could drift from it.
    private func goProMeta(_ stem: String, recording: Int, chapter: Int, tc: String, fps: Double,
                          creation: Date, durS: Double, size: Int64,
                          info: Guard.SegmentStreamInfo? = nil) -> Meta {
        var m = Meta(id: UUID(), variantSuffix: nil, creationDate: creation, containerSeconds: durS,
                     sizeBytes: size, streamInfo: info ?? goProParams(fps: "\(Int(fps))/1"),
                     index: chapter, stem: stem)
        m.family = .goPro
        m.recordingNumber = recording
        m.startTimecodeSeconds = DJIFolderReader.resolveStartTimecodeSeconds(timecode: tc, framesPerSecond: fps)
        return m
    }

    /// Baseline: two consecutive chapters of one recording chain into a single group (recording
    /// 6347, chapters 01–02).
    func testGoProValidTwoChapterChainGroups() {
        let creation = gpUtc("2026-08-04", "16:40:00")
        let metas = [
            goProMeta("GX016347", recording: 6347, chapter: 1, tc: "18:40:00:24", fps: 100,
                      creation: creation, durS: 768.0, size: 11_508_180_971),
            goProMeta("GX026347", recording: 6347, chapter: 2, tc: "18:52:48:24", fps: 100,
                      creation: creation, durS: 768.0, size: 11_509_900_589),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["GX016347", "GX026347"]])
    }

    /// Rule (e), the load-bearing GoPro divergence from DJI: recording 6338's two chapters share
    /// an **identical** `creation_time` (DJI's `gap > 0` wall-clock rule would refuse this outright),
    /// and the final chapter (876 MB) sits nowhere near any plausible size cap (DJI's step-1 cap gate
    /// only applies to the chapter that continues, but structurally `continuesGoPro` never even
    /// receives a `capThreshold` to gate on). Both chapters still chain into one group — proving
    /// timecode continuity alone carries the rule.
    func testGoProChainsAcrossIdenticalCreationTimeAndFarUnderCapFinalChapter() {
        let creation = gpUtc("2026-08-03", "11:52:11")
        let metas = [
            goProMeta("GX016338", recording: 6338, chapter: 1, tc: "13:52:11:64", fps: 100,
                      creation: creation, durS: 1536.000, size: 11_497_577_082),
            goProMeta("GX026338", recording: 6338, chapter: 2, tc: "14:17:47:64", fps: 100,
                      creation: creation, durS: 116.992, size: 875_947_819),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["GX016338", "GX026338"]])
    }

    /// A chapter gap (01 + 03, 02 missing) must not be bridged — rule (b), consecutive chapters.
    func testGoProChapterGapRefusesChain() {
        let creation = gpUtc("2026-08-04", "16:40:00")
        let metas = [
            goProMeta("GX016347", recording: 6347, chapter: 1, tc: "18:40:00:24", fps: 100,
                      creation: creation, durS: 768.0, size: 11_508_180_971),
            // chapter 02 absent — the hole.
            goProMeta("GX036347", recording: 6347, chapter: 3, tc: "19:05:36:24", fps: 100,
                      creation: creation, durS: 768.0, size: 11_508_221_014),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["GX016347"], ["GX036347"]])
    }

    /// Different recordings (different file numbers) never merge, even when chapter numbering and
    /// stream params would otherwise look chainable — rule (a), recording identity.
    func testGoProDifferentRecordingNumberRefusesChain() {
        let metas = [
            goProMeta("GX016347", recording: 6347, chapter: 1, tc: "18:40:00:24", fps: 100,
                      creation: gpUtc("2026-08-04", "16:40:00"), durS: 768.0, size: 11_508_180_971),
            goProMeta("GX016348", recording: 6348, chapter: 1, tc: "19:34:02:54", fps: 100,
                      creation: gpUtc("2026-08-04", "17:34:02"), durS: 768.0, size: 11_508_578_322),
        ]
        XCTAssertEqual(Set(stems(DJIFolderReader.groupMetas(metas)).map(Set.init)),
                       [Set(["GX016347"]), Set(["GX016348"])])
    }

    /// Missing timecode on either side blocks the chain — locked decision 5, never bridge on a
    /// signal we don't have.
    func testGoProMissingTimecodeRefusesChain() {
        let creation = gpUtc("2026-08-03", "11:52:11")
        var prev = goProMeta("GX016338", recording: 6338, chapter: 1, tc: "13:52:11:64", fps: 100,
                             creation: creation, durS: 1536.000, size: 11_497_577_082)
        prev.startTimecodeSeconds = nil // unresolved timecode (e.g. drop-frame or unparseable string)
        let next = goProMeta("GX026338", recording: 6338, chapter: 2, tc: "14:17:47:64", fps: 100,
                             creation: creation, durS: 116.992, size: 875_947_819)
        XCTAssertEqual(stems(DJIFolderReader.groupMetas([prev, next])), [["GX016338"], ["GX026338"]])
    }

    /// Incompatible stream params (mismatched codec) break the chain even with valid chapter
    /// numbering and timecode continuity — rule (c), mirrors `continuesDJI`'s step 4.
    func testGoProStreamParamMismatchRefusesChain() {
        let creation = gpUtc("2026-08-03", "11:52:11")
        let metas = [
            goProMeta("GX016338", recording: 6338, chapter: 1, tc: "13:52:11:64", fps: 100,
                      creation: creation, durS: 1536.000, size: 11_497_577_082,
                      info: goProParams(codec: "hevc")),
            goProMeta("GX026338", recording: 6338, chapter: 2, tc: "14:17:47:64", fps: 100,
                      creation: creation, durS: 116.992, size: 875_947_819,
                      info: goProParams(codec: "h264")),
        ]
        XCTAssertEqual(stems(DJIFolderReader.groupMetas(metas)), [["GX016338"], ["GX026338"]])
    }

    /// A DJI segment and a GoPro segment never co-group, even when other signals could line up —
    /// `continues`'s family dispatch refuses cross-family chains outright.
    func testDJIAndGoProNeverCoGroup() {
        let djiSegment = meta("0006", idx: 6, start: utc("17:53:03"), durS: 794.84, size: 3_764_025_581)
        let goProSegment = goProMeta("GX016338", recording: 6338, chapter: 1, tc: "13:52:11:64",
                                     fps: 100, creation: gpUtc("2026-08-03", "11:52:11"),
                                     durS: 1536.000, size: 11_497_577_082)
        let result = stems(DJIFolderReader.groupMetas([djiSegment, goProSegment]))
        XCTAssertEqual(Set(result.map(Set.init)), [Set(["0006"]), Set(["GX016338"])])
    }

    // MARK: - Full 71-file corpus fixtures (G3.3)

    /// One row of the real 71-file Hero 11 corpus (`gopro/corpus.csv`) — `size_bytes`,
    /// `format_duration`, `format_creation_time`, `video_timecode`, `r_frame_rate`, `width`,
    /// `height` and `n_streams` transcribed verbatim (re-diffed against the source CSV after
    /// transcription; no value here was estimated).
    private struct CorpusRow {
        let stem: String
        let recording: Int
        let chapter: Int
        let sizeBytes: Int64
        let durationS: Double
        /// `format_creation_time` with the always-`.000000` fractional part dropped.
        let creationTime: String
        let timecode: String
        let fps: Double
        let width: Int
        let height: Int
        let hasAudio: Bool
    }

    /// All 71 corpus rows: 6 multi-chapter recordings (20 chapters: 6338×2, 6345×4, 6346×4,
    /// 6347×5, 6348×3, 6349×2) plus 51 single-chapter files.
    private static let corpusRows: [CorpusRow] = [
        CorpusRow(stem: "GX014604", recording: 4604, chapter: 1, sizeBytes: 191_238_231, durationS: 25.520000, creationTime: "2026-08-01T14:30:29Z", timecode: "16:30:29:80", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014605", recording: 4605, chapter: 1, sizeBytes: 162_596_563, durationS: 21.610667, creationTime: "2026-08-01T14:31:08Z", timecode: "16:31:08:58", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014606", recording: 4606, chapter: 1, sizeBytes: 144_329_858, durationS: 19.200000, creationTime: "2026-08-01T14:31:42Z", timecode: "16:31:42:67", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014607", recording: 4607, chapter: 1, sizeBytes: 293_775_407, durationS: 39.110000, creationTime: "2026-08-01T14:32:18Z", timecode: "16:32:18:40", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014608", recording: 4608, chapter: 1, sizeBytes: 441_640_754, durationS: 58.890000, creationTime: "2026-08-01T14:33:12Z", timecode: "16:33:12:78", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014609", recording: 4609, chapter: 1, sizeBytes: 287_657_351, durationS: 38.410000, creationTime: "2026-08-01T14:34:59Z", timecode: "16:34:59:40", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014610", recording: 4610, chapter: 1, sizeBytes: 85_603_655, durationS: 11.530000, creationTime: "2026-08-01T14:35:41Z", timecode: "16:35:41:76", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014611", recording: 4611, chapter: 1, sizeBytes: 388_262_830, durationS: 51.870000, creationTime: "2026-08-01T14:36:13Z", timecode: "16:36:13:98", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014612", recording: 4612, chapter: 1, sizeBytes: 186_474_562, durationS: 24.880000, creationTime: "2026-08-01T14:38:33Z", timecode: "16:38:33:97", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014613", recording: 4613, chapter: 1, sizeBytes: 175_196_839, durationS: 23.370000, creationTime: "2026-08-01T14:39:07Z", timecode: "16:39:07:36", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014616", recording: 4616, chapter: 1, sizeBytes: 853_263_792, durationS: 114.709333, creationTime: "2026-08-01T14:41:10Z", timecode: "16:41:10:041", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014617", recording: 4617, chapter: 1, sizeBytes: 1_945_294_462, durationS: 104.160000, creationTime: "2026-08-01T14:45:07Z", timecode: "16:45:07:05", fps: 25, width: 5312, height: 2988, hasAudio: false),
        CorpusRow(stem: "GX014618", recording: 4618, chapter: 1, sizeBytes: 308_665_363, durationS: 41.350000, creationTime: "2026-08-02T11:16:02Z", timecode: "13:16:02:148", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014619", recording: 4619, chapter: 1, sizeBytes: 963_803_487, durationS: 129.536000, creationTime: "2026-08-02T11:23:10Z", timecode: "13:23:10:138", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014620", recording: 4620, chapter: 1, sizeBytes: 1_221_679_426, durationS: 164.250000, creationTime: "2026-08-02T11:29:05Z", timecode: "13:29:05:047", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014621", recording: 4621, chapter: 1, sizeBytes: 30_323_433, durationS: 2.520000, creationTime: "2026-08-02T11:32:04Z", timecode: "13:32:04:24", fps: 25, width: 5312, height: 2988, hasAudio: false),
        CorpusRow(stem: "GX014622", recording: 4622, chapter: 1, sizeBytes: 25_526_393, durationS: 2.280000, creationTime: "2026-08-02T11:33:00Z", timecode: "13:33:00:09", fps: 25, width: 5312, height: 2988, hasAudio: false),
        CorpusRow(stem: "GX014623", recording: 4623, chapter: 1, sizeBytes: 9_752_752, durationS: 1.280000, creationTime: "2026-08-02T11:44:07Z", timecode: "13:44:07:127", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014624", recording: 4624, chapter: 1, sizeBytes: 3_780_949_141, durationS: 508.270000, creationTime: "2026-08-02T11:44:23Z", timecode: "13:44:23:015", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014625", recording: 4625, chapter: 1, sizeBytes: 1_254_008_732, durationS: 168.555000, creationTime: "2026-08-02T11:52:55Z", timecode: "13:52:55:017", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014626", recording: 4626, chapter: 1, sizeBytes: 546_322_563, durationS: 73.455000, creationTime: "2026-08-02T11:56:37Z", timecode: "13:56:37:112", fps: 200, width: 2704, height: 1520, hasAudio: true),
        CorpusRow(stem: "GX014627", recording: 4627, chapter: 1, sizeBytes: 1_003_064_339, durationS: 79.740000, creationTime: "2026-08-02T13:30:16Z", timecode: "15:30:16:00", fps: 50, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014628", recording: 4628, chapter: 1, sizeBytes: 784_411_772, durationS: 56.980000, creationTime: "2026-08-02T13:31:39Z", timecode: "15:31:39:41", fps: 50, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014629", recording: 4629, chapter: 1, sizeBytes: 76_542_575, durationS: 4.560000, creationTime: "2026-08-02T13:32:47Z", timecode: "15:32:47:20", fps: 25, width: 5312, height: 2988, hasAudio: false),
        CorpusRow(stem: "GX014630", recording: 4630, chapter: 1, sizeBytes: 368_649_504, durationS: 49.220000, creationTime: "2026-08-02T13:33:57Z", timecode: "15:33:57:97", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014631", recording: 4631, chapter: 1, sizeBytes: 471_042_689, durationS: 62.920000, creationTime: "2026-08-02T13:35:03Z", timecode: "15:35:03:24", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014632", recording: 4632, chapter: 1, sizeBytes: 782_209_828, durationS: 104.490667, creationTime: "2026-08-02T13:36:10Z", timecode: "15:36:10:65", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014633", recording: 4633, chapter: 1, sizeBytes: 1_814_584_914, durationS: 242.581333, creationTime: "2026-08-02T13:37:58Z", timecode: "15:37:58:30", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014634", recording: 4634, chapter: 1, sizeBytes: 1_183_254_192, durationS: 158.186667, creationTime: "2026-08-02T13:42:34Z", timecode: "15:42:34:80", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014635", recording: 4635, chapter: 1, sizeBytes: 243_347_593, durationS: 32.500000, creationTime: "2026-08-02T13:45:28Z", timecode: "15:45:28:38", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014636", recording: 4636, chapter: 1, sizeBytes: 247_985_034, durationS: 33.152000, creationTime: "2026-08-02T13:46:04Z", timecode: "15:46:04:21", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX014637", recording: 4637, chapter: 1, sizeBytes: 24_994_648, durationS: 3.285333, creationTime: "2026-08-02T13:46:57Z", timecode: "15:46:57:71", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016317", recording: 6317, chapter: 1, sizeBytes: 639_065_194, durationS: 85.610667, creationTime: "2026-08-03T11:04:27Z", timecode: "13:04:27:55", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016318", recording: 6318, chapter: 1, sizeBytes: 266_830_010, durationS: 35.584000, creationTime: "2026-08-03T11:06:24Z", timecode: "13:06:24:21", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016319", recording: 6319, chapter: 1, sizeBytes: 1_309_175_938, durationS: 174.870000, creationTime: "2026-08-03T11:07:39Z", timecode: "13:07:39:45", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016320", recording: 6320, chapter: 1, sizeBytes: 763_541_845, durationS: 101.980000, creationTime: "2026-08-03T11:12:13Z", timecode: "13:12:13:03", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016321", recording: 6321, chapter: 1, sizeBytes: 13_561_650, durationS: 1.770667, creationTime: "2026-08-03T11:15:31Z", timecode: "13:15:31:44", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016330", recording: 6330, chapter: 1, sizeBytes: 604_378_131, durationS: 80.770000, creationTime: "2026-08-03T11:17:09Z", timecode: "13:17:09:68", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016332", recording: 6332, chapter: 1, sizeBytes: 1_308_582_835, durationS: 174.784000, creationTime: "2026-08-03T11:23:32Z", timecode: "13:23:32:01", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016333", recording: 6333, chapter: 1, sizeBytes: 1_309_762_572, durationS: 175.018667, creationTime: "2026-08-03T11:27:14Z", timecode: "13:27:14:59", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016334", recording: 6334, chapter: 1, sizeBytes: 8_352_780, durationS: 1.130667, creationTime: "2026-08-03T11:30:15Z", timecode: "13:30:15:32", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016335", recording: 6335, chapter: 1, sizeBytes: 10_780_615, durationS: 1.365333, creationTime: "2026-08-03T11:30:19Z", timecode: "13:30:19:52", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016336", recording: 6336, chapter: 1, sizeBytes: 1_443_335_154, durationS: 192.789333, creationTime: "2026-08-03T11:30:25Z", timecode: "13:30:25:20", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016337", recording: 6337, chapter: 1, sizeBytes: 810_560_889, durationS: 108.310000, creationTime: "2026-08-03T11:33:55Z", timecode: "13:33:55:04", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016338", recording: 6338, chapter: 1, sizeBytes: 11_497_577_082, durationS: 1536.000000, creationTime: "2026-08-03T11:52:11Z", timecode: "13:52:11:64", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX026338", recording: 6338, chapter: 2, sizeBytes: 875_947_819, durationS: 116.992000, creationTime: "2026-08-03T11:52:11Z", timecode: "14:17:47:64", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016339", recording: 6339, chapter: 1, sizeBytes: 385_514_470, durationS: 51.456000, creationTime: "2026-08-03T14:03:27Z", timecode: "16:03:27:97", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016340", recording: 6340, chapter: 1, sizeBytes: 347_441_200, durationS: 46.430000, creationTime: "2026-08-03T14:04:23Z", timecode: "16:04:23:94", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016341", recording: 6341, chapter: 1, sizeBytes: 1_001_109_839, durationS: 133.696000, creationTime: "2026-08-03T14:06:59Z", timecode: "16:06:59:51", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016342", recording: 6342, chapter: 1, sizeBytes: 1_545_648_081, durationS: 206.464000, creationTime: "2026-08-03T14:10:36Z", timecode: "16:10:36:44", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016343", recording: 6343, chapter: 1, sizeBytes: 15_743_525, durationS: 2.010000, creationTime: "2026-08-03T14:14:22Z", timecode: "16:14:22:16", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016344", recording: 6344, chapter: 1, sizeBytes: 3_597_003_759, durationS: 480.670000, creationTime: "2026-08-03T14:14:36Z", timecode: "16:14:36:38", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016345", recording: 6345, chapter: 1, sizeBytes: 11_527_010_739, durationS: 768.000000, creationTime: "2026-08-04T14:40:19Z", timecode: "16:40:19:14", fps: 50, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX026345", recording: 6345, chapter: 2, sizeBytes: 11_525_698_088, durationS: 768.000000, creationTime: "2026-08-04T14:40:19Z", timecode: "16:53:07:14", fps: 50, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX036345", recording: 6345, chapter: 3, sizeBytes: 11_526_559_433, durationS: 768.000000, creationTime: "2026-08-04T14:40:19Z", timecode: "17:05:55:14", fps: 50, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX046345", recording: 6345, chapter: 4, sizeBytes: 8_632_759_614, durationS: 575.200000, creationTime: "2026-08-04T14:40:19Z", timecode: "17:18:43:14", fps: 50, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016346", recording: 6346, chapter: 1, sizeBytes: 11_509_170_326, durationS: 768.000000, creationTime: "2026-08-04T15:49:22Z", timecode: "17:49:22:05", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX026346", recording: 6346, chapter: 2, sizeBytes: 11_508_963_481, durationS: 768.000000, creationTime: "2026-08-04T15:49:22Z", timecode: "18:02:10:05", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX036346", recording: 6346, chapter: 3, sizeBytes: 11_509_459_522, durationS: 768.000000, creationTime: "2026-08-04T15:49:22Z", timecode: "18:14:58:05", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX046346", recording: 6346, chapter: 4, sizeBytes: 7_621_196_150, durationS: 508.608000, creationTime: "2026-08-04T15:49:22Z", timecode: "18:27:46:05", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016347", recording: 6347, chapter: 1, sizeBytes: 11_508_180_971, durationS: 768.000000, creationTime: "2026-08-04T16:40:00Z", timecode: "18:40:00:24", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX026347", recording: 6347, chapter: 2, sizeBytes: 11_509_900_589, durationS: 768.000000, creationTime: "2026-08-04T16:40:00Z", timecode: "18:52:48:24", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX036347", recording: 6347, chapter: 3, sizeBytes: 11_508_221_014, durationS: 768.000000, creationTime: "2026-08-04T16:40:00Z", timecode: "19:05:36:24", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX046347", recording: 6347, chapter: 4, sizeBytes: 11_508_873_678, durationS: 768.000000, creationTime: "2026-08-04T16:40:00Z", timecode: "19:18:24:24", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX056347", recording: 6347, chapter: 5, sizeBytes: 1_854_029_367, durationS: 123.780000, creationTime: "2026-08-04T16:40:00Z", timecode: "19:31:12:24", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016348", recording: 6348, chapter: 1, sizeBytes: 11_508_578_322, durationS: 768.000000, creationTime: "2026-08-04T17:34:02Z", timecode: "19:34:02:54", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX026348", recording: 6348, chapter: 2, sizeBytes: 11_508_768_918, durationS: 768.000000, creationTime: "2026-08-04T17:34:02Z", timecode: "19:46:50:54", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX036348", recording: 6348, chapter: 3, sizeBytes: 10_184_502_461, durationS: 679.660000, creationTime: "2026-08-04T17:34:02Z", timecode: "19:59:38:54", fps: 100, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016349", recording: 6349, chapter: 1, sizeBytes: 11_646_991_608, durationS: 2063.360000, creationTime: "2026-08-04T18:14:42Z", timecode: "20:14:42:06", fps: 25, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX026349", recording: 6349, chapter: 2, sizeBytes: 1_846_935_493, durationS: 327.240000, creationTime: "2026-08-04T18:14:42Z", timecode: "20:49:05:15", fps: 25, width: 3840, height: 2160, hasAudio: true),
        CorpusRow(stem: "GX016350", recording: 6350, chapter: 1, sizeBytes: 7_656_985_895, durationS: 1022.920000, creationTime: "2026-08-04T19:00:19Z", timecode: "21:00:19:50", fps: 100, width: 3840, height: 2160, hasAudio: true),
    ]

    private func corpusUtc(_ iso: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: iso)!
    }

    /// Stream params for a corpus row. Codec is `hevc` in all 71 files; resolution, fps, and
    /// audio presence vary per row (4 files in the corpus have no audio stream).
    private func corpusParams(width: Int, height: Int, fps: Double, hasAudio: Bool) -> Guard.SegmentStreamInfo {
        let fpsRational = "\(Int(fps))/1"
        return .init(video: .init(codecName: "hevc", width: width, height: height, pixelFormat: "yuv420p",
                                  avgFrameRate: fpsRational, timeBase: "1/90000", rFrameRate: fpsRational),
                     audio: hasAudio
                        ? .init(codecName: "aac", sampleRate: "48000", channels: 2, channelLayout: "stereo")
                        : nil,
                     dataStreamIndex: hasAudio ? 3 : 2, dataCodecTag: "gpmd")
    }

    /// Builds one corpus row into a GoPro `SegmentMeta`, deriving `startTimecodeSeconds` through
    /// the real production conversion (as `goProMeta` above does for the smaller G3.2 fixtures).
    private func corpusMeta(_ row: CorpusRow) -> Meta {
        var m = Meta(id: UUID(), variantSuffix: nil, creationDate: corpusUtc(row.creationTime),
                    containerSeconds: row.durationS, sizeBytes: row.sizeBytes,
                    streamInfo: corpusParams(width: row.width, height: row.height, fps: row.fps, hasAudio: row.hasAudio),
                    index: row.chapter, stem: row.stem)
        m.family = .goPro
        m.recordingNumber = row.recording
        m.startTimecodeSeconds = DJIFolderReader.resolveStartTimecodeSeconds(timecode: row.timecode, framesPerSecond: row.fps)
        return m
    }

    private func corpusGroups() -> [[Meta]] {
        DJIFolderReader.groupMetas(Self.corpusRows.map(corpusMeta))
    }

    /// Given the full 71-file corpus, grouping produces exactly 6 multi-chapter groups and 51
    /// single-chapter groups, accounting for every file.
    func testFullCorpusProduces6MultiChapterGroupsAnd51SingleChapterFiles() {
        let groups = corpusGroups()
        XCTAssertEqual(groups.filter { $0.count > 1 }.count, 6)
        XCTAssertEqual(groups.filter { $0.count == 1 }.count, 51)
        XCTAssertEqual(groups.reduce(0) { $0 + $1.count }, 71)
    }

    /// Recording 6347 (5 chapters) is one group, ordered ch01–05, totalling the measured
    /// duration and byte count.
    func testFullCorpusRecording6347IsOneGroupOfFiveOrderedByChapter() throws {
        let group = try XCTUnwrap(corpusGroups().first { $0.first?.recordingNumber == 6347 })
        XCTAssertEqual(group.map(\.stem), ["GX016347", "GX026347", "GX036347", "GX046347", "GX056347"])
        XCTAssertEqual(group.reduce(0.0) { $0 + $1.containerSeconds }, 3195.780, accuracy: 0.0005)
        XCTAssertEqual(group.reduce(Int64(0)) { $0 + $1.sizeBytes }, 47_889_205_619)
    }

    /// Recording 6338's two chapters share an **identical** `creation_time` — asserted explicitly
    /// so this test documents why the DJI wall-clock rule (which requires `gap > 0`) would have
    /// refused this real chain — yet they still chain into one group of 2, totalling the measured
    /// duration.
    func testFullCorpusRecording6338ChainsDespiteIdenticalCreationTime() throws {
        let group = try XCTUnwrap(corpusGroups().first { $0.first?.recordingNumber == 6338 })
        XCTAssertEqual(group.map(\.stem), ["GX016338", "GX026338"])
        XCTAssertEqual(group.first?.creationDate, group.last?.creationDate)
        XCTAssertEqual(group.reduce(0.0) { $0 + $1.containerSeconds }, 1652.992, accuracy: 0.0005)
    }

    /// `GX016350`, recorded minutes after recording 6349 finished, never merges into 6349 despite
    /// the temporal adjacency — different file number, different recording.
    func testFullCorpusGX016350NeverMergesIntoRecording6349() throws {
        let groups = corpusGroups()
        let single = try XCTUnwrap(groups.first { $0.contains { $0.stem == "GX016350" } })
        XCTAssertEqual(single.map(\.stem), ["GX016350"])
        let recording6349 = try XCTUnwrap(groups.first { $0.first?.recordingNumber == 6349 })
        XCTAssertEqual(recording6349.map(\.stem), ["GX016349", "GX026349"])
    }

    /// Across the corpus's mix of 25/50/100/200 fps and 3 resolutions, no group ever spans more
    /// than one recording number, and every multi-chapter group stays internally uniform in
    /// resolution and fps — the mix itself is real, not incidental to this fixture set.
    func testFullCorpusNoCrossRecordingMergeAcrossMixedFpsAndResolutions() {
        let groups = corpusGroups()
        for group in groups {
            XCTAssertEqual(Set(group.map(\.recordingNumber)).count, 1)
        }
        for group in groups where group.count > 1 {
            XCTAssertEqual(Set(group.compactMap { $0.streamInfo?.video.width }).count, 1)
            XCTAssertEqual(Set(group.compactMap { $0.streamInfo?.video.height }).count, 1)
            XCTAssertEqual(Set(group.compactMap { $0.streamInfo?.video.avgFrameRate }).count, 1)
        }
        XCTAssertEqual(Set(Self.corpusRows.map { "\($0.width)x\($0.height)" }),
                       ["3840x2160", "2704x1520", "5312x2988"])
        XCTAssertEqual(Set(Self.corpusRows.map(\.fps)), [25, 50, 100, 200])
    }

    /// Recording 6347's own chapters 01 and 03 (02 withheld), drawn from the same corpus table as
    /// the fixtures above: the gap is never bridged.
    func testFullCorpusChapterGapNeverBridged() {
        let rows = Self.corpusRows.filter { $0.recording == 6347 && [1, 3].contains($0.chapter) }
        let groups = DJIFolderReader.groupMetas(rows.map(corpusMeta))
        XCTAssertEqual(groups.map { $0.map(\.stem) }, [["GX016347"], ["GX036347"]])
    }
}
