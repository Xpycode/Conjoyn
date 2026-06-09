import XCTest
@testable import DJIjoiner

/// Backpressure for task 2.8: 1904-epoch conversion and size-preserving mvhd/tkhd/mdhd patching,
/// validated by byte-level round trips (synthetic + real-muxer atoms). The risk register calls
/// out 1904-epoch correctness as the thing to de-risk with a round-trip test — this is it.
final class QuickTimeAtomWriterTests: XCTestCase {

    typealias Writer = QuickTimeAtomWriter

    // MARK: - 1904 epoch math

    func testEpochAnchors() {
        // 1904-01-01 is the QuickTime zero; 1970-01-01 is the offset.
        XCTAssertEqual(Writer.quickTimeSeconds(from: Date(timeIntervalSince1970: 0)), 2_082_844_800)
        let qtZero = Writer.date(fromQuickTimeSeconds: 0)
        XCTAssertEqual(qtZero.timeIntervalSince1970, -2_082_844_800, accuracy: 0.5)
    }

    func testEpochRoundTrip() {
        let date = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11-14, well within 32-bit range
        let qt = Writer.quickTimeSeconds(from: date)
        XCTAssertEqual(Writer.date(fromQuickTimeSeconds: qt).timeIntervalSince1970,
                       date.timeIntervalSince1970, accuracy: 0.5)
    }

    // MARK: - Synthetic moov round trips

    func testPatchesAllThreeHeadersVersion0() throws {
        var moov = makeMoov(version: 0, creation: 111, modification: 222)
        var data = Data(moov)
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let patched = try Writer.patch(&data, creationDate: date)
        XCTAssertEqual(patched, 3, "expected mvhd + tkhd + mdhd patched")

        // The mvhd creation date reads back as the date we wrote (to the second).
        moov = [UInt8](data)
        let readBack = try XCTUnwrap(Writer.readCreationDate(fromMoov: moov))
        XCTAssertEqual(readBack.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.5)
    }

    func testPatchVersion1SixtyFourBit() throws {
        var data = Data(makeMoov(version: 1, creation: 5, modification: 6))
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        XCTAssertEqual(try Writer.patch(&data, creationDate: date), 3)
        let readBack = try XCTUnwrap(Writer.readCreationDate(fromMoov: [UInt8](data)))
        XCTAssertEqual(readBack.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.5)
    }

