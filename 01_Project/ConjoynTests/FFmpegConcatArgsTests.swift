import XCTest
@testable import Conjoyn

/// Backpressure for task 2.5: the pure concat list + argument builders.
final class FFmpegConcatArgsTests: XCTestCase {

    private let seg1 = URL(fileURLWithPath: "/Volumes/CARD/DCIM/100MEDIA/DJI_0001.MP4")
    private let seg2 = URL(fileURLWithPath: "/Volumes/CARD/DCIM/100MEDIA/DJI_0002.MP4")
    private let listURL = URL(fileURLWithPath: "/tmp/list.txt")
    private let outURL = URL(fileURLWithPath: "/Users/me/Movies/joined.mp4")

    // MARK: - Concat list

    func testConcatListBody() {
        let body = FFmpegWrapper.buildConcatList(for: [seg1, seg2])
        XCTAssertEqual(
            body,
            "file '/Volumes/CARD/DCIM/100MEDIA/DJI_0001.MP4'\n" +
            "file '/Volumes/CARD/DCIM/100MEDIA/DJI_0002.MP4'\n"
        )
    }

    func testConcatListEscapesSingleQuotes() {
        let tricky = URL(fileURLWithPath: "/tmp/Bob's Drone/DJI_0001.MP4")
        let body = FFmpegWrapper.buildConcatList(for: [tricky])
        XCTAssertEqual(body, "file '/tmp/Bob'\\''s Drone/DJI_0001.MP4'\n")
    }

    // MARK: - Argument vector

    func testMergeArgumentsCoreShape() {
        let args = FFmpegWrapper.buildMergeArguments(listFileURL: listURL, outputURL: outURL)

        // Lossless concat-demuxer essentials.
        assertSubsequence(["-f", "concat", "-safe", "0", "-i", "/tmp/list.txt"], in: args)
        // Primary video only (`0:v:0`) — DJI's embedded mjpeg preview track (v:1) must not be carried.
        assertSubsequence(["-map", "0:v:0", "-map", "0:a?", "-map", "-0:d"], in: args)
        assertSubsequence(["-c", "copy"], in: args)
        assertSubsequence(["-fflags", "+genpts"], in: args)
        assertSubsequence(["-movflags", "+faststart"], in: args)

        // Output is overwritten and comes last.
        XCTAssertEqual(args.last, "/Users/me/Movies/joined.mp4")
        XCTAssertEqual(args[args.count - 2], "-y")
    }

    func testMergeArgumentsOmitsMetadataWhenAbsent() {
        let args = FFmpegWrapper.buildMergeArguments(listFileURL: listURL, outputURL: outURL)
        XCTAssertFalse(args.contains("-timecode"))
        XCTAssertFalse(args.contains { $0.hasPrefix("creation_time=") })
    }

    func testMergeArgumentsIncludesMetadataWhenPresent() {
        let meta = FFmpegWrapper.JoinMetadata(
            creationTime: "2023-08-13T10:20:11.000000Z",
            timecode: "01:02:03:04"
        )
        let args = FFmpegWrapper.buildMergeArguments(listFileURL: listURL, outputURL: outURL, metadata: meta)

        assertSubsequence(["-metadata", "creation_time=2023-08-13T10:20:11.000000Z"], in: args)
        assertSubsequence(["-timecode", "01:02:03:04"], in: args)
        // Metadata must precede the trailing -y/output pair.
        let yIndex = args.firstIndex(of: "-y")!
        let tcIndex = args.firstIndex(of: "-timecode")!
        XCTAssertLessThan(tcIndex, yIndex)
    }

    // MARK: - Argument vector (gpmd / GoPro shape, task G4.1)

    func testMergeArgumentsNilGpmdIndexIsByteIdenticalToDJIShape() {
        let args = FFmpegWrapper.buildMergeArguments(listFileURL: listURL, outputURL: outURL, gpmdStreamIndex: nil)
        XCTAssertEqual(args, [
            "-f", "concat",
            "-safe", "0",
            "-i", "/tmp/list.txt",
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "-0:d",
            "-c", "copy",
            "-fflags", "+genpts",
            "-movflags", "+faststart",
            "-y", "/Users/me/Movies/joined.mp4",
        ])
    }

    func testMergeArgumentsGoProShapeNoMetadataIndex3() {
        let args = FFmpegWrapper.buildMergeArguments(
            listFileURL: listURL, outputURL: outURL, gpmdStreamIndex: 3
        )
        XCTAssertEqual(args, [
            "-f", "concat",
            "-safe", "0",
            "-i", "/tmp/list.txt",
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "0:3",
            "-c", "copy",
            "-copy_unknown",
            "-fflags", "+genpts",
            "-movflags", "+faststart",
            "-y", "/Users/me/Movies/joined.mp4",
        ])
    }

    func testMergeArgumentsGoProShapeIndex2() {
        let args = FFmpegWrapper.buildMergeArguments(
            listFileURL: listURL, outputURL: outURL, gpmdStreamIndex: 2
        )
        XCTAssertEqual(args, [
            "-f", "concat",
            "-safe", "0",
            "-i", "/tmp/list.txt",
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "0:2",
            "-c", "copy",
            "-copy_unknown",
            "-fflags", "+genpts",
            "-movflags", "+faststart",
            "-y", "/Users/me/Movies/joined.mp4",
        ])
    }

