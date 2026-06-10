import XCTest
@testable import Conjoyn

final class BundledToolResolverTests: XCTestCase {

    // task 1.4 backpressure: resolves both tool URLs.
    // In the test runner there is no bundled Helpers/, so this exercises the Homebrew dev
    // fallback. Skips gracefully if Homebrew FFmpeg isn't installed (e.g. clean CI).
    func testResolvesFFmpegAndFFprobe() throws {
        let resolver = BundledToolResolver.shared

        let homebrewPresent = FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/ffmpeg")
            || FileManager.default.isExecutableFile(atPath: "/usr/local/bin/ffmpeg")
        try XCTSkipUnless(homebrewPresent, "No bundled or Homebrew FFmpeg available in test environment")

        let ffmpeg = resolver.path(for: .ffmpeg)
        let ffprobe = resolver.path(for: .ffprobe)
        XCTAssertNotNil(ffmpeg, "Expected to resolve ffmpeg")
        XCTAssertNotNil(ffprobe, "Expected to resolve ffprobe")
        XCTAssertTrue(resolver.isAvailable(.ffmpeg))
        XCTAssertTrue(resolver.allRequiredToolsAvailable)
    }

    func testBundledToolCasesAreFFmpegAndFFprobeOnly() {
        // BMX tools dropped for DJI — only the two FFmpeg tools remain.
        XCTAssertEqual(Set(BundledTool.allCases.map(\.rawValue)), ["ffmpeg", "ffprobe"])
    }
}
