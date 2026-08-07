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

    // MARK: - Camera family (DJI side)

    /// DJI names must carry the new `family`/`recordingNumber` fields with their DJI-side values —
    /// added as a standalone assertion rather than folded into the 16 existing DJI cases above, so
    /// those cases stay provably unmodified.
    func testDJIParsedCarriesFamilyAndNoRecordingNumber() {
        let legacy = DJIFilenameParser.parse("DJI_0001.MP4")
        XCTAssertEqual(legacy?.family, .dji)
        XCTAssertNil(legacy?.recordingNumber)

        let timestamped = DJIFilenameParser.parse("DJI_20230813102011_0008_D.MP4")
        XCTAssertEqual(timestamped?.family, .dji)
        XCTAssertNil(timestamped?.recordingNumber)

        let prefixed = DJIFilenameParser.parse("M4P--2026-05-21--19-43-29--DJI_20260521194329_0001_D.MP4")
        XCTAssertEqual(prefixed?.family, .dji)
        XCTAssertNil(prefixed?.recordingNumber)
    }

    // MARK: - GoPro chaptered scheme

    func testGoProChapteredVideo() {
        let p = DJIFilenameParser.parse("GX016338.MP4")
        XCTAssertEqual(p?.scheme, .goProChaptered)
        XCTAssertEqual(p?.family, .goPro)
        XCTAssertEqual(p?.index, 1)                 // chapter rides in `index`
        XCTAssertEqual(p?.recordingNumber, 6338)
        XCTAssertNil(p?.timestamp)
        XCTAssertNil(p?.variantSuffix)
        XCTAssertEqual(p?.mediaKind, .video)
        XCTAssertEqual(p?.stem, "GX016338")
        XCTAssertEqual(p?.original, "GX016338.MP4")
    }

    /// Real user footage, renamed by an archiving tool — the same optional rename-prefix rule
    /// that applies to DJI names applies to GoPro ones too.
    func testGoProChapteredBehindPrefix() {
        let p = DJIFilenameParser.parse("H11--2026-08-03--11-52-11--GX026338.MP4")
        XCTAssertEqual(p?.family, .goPro)
        XCTAssertEqual(p?.index, 2)
        XCTAssertEqual(p?.recordingNumber, 6338)
        XCTAssertEqual(p?.stem, "H11--2026-08-03--11-52-11--GX026338")
    }

    /// The tail stays anchored, exactly like the DJI regexes: the app must never re-ingest its
    /// own `…_joined` output as a fresh GoPro source segment.
    func testGoProTrailingAdditionRejected() {
        XCTAssertNil(DJIFilenameParser.parse("GX016338_joined.mp4"))
    }

    /// `GH` (chaptered AVC naming) is accepted with the same structure as `GX`.
    func testGoProGHAcceptedWithSameStructure() {
        let p = DJIFilenameParser.parse("GH010123.MP4")
        XCTAssertEqual(p?.family, .goPro)
        XCTAssertEqual(p?.index, 1)
        XCTAssertEqual(p?.recordingNumber, 123)
    }

    /// GoPro's older, non-chaptered naming schemes are out of scope for this pass and must not
    /// be misparsed as the chaptered form.
    func testGoProLegacyNamesRejected() {
        XCTAssertNil(DJIFilenameParser.parse("GOPR0123.MP4"))
        XCTAssertNil(DJIFilenameParser.parse("GP010123.MP4"))
    }

    /// The measured 71-file 2026-08 corpus: every filename, its expected chapter, and its
    /// expected file number. Transcribed from the authoritative corpus listing (in-memory only —
    /// no dependency on the source folder or volume at test run time).
    private static let corpus: [(filename: String, chapter: Int, fileNumber: Int)] = [
        ("H11--2026-08-01--14-30-29--GX014604.MP4", 1, 4604),
        ("H11--2026-08-01--14-31-08--GX014605.MP4", 1, 4605),
        ("H11--2026-08-01--14-31-42--GX014606.MP4", 1, 4606),
        ("H11--2026-08-01--14-32-18--GX014607.MP4", 1, 4607),
        ("H11--2026-08-01--14-33-12--GX014608.MP4", 1, 4608),
        ("H11--2026-08-01--14-34-59--GX014609.MP4", 1, 4609),
        ("H11--2026-08-01--14-35-41--GX014610.MP4", 1, 4610),
        ("H11--2026-08-01--14-36-13--GX014611.MP4", 1, 4611),
        ("H11--2026-08-01--14-38-33--GX014612.MP4", 1, 4612),
        ("H11--2026-08-01--14-39-07--GX014613.MP4", 1, 4613),
        ("H11--2026-08-01--14-41-10--GX014616.MP4", 1, 4616),
        ("H11--2026-08-01--14-45-07--GX014617.MP4", 1, 4617),
        ("H11--2026-08-02--11-16-02--GX014618.MP4", 1, 4618),
        ("H11--2026-08-02--11-23-10--GX014619.MP4", 1, 4619),
        ("H11--2026-08-02--11-29-05--GX014620.MP4", 1, 4620),
        ("H11--2026-08-02--11-32-04--GX014621.MP4", 1, 4621),
        ("H11--2026-08-02--11-33-00--GX014622.MP4", 1, 4622),
        ("H11--2026-08-02--11-44-07--GX014623.MP4", 1, 4623),
        ("H11--2026-08-02--11-44-23--GX014624.MP4", 1, 4624),
        ("H11--2026-08-02--11-52-55--GX014625.MP4", 1, 4625),
        ("H11--2026-08-02--11-56-37--GX014626.MP4", 1, 4626),
        ("H11--2026-08-02--13-30-16--GX014627.MP4", 1, 4627),
        ("H11--2026-08-02--13-31-39--GX014628.MP4", 1, 4628),
        ("H11--2026-08-02--13-32-47--GX014629.MP4", 1, 4629),
        ("H11--2026-08-02--13-33-57--GX014630.MP4", 1, 4630),
        ("H11--2026-08-02--13-35-03--GX014631.MP4", 1, 4631),
        ("H11--2026-08-02--13-36-10--GX014632.MP4", 1, 4632),
        ("H11--2026-08-02--13-37-58--GX014633.MP4", 1, 4633),
        ("H11--2026-08-02--13-42-34--GX014634.MP4", 1, 4634),
        ("H11--2026-08-02--13-45-28--GX014635.MP4", 1, 4635),
        ("H11--2026-08-02--13-46-04--GX014636.MP4", 1, 4636),
        ("H11--2026-08-02--13-46-57--GX014637.MP4", 1, 4637),
        ("H11--2026-08-03--11-04-27--GX016317.MP4", 1, 6317),
        ("H11--2026-08-03--11-06-24--GX016318.MP4", 1, 6318),
        ("H11--2026-08-03--11-07-39--GX016319.MP4", 1, 6319),
        ("H11--2026-08-03--11-12-13--GX016320.MP4", 1, 6320),
        ("H11--2026-08-03--11-15-31--GX016321.MP4", 1, 6321),
        ("H11--2026-08-03--11-17-09--GX016330.MP4", 1, 6330),
        ("H11--2026-08-03--11-23-32--GX016332.MP4", 1, 6332),
        ("H11--2026-08-03--11-27-14--GX016333.MP4", 1, 6333),
        ("H11--2026-08-03--11-30-15--GX016334.MP4", 1, 6334),
        ("H11--2026-08-03--11-30-19--GX016335.MP4", 1, 6335),
        ("H11--2026-08-03--11-30-25--GX016336.MP4", 1, 6336),
        ("H11--2026-08-03--11-33-55--GX016337.MP4", 1, 6337),
        ("H11--2026-08-03--11-52-11--GX016338.MP4", 1, 6338),
        ("H11--2026-08-03--11-52-11--GX026338.MP4", 2, 6338),
        ("H11--2026-08-03--14-03-27--GX016339.MP4", 1, 6339),
        ("H11--2026-08-03--14-04-23--GX016340.MP4", 1, 6340),
        ("H11--2026-08-03--14-06-59--GX016341.MP4", 1, 6341),
        ("H11--2026-08-03--14-10-36--GX016342.MP4", 1, 6342),
        ("H11--2026-08-03--14-14-22--GX016343.MP4", 1, 6343),
        ("H11--2026-08-03--14-14-36--GX016344.MP4", 1, 6344),
        ("H11--2026-08-04--14-40-19--GX016345.MP4", 1, 6345),
        ("H11--2026-08-04--14-40-19--GX026345.MP4", 2, 6345),
        ("H11--2026-08-04--14-40-19--GX036345.MP4", 3, 6345),
        ("H11--2026-08-04--14-40-19--GX046345.MP4", 4, 6345),
        ("H11--2026-08-04--15-49-22--GX016346.MP4", 1, 6346),
        ("H11--2026-08-04--15-49-22--GX026346.MP4", 2, 6346),
        ("H11--2026-08-04--15-49-22--GX036346.MP4", 3, 6346),
        ("H11--2026-08-04--15-49-22--GX046346.MP4", 4, 6346),
        ("H11--2026-08-04--16-40-00--GX016347.MP4", 1, 6347),
        ("H11--2026-08-04--16-40-00--GX026347.MP4", 2, 6347),
        ("H11--2026-08-04--16-40-00--GX036347.MP4", 3, 6347),
        ("H11--2026-08-04--16-40-00--GX046347.MP4", 4, 6347),
        ("H11--2026-08-04--16-40-00--GX056347.MP4", 5, 6347),
        ("H11--2026-08-04--17-34-02--GX016348.MP4", 1, 6348),
        ("H11--2026-08-04--17-34-02--GX026348.MP4", 2, 6348),
        ("H11--2026-08-04--17-34-02--GX036348.MP4", 3, 6348),
        ("H11--2026-08-04--18-14-42--GX016349.MP4", 1, 6349),
        ("H11--2026-08-04--18-14-42--GX026349.MP4", 2, 6349),
        ("H11--2026-08-04--19-00-19--GX016350.MP4", 1, 6350),
    ]

    /// All 71 corpus filenames parse with the correct (chapter, recordingNumber) pair and zero
    /// misclassification.
    func testGoProCorpusAllParseCorrectly() {
        XCTAssertEqual(Self.corpus.count, 71)
        for entry in Self.corpus {
            let p = DJIFilenameParser.parse(entry.filename)
            XCTAssertEqual(p?.family, .goPro, "for \(entry.filename)")
            XCTAssertEqual(p?.scheme, .goProChaptered, "for \(entry.filename)")
            XCTAssertEqual(p?.index, entry.chapter, "chapter mismatch for \(entry.filename)")
            XCTAssertEqual(p?.recordingNumber, entry.fileNumber, "file number mismatch for \(entry.filename)")
        }
    }
}
