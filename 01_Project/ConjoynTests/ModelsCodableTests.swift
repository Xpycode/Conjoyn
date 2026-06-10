import XCTest
import CoreMedia
@testable import Conjoyn

/// Wave 1.2/1.3 model-layer tests. The keystone is `testConversionJobFullCodableRoundTrip` — a
/// fully-populated `ConversionJob` (embedded `DJIClip` + `SegmentStreamInfo` + CMTime backing,
/// `JobStatus.failed`, `VerificationStatus.failed`, bookmark `Data`) survives a JSON round-trip
/// byte-for-byte. Queue persistence is the single load-bearing behavior of these models.
final class ModelsCodableTests: XCTestCase {

    // MARK: - Helpers

    private func roundTrip<T: Codable>(_ value: T, as type: T.Type) throws -> T {
        let data = try JSONEncoder().encode(value)
        return try JSONDecoder().decode(type, from: data)
    }

    /// A representative segment's probed stream parameters.
    private func sampleStreamInfo() -> StreamParameterGuard.SegmentStreamInfo {
        StreamParameterGuard.SegmentStreamInfo(
            video: .init(
                codecName: "hevc",
                width: 3840,
                height: 2160,
                pixelFormat: "yuv420p10le",
                avgFrameRate: "30000/1001",
                timeBase: "1/30000"
            ),
            audio: .init(
                codecName: "aac",
                sampleRate: "48000",
                channels: 2,
                channelLayout: "stereo"
            )
        )
    }

    /// A fully-populated clip with an NTSC-fraction duration (exercises exact CMTime backing).
    private func sampleClip(index: Int = 8) -> DJIClip {
        var ts = DateComponents()
        ts.year = 2023; ts.month = 8; ts.day = 13
        ts.hour = 10; ts.minute = 20; ts.second = 11
        return DJIClip(
            videoURL: URL(fileURLWithPath: "/Volumes/SD/DCIM/100MEDIA/DJI_20230813102011_0008_D.MP4"),
            srtURL: URL(fileURLWithPath: "/Volumes/SD/DCIM/100MEDIA/DJI_20230813102011_0008_D.SRT"),
            lrfURL: URL(fileURLWithPath: "/Volumes/SD/DCIM/100MEDIA/DJI_20230813102011_0008_D.LRF"),
            index: index,
            variantSuffix: "D",
            filenameTimestamp: ts,
            stem: "DJI_20230813102011_0008_D",
            creationDate: Date(timeIntervalSinceReferenceDate: 712_345_678),
            cameraModel: "DJI Mavic 3 Pro",
            duration: CMTime(value: 30_000, timescale: 1001),
            streamInfo: sampleStreamInfo()
        )
    }

    // MARK: - DJIClip

    func testDJIClipDurationCMTimeIsExactAcrossRoundTrip() throws {
        let clip = sampleClip()
        // 30000/1001 ≈ 29.97 — the classic NTSC fraction a Double would mangle.
        XCTAssertEqual(clip.duration, CMTime(value: 30_000, timescale: 1001))
        let decoded = try roundTrip(clip, as: DJIClip.self)
        XCTAssertEqual(decoded.duration.value, 30_000)
        XCTAssertEqual(decoded.duration.timescale, 1001)
        XCTAssertEqual(decoded.duration, clip.duration)
    }

    func testDJIClipFullRoundTripPreservesEveryField() throws {
        let clip = sampleClip()
        let decoded = try roundTrip(clip, as: DJIClip.self)
        // Synthesized Equatable compares all stored fields (paths, backing, embedded streamInfo).
        XCTAssertEqual(decoded, clip)
        XCTAssertEqual(decoded.videoURL, clip.videoURL)
        XCTAssertEqual(decoded.srtURL, clip.srtURL)
        XCTAssertEqual(decoded.lrfURL, clip.lrfURL)
        XCTAssertEqual(decoded.streamInfo, clip.streamInfo)
        XCTAssertEqual(decoded.filenameTimestamp, clip.filenameTimestamp)
        XCTAssertEqual(decoded.creationDate, clip.creationDate)
        XCTAssertEqual(decoded.cameraModel, "DJI Mavic 3 Pro")
    }

