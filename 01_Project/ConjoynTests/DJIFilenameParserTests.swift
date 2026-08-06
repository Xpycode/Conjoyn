import XCTest
@testable import Conjoyn

final class DJIFilenameParserTests: XCTestCase {

    typealias Parsed = DJIFilenameParser.Parsed

    // MARK: - Legacy scheme

    func testLegacyVideo() {
        let p = DJIFilenameParser.parse("DJI_0001.MP4")
        XCTAssertEqual(p?.scheme, .legacy)
        XCTAssertEqual(p?.index, 1)
        XCTAssertNil(p?.timestamp)
        XCTAssertNil(p?.variantSuffix)
        XCTAssertEqual(p?.mediaKind, .video)
        XCTAssertEqual(p?.stem, "DJI_0001")
        XCTAssertEqual(p?.original, "DJI_0001.MP4")
    }

    func testLegacyIndexParsing() {
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0002.MP4")?.index, 2)
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0042.MP4")?.index, 42)
        XCTAssertEqual(DJIFilenameParser.parse("DJI_9999.MP4")?.index, 9999)
    }

    func testLegacySidecars() {
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0001.SRT")?.mediaKind, .telemetry)
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0001.LRF")?.mediaKind, .proxy)
        // Sidecars share the stem with the video → they pair on it.
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0001.SRT")?.stem, "DJI_0001")
    }

    // MARK: - Timestamped scheme + variant suffixes

    func testTimestampedVideo() {
        // From the technical brief: DJI_20230813102011_0008_D.MP4
        let p = DJIFilenameParser.parse("DJI_20230813102011_0008_D.MP4")
        XCTAssertEqual(p?.scheme, .timestamped)
        XCTAssertEqual(p?.index, 8)
        XCTAssertEqual(p?.variantSuffix, "D")
        XCTAssertEqual(p?.mediaKind, .video)
        XCTAssertEqual(p?.stem, "DJI_20230813102011_0008_D")

        let ts = p?.timestamp
        XCTAssertEqual(ts?.year, 2023)
        XCTAssertEqual(ts?.month, 8)
        XCTAssertEqual(ts?.day, 13)
        XCTAssertEqual(ts?.hour, 10)
        XCTAssertEqual(ts?.minute, 20)
        XCTAssertEqual(ts?.second, 11)
    }

    func testVariantSuffixesExtracted() {
        let cases: [(String, String)] = [
            ("DJI_20230813102011_0008_W.MP4", "W"),
            ("DJI_20230813102011_0008_Z.MP4", "Z"),
            ("DJI_20230813102011_0008_T.MP4", "T"),
            ("DJI_20230813102011_0008_V.MP4", "V"),
            ("DJI_20230813102011_0008_S.MP4", "S"),
        ]
        for (name, expected) in cases {
            XCTAssertEqual(DJIFilenameParser.parse(name)?.variantSuffix, expected, "for \(name)")
        }
    }

    func testVariantSuffixDistinguishesGroups() {
        // The whole point of the variant guard: same capture instant, different lens → the
        // parsed suffix differs, so the grouping engine can refuse to merge them.
        let wide = DJIFilenameParser.parse("DJI_20230813102011_0008_W.MP4")
        let zoom = DJIFilenameParser.parse("DJI_20230813102011_0008_Z.MP4")
        XCTAssertNotEqual(wide?.variantSuffix, zoom?.variantSuffix)
        XCTAssertNotEqual(wide?.stem, zoom?.stem)
    }

    func testTimestampedSidecar() {
        let p = DJIFilenameParser.parse("DJI_20230813102011_0008_D.LRF")
        XCTAssertEqual(p?.mediaKind, .proxy)
        XCTAssertEqual(p?.variantSuffix, "D")
        XCTAssertEqual(p?.stem, "DJI_20230813102011_0008_D")
    }

    // MARK: - Robustness

    func testExtensionCaseInsensitive() {
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0001.mp4")?.mediaKind, .video)
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0001.mov")?.mediaKind, .video)
        XCTAssertEqual(DJIFilenameParser.parse("DJI_0001.srt")?.mediaKind, .telemetry)
    }

    func testFullPathAccepted() {
        let url = URL(fileURLWithPath: "/Volumes/CARD/DCIM/100MEDIA/DJI_0007.MP4")
        XCTAssertEqual(DJIFilenameParser.parse(url)?.index, 7)
        XCTAssertEqual(DJIFilenameParser.parse(url)?.stem, "DJI_0007")
    }

