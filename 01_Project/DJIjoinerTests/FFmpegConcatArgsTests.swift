import XCTest
@testable import DJIjoiner

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
        assertSubsequence(["-map", "0:v", "-map", "0:a?", "-map", "-0:d"], in: args)
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