    func testDJIClipOptionalSidecarsRoundTripAsNil() throws {
        let clip = DJIClip(
            videoURL: URL(fileURLWithPath: "/x/DJI_0001.MP4"),
            index: 1,
            stem: "DJI_0001",
            duration: CMTime(value: 60, timescale: 1)
        )
        let decoded = try roundTrip(clip, as: DJIClip.self)
        XCTAssertNil(decoded.srtURL)
        XCTAssertNil(decoded.lrfURL)
        XCTAssertNil(decoded.streamInfo)
        XCTAssertNil(decoded.variantSuffix)
        XCTAssertNil(decoded.filenameTimestamp)
        XCTAssertFalse(decoded.hasSRT)
        XCTAssertEqual(decoded, clip)
    }

    func testDJIClipFactoryFromParsedFilename() throws {
        let parsed = try XCTUnwrap(DJIFilenameParser.parse("DJI_20230813102011_0008_D.MP4"))
        let clip = DJIClip.from(
            parsed: parsed,
            videoURL: URL(fileURLWithPath: "/x/DJI_20230813102011_0008_D.MP4"),
            duration: CMTime(value: 90_090, timescale: 3003)
        )
        XCTAssertEqual(clip.index, 8)
        XCTAssertEqual(clip.variantSuffix, "D")
        XCTAssertEqual(clip.stem, "DJI_20230813102011_0008_D")
        XCTAssertEqual(clip.filenameTimestamp?.year, 2023)
        XCTAssertEqual(clip.filenameTimestamp?.second, 11)
    }

    // MARK: - ConversionSettings

    func testConversionSettingsDefaults() {
        let s = ConversionSettings()
        XCTAssertEqual(s.outputContainer, .mp4)
        XCTAssertTrue(s.preserveTimecode)
        XCTAssertTrue(s.fixCreationDate)
        XCTAssertTrue(s.stitchSRT)
        XCTAssertFalse(s.reEncodeOnMismatch)
        XCTAssertFalse(s.deleteOriginalsAfterVerify)
        XCTAssertNil(s.outputDirectory)
    }

    func testConversionSettingsOutputDirectoryRoundTrip() throws {
        var s = ConversionSettings()
        s.outputDirectory = URL(fileURLWithPath: "/Users/me/Movies/Joined")
        s.outputFilename = "flight-01"
        s.outputContainer = .mov
        let decoded = try roundTrip(s, as: ConversionSettings.self)
        XCTAssertEqual(decoded.outputDirectory, URL(fileURLWithPath: "/Users/me/Movies/Joined"))
        XCTAssertEqual(decoded.outputFilename, "flight-01")
        XCTAssertEqual(decoded.outputContainer, .mov)
    }

    func testOutputContainerFileExtensions() {
        XCTAssertEqual(ConversionSettings.OutputContainer.mp4.fileExtension, "mp4")
        XCTAssertEqual(ConversionSettings.OutputContainer.mov.fileExtension, "mov")
    }

    // MARK: - RecordGroup

    func testRecordGroupTotalDurationSumsExactly() {
        let a = sampleClip(index: 1)   // 30000/1001
        let b = sampleClip(index: 2)   // 30000/1001
        let group = RecordGroup(clips: [a, b], groupIndex: 1)
        XCTAssertEqual(group.totalDuration, CMTimeAdd(a.duration, b.duration))
        XCTAssertEqual(group.clipCount, 2)
        XCTAssertEqual(group.videoURLs, [a.videoURL, b.videoURL])
    }

    func testRecordGroupIdAndVariantDerivedFromFirstClip() {
        let a = sampleClip(index: 1)
        let group = RecordGroup(clips: [a, sampleClip(index: 2)], groupIndex: 3)
        XCTAssertEqual(group.id, a.id)            // stable identity from first clip
        XCTAssertEqual(group.variantSuffix, "D")  // inherited from clips
        XCTAssertEqual(group.groupType, .split)
        XCTAssertEqual(group.groupTypeLabel, "Split")
    }

    func testRecordGroupSingle() {
        let group = RecordGroup(clips: [sampleClip()], groupIndex: 1, groupType: .single)
        XCTAssertEqual(group.groupType, .single)
        XCTAssertEqual(group.groupTypeLabel, "Single")
    }

    // MARK: - DJIFolder