    func testNonDJINamesRejected() {
        XCTAssertNil(DJIFilenameParser.parse("IMG_1234.JPG"))
        XCTAssertNil(DJIFilenameParser.parse("DJI_001.MP4"))      // 3 digits, not legacy
        XCTAssertNil(DJIFilenameParser.parse("DJI_20230813102011.MP4")) // no index/suffix
        XCTAssertNil(DJIFilenameParser.parse("random.mp4"))
    }

    // MARK: - Renamed footage (prefixed names)

    /// Real user footage, renamed by an archiving tool: the DJI name is intact but carries a
    /// prefix. Every field must still parse verbatim — before this was allowed, a whole folder of
    /// renamed clips read as "no video segments found".
    func testTimestampedBehindPrefix() {
        let p = DJIFilenameParser.parse("M4P--2026-05-21--19-43-29--DJI_20260521194329_0001_D.MP4")
        XCTAssertEqual(p?.scheme, .timestamped)
        XCTAssertEqual(p?.index, 1)
        XCTAssertEqual(p?.variantSuffix, "D")
        XCTAssertEqual(p?.mediaKind, .video)
        XCTAssertEqual(p?.timestamp?.year, 2026)
        XCTAssertEqual(p?.timestamp?.month, 5)
        XCTAssertEqual(p?.timestamp?.day, 21)
        XCTAssertEqual(p?.timestamp?.hour, 19)
        XCTAssertEqual(p?.timestamp?.minute, 43)
        XCTAssertEqual(p?.timestamp?.second, 29)
        // The stem is the *whole* name — that's what sidecars pair on.
        XCTAssertEqual(p?.stem, "M4P--2026-05-21--19-43-29--DJI_20260521194329_0001_D")
    }

    func testLegacyBehindPrefix() {
        let p = DJIFilenameParser.parse("2026-05-21 flight_DJI_0007.MP4")
        XCTAssertEqual(p?.scheme, .legacy)
        XCTAssertEqual(p?.index, 7)
        XCTAssertNil(p?.variantSuffix)
        XCTAssertEqual(p?.stem, "2026-05-21 flight_DJI_0007")
    }

    /// A renamed video and its renamed `.SRT` carry the same prefix, so they still share a stem —
    /// which is the only thing `DJIFolderReader` pairs sidecars on.
    func testPrefixedSidecarPairsWithVideo() {
        let prefix = "M4P--2026-05-21--19-43-29--"
        let video = DJIFilenameParser.parse(prefix + "DJI_20260521194329_0001_D.MP4")
        let srt = DJIFilenameParser.parse(prefix + "DJI_20260521194329_0001_D.SRT")
        XCTAssertEqual(video?.mediaKind, .video)
        XCTAssertEqual(srt?.mediaKind, .telemetry)
        XCTAssertEqual(video?.stem, srt?.stem)
    }

    /// Two prefixed clips of different lenses must still land in different variant buckets —
    /// the prefix must not blur the hard no-merge boundary.
    func testPrefixedVariantsStillDistinct() {
        let wide = DJIFilenameParser.parse("archive_DJI_20230813102011_0008_W.MP4")
        let tele = DJIFilenameParser.parse("archive_DJI_20230813102011_0008_T.MP4")
        XCTAssertEqual(wide?.variantSuffix, "W")
        XCTAssertEqual(tele?.variantSuffix, "T")
        XCTAssertNotEqual(wide?.stem, tele?.stem)
    }

    /// The prefix must end in a separator, so it can only attach *before* the DJI name — it can
    /// never eat into a word and turn a non-DJI name into a match.
    func testPrefixMustEndInSeparator() {
        XCTAssertNil(DJIFilenameParser.parse("MYDJI_0001.MP4"))
        XCTAssertNil(DJIFilenameParser.parse("XDJI_20230813102011_0008_D.MP4"))
    }

    /// The tail stays anchored: a *trailing* addition is still not a DJI name. This is what stops
    /// the app's own `…_joined` output from being re-ingested as source footage.
    func testTrailingAdditionsStillRejected() {
        XCTAssertNil(DJIFilenameParser.parse("DJI_0001_joined.MP4"))
        XCTAssertNil(DJIFilenameParser.parse("DJI_20230813102011_0008_D_joined.MP4"))
        XCTAssertNil(DJIFilenameParser.parse("M4P--2026-05-21--DJI_0001_joined.MP4"))
    }
}