    func testMergeArgumentsGoProShapeWithMetadataAndTimecode() {
        let meta = FFmpegWrapper.JoinMetadata(
            creationTime: "2023-08-13T10:20:11.000000Z",
            timecode: "01:02:03:04"
        )
        let args = FFmpegWrapper.buildMergeArguments(
            listFileURL: listURL, outputURL: outURL, metadata: meta, gpmdStreamIndex: 3
        )
        XCTAssertEqual(args, [
            "-f", "concat",
            "-safe", "0",
            "-i", "/tmp/list.txt",
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "0:3",
            "-c", "copy",
            "-copy_unknown",
            "-fflags", "+genpts",
            "-movflags", "+faststart",
            "-metadata", "creation_time=2023-08-13T10:20:11.000000Z",
            "-timecode", "01:02:03:04",
            "-y", "/Users/me/Movies/joined.mp4",
        ])
    }

    // MARK: - gpmd index resolution + layout-mismatch refusal (task G4.2)

    private let refVideo = StreamParameterGuard.VideoStreamParams(
        codecName: "h264", width: 1920, height: 1080, pixelFormat: "yuv420p",
        avgFrameRate: "30/1", timeBase: "1/30000"
    )

    private func streamInfo(dataStreamIndex: Int?) -> StreamParameterGuard.SegmentStreamInfo {
        .init(
            video: refVideo,
            audio: nil,
            dataStreamIndex: dataStreamIndex,
            dataCodecTag: dataStreamIndex != nil ? "gpmd" : nil
        )
    }

    func testResolveGpmdStreamIndexReturnsSegment1sIndexWhenAllAgree() throws {
        let infos = [streamInfo(dataStreamIndex: 3), streamInfo(dataStreamIndex: 3), streamInfo(dataStreamIndex: 3)]
        let names = ["GX010001.MP4", "GX010002.MP4", "GX010003.MP4"]

        let resolved = try FFmpegWrapper.resolveGpmdStreamIndex(for: infos, segmentNames: names)
        XCTAssertEqual(resolved, 3)
    }

    func testResolveGpmdStreamIndexIsPositionalNotUniformAcrossSegments() throws {
        // The gpmd index need not be identical across segments (audio presence can shift it) —
        // only *presence* is compared. Segment 1's own index is what's returned.
        let infos = [streamInfo(dataStreamIndex: 3), streamInfo(dataStreamIndex: 2)]
        let names = ["GX010001.MP4", "GX010002.MP4"]

        let resolved = try FFmpegWrapper.resolveGpmdStreamIndex(for: infos, segmentNames: names)
        XCTAssertEqual(resolved, 3)
    }

    func testResolveGpmdStreamIndexNilWhenNoSegmentHasGpmd() throws {
        let infos = [streamInfo(dataStreamIndex: nil), streamInfo(dataStreamIndex: nil)]
        let names = ["a.MP4", "b.MP4"]

        let resolved = try FFmpegWrapper.resolveGpmdStreamIndex(for: infos, segmentNames: names)
        XCTAssertNil(resolved)
    }

    func testResolveGpmdStreamIndexSingleSegmentReturnsItsOwnIndex() throws {
        let resolved = try FFmpegWrapper.resolveGpmdStreamIndex(
            for: [streamInfo(dataStreamIndex: 2)], segmentNames: ["GX010001.MP4"]
        )
        XCTAssertEqual(resolved, 2)
    }

    func testResolveGpmdStreamIndexThrowsAndNamesSegmentMissingGpmd() {
        // Segment 1 has telemetry; segment 2 (named) does not — refused before ffmpeg runs.
        let infos = [streamInfo(dataStreamIndex: 3), streamInfo(dataStreamIndex: nil)]
        let names = ["GX010001.MP4", "GX010002.MP4"]

        XCTAssertThrowsError(try FFmpegWrapper.resolveGpmdStreamIndex(for: infos, segmentNames: names)) { error in
            guard case let FFmpegWrapper.FFmpegError.dataStreamLayoutMismatch(reason) = error else {
                return XCTFail("expected .dataStreamLayoutMismatch, got \(error)")
            }
            XCTAssertTrue(reason.contains("GX010002.MP4"), "reason should name the offending segment: \(reason)")
            XCTAssertTrue(reason.contains("segment 2"), "reason should cite the segment number: \(reason)")
        }
    }

    func testResolveGpmdStreamIndexThrowsAndNamesSegmentWithUnexpectedGpmd() {
        // Reverse direction: segment 1 has no telemetry, segment 3 (named) does.
        let infos = [
            streamInfo(dataStreamIndex: nil),
            streamInfo(dataStreamIndex: nil),
            streamInfo(dataStreamIndex: 3),
        ]
        let names = ["GX010001.MP4", "GX010002.MP4", "GX010003.MP4"]

        XCTAssertThrowsError(try FFmpegWrapper.resolveGpmdStreamIndex(for: infos, segmentNames: names)) { error in
            guard case let FFmpegWrapper.FFmpegError.dataStreamLayoutMismatch(reason) = error else {
                return XCTFail("expected .dataStreamLayoutMismatch, got \(error)")
            }
            XCTAssertTrue(reason.contains("GX010003.MP4"), "reason should name the offending segment: \(reason)")
            XCTAssertTrue(reason.contains("segment 3"), "reason should cite the segment number: \(reason)")
        }
    }

    // MARK: - Helpers

    /// Asserts that `needle` appears as a contiguous run inside `haystack`.
    private func assertSubsequence(_ needle: [String], in haystack: [String],
                                   file: StaticString = #filePath, line: UInt = #line) {
        guard !needle.isEmpty, haystack.count >= needle.count else {
            return XCTFail("haystack too short for \(needle)", file: file, line: line)
        }
        for start in 0...(haystack.count - needle.count) where Array(haystack[start..<start + needle.count]) == needle {
            return
        }
        XCTFail("expected contiguous \(needle) inside \(haystack)", file: file, line: line)
    }
}