    func testDJIFolderRoundTrip() throws {
        let folder = DJIFolder(
            rootURL: URL(fileURLWithPath: "/Volumes/SD/DCIM/100MEDIA"),
            clips: [sampleClip(index: 1), sampleClip(index: 2)],
            parseErrors: [ClipParseError(file: URL(fileURLWithPath: "/x/bad.MP4"), message: "probe failed")]
        )
        let decoded = try roundTrip(folder, as: DJIFolder.self)
        XCTAssertEqual(decoded.name, "100MEDIA")
        XCTAssertEqual(decoded.clipCount, 2)
        XCTAssertTrue(decoded.hasParseErrors)
        XCTAssertEqual(decoded.parseErrors.first?.fileName, "bad.MP4")
        XCTAssertEqual(decoded.clips, folder.clips)
    }

    // MARK: - JobStatus / VerificationStatus custom Codable

    func testJobStatusFailedRoundTrip() throws {
        for status in [JobStatus.pending, .preparing, .active, .completed, .failed("disk full"), .cancelled] {
            XCTAssertEqual(try roundTrip(status, as: JobStatus.self), status)
        }
    }

    func testVerificationStatusFailedRoundTrip() throws {
        for status in [VerificationStatus.unverified, .verifying, .verified, .failed("decode error at frame 12")] {
            XCTAssertEqual(try roundTrip(status, as: VerificationStatus.self), status)
        }
    }

    // MARK: - KEYSTONE: full ConversionJob round-trip

    func testConversionJobFullCodableRoundTrip() throws {
        var settings = ConversionSettings()
        settings.outputDirectory = URL(fileURLWithPath: "/Users/me/Movies")
        settings.outputFilename = "flight-08"
        settings.outputContainer = .mov

        var job = ConversionJob(
            folderName: "100MEDIA",
            sourceFolderURL: URL(fileURLWithPath: "/Volumes/SD/DCIM/100MEDIA"),
            clips: [sampleClip(index: 8), sampleClip(index: 9)],
            settings: settings,
            destinationURL: URL(fileURLWithPath: "/Users/me/Movies/flight-08.mov"),
            sourceBookmarkData: Data([0xDE, 0xAD, 0xBE, 0xEF]),
            outputBookmarkData: Data([0x01, 0x02, 0x03])
        )
        // Populate the mutable lifecycle/verification state, including the associated-value cases.
        job.status = .failed("ffmpeg exited 1")
        job.progress = 0.42
        job.startedAt = Date(timeIntervalSinceReferenceDate: 712_000_000)
        job.verificationStatus = .failed("frame mismatch")
        job.verificationResult = VerificationResult(
            fileURL: URL(fileURLWithPath: "/Users/me/Movies/flight-08.mov"),
            passed: false,
            mode: .full,
            duration: 3.5,
            framesDecoded: 100,
            totalFrames: 200,
            decodingSpeed: "45.2x",
            containerValid: true,
            errorMessage: "frame mismatch",
            verifiedAt: Date(timeIntervalSinceReferenceDate: 712_100_000)
        )
        job.verificationProgress = 0.5
        job.recordOutputURL(URL(fileURLWithPath: "/Users/me/Movies/flight-08.mov"))

        let decoded = try roundTrip(job, as: ConversionJob.self)

        XCTAssertEqual(decoded.id, job.id)
        XCTAssertEqual(decoded.folderName, "100MEDIA")
        XCTAssertEqual(decoded.sourceFolderURL, job.sourceFolderURL)
        XCTAssertEqual(decoded.destinationURL, job.destinationURL)
        XCTAssertEqual(decoded.clips, job.clips)                    // embedded DJIClip + streamInfo + CMTime
        XCTAssertEqual(decoded.settings.outputContainer, .mov)
        XCTAssertEqual(decoded.status, .failed("ffmpeg exited 1"))  // JobStatus.failed associated value
        XCTAssertEqual(decoded.progress, 0.42)
        XCTAssertEqual(decoded.startedAt, job.startedAt)
        XCTAssertEqual(decoded.sourceBookmarkData, Data([0xDE, 0xAD, 0xBE, 0xEF]))
        XCTAssertEqual(decoded.outputBookmarkData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(decoded.verificationStatus, .failed("frame mismatch"))
        XCTAssertEqual(decoded.verificationResult?.decodingSpeed, "45.2x")
        XCTAssertEqual(decoded.verificationResult?.passed, false)
        XCTAssertEqual(decoded.verificationProgress, 0.5)
        XCTAssertEqual(decoded.actualOutputURLs, job.actualOutputURLs)
        XCTAssertEqual(decoded.displayName, "flight-08.mov")
    }
}