    func testPatchIsSizePreserving() throws {
        var data = Data(makeMoov(version: 0, creation: 1, modification: 1))
        let before = data.count
        _ = try Writer.patch(&data, creationDate: Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(data.count, before, "patch must not change file size")
    }

    func testZeroCreationReadsAsNil() {
        // DJI often leaves mvhd creation_time at 0 — callers want nil so they can fall back.
        let moov = makeMoov(version: 0, creation: 0, modification: 0)
        XCTAssertNil(Writer.readCreationDate(fromMoov: moov))
    }

    func testFindsMoovInsideFullFileLayout() throws {
        // ftyp + moov + mdat, the usual top-level shape.
        var bytes = box("ftyp", Array("isom".utf8) + be32(0x200) + Array("isomiso2".utf8))
        bytes += makeMoov(version: 0, creation: 99, modification: 99)
        bytes += box("mdat", [UInt8](repeating: 0xAB, count: 32))

        var data = Data(bytes)
        XCTAssertEqual(try Writer.patch(&data, creationDate: Date(timeIntervalSince1970: 1_700_000_000)), 3)
    }

    func testMalformedThrows() {
        // A moov claiming a child box larger than itself must be rejected, not crash.
        var bytes = be32(8 + 16) + Array("moov".utf8)
        bytes += be32(9_000) + Array("mvhd".utf8) + [UInt8](repeating: 0, count: 8)
        var data = Data(bytes)
        XCTAssertThrowsError(try Writer.patch(&data, creationDate: Date()))
    }

    // MARK: - File round trip (FileHandle path)

    func testFileSetAndReadCreationDate() throws {
        var bytes = box("ftyp", Array("isom".utf8) + be32(0x200))
        bytes += makeMoov(version: 0, creation: 7, modification: 7)
        bytes += box("mdat", [UInt8](repeating: 0x11, count: 64))

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-atom-\(UUID().uuidString).mp4")
        try Data(bytes).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let count = try Writer.setCreationDate(date, inFileAt: url)
        XCTAssertEqual(count, 3)

        let readBack = try XCTUnwrap(try Writer.readCreationDate(fromFileAt: url))
        XCTAssertEqual(readBack.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.5)

        // File size unchanged on disk.
        let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int
        XCTAssertEqual(size, bytes.count)
    }

    // MARK: - Integration: patch a real ffmpeg-muxed file (skips without ffmpeg)

    func testRoundTripOnRealMuxedFile() throws {
        let resolver = BundledToolResolver.shared
        guard let ffmpeg = resolver.path(for: .ffmpeg) else {
            throw XCTSkip("No ffmpeg available (bundled or Homebrew)")
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-real-\(UUID().uuidString).mp4")
        defer { try? FileManager.default.removeItem(at: url) }

        let p = Process()
        p.executableURL = ffmpeg
        p.arguments = ["-y", "-f", "lavfi", "-i", "testsrc=duration=1:size=160x120:rate=30",
                       "-pix_fmt", "yuv420p", url.path]
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try p.run(); p.waitUntilExit()
        try XCTSkipIf(p.terminationStatus != 0, "ffmpeg could not generate a test clip")

        // Our parser must handle a real muxer's atom layout, not just hand-built ones.
        let date = Date(timeIntervalSince1970: 1_600_000_000)  // 2020-09-13
        let count = try Writer.setCreationDate(date, inFileAt: url)
        XCTAssertGreaterThanOrEqual(count, 1, "expected at least mvhd patched")
        let readBack = try XCTUnwrap(try Writer.readCreationDate(fromFileAt: url))
        XCTAssertEqual(readBack.timeIntervalSince1970, date.timeIntervalSince1970, accuracy: 0.5)
    }

    // MARK: - Atom builders

    /// A `moov` containing `mvhd` + `trak[ tkhd, mdia[ mdhd ] ]`, all with the same version.
    private func makeMoov(version: UInt8, creation: UInt64, modification: UInt64) -> [UInt8] {
        let mvhd = box("mvhd", fullHeader(version, creation, modification))
        let tkhd = box("tkhd", fullHeader(version, creation, modification))
        let mdhd = box("mdhd", fullHeader(version, creation, modification))
        let mdia = box("mdia", mdhd)
        let trak = box("trak", tkhd + mdia)
        return box("moov", mvhd + trak)
    }

    /// A full-box body: version, 3 flag bytes, creation, modification, then a little trailing
    /// payload (timescale + duration) so the box is realistically sized.
    private func fullHeader(_ version: UInt8, _ creation: UInt64, _ modification: UInt64) -> [UInt8] {
        var body: [UInt8] = [version, 0, 0, 0]
        if version == 1 {
            body += be64(creation) + be64(modification) + be32(1000) + be64(0)
        } else {
            body += be32(UInt32(truncatingIfNeeded: creation)) + be32(UInt32(truncatingIfNeeded: modification))
            body += be32(1000) + be32(0)   // timescale + duration
        }
        return body
    }

    private func box(_ type: String, _ payload: [UInt8]) -> [UInt8] {
        be32(UInt32(8 + payload.count)) + Array(type.utf8) + payload
    }
    private func be32(_ v: UInt32) -> [UInt8] {
        [UInt8((v >> 24) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)]
    }
    private func be64(_ v: UInt64) -> [UInt8] {
        (0..<8).map { UInt8((v >> (8 * (7 - $0))) & 0xFF) }
    }
}
