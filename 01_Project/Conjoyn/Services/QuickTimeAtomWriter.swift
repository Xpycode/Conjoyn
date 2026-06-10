import Foundation

// MARK: - Native QuickTime/MP4 Date Atom Writer (Wave 2, task 2.8)

/// Patches the creation/modification timestamps inside an ISO-BMFF (MP4/MOV) file's movie,
/// track, and media headers — `mvhd`, `tkhd`, `mdhd` — without re-muxing. DJI frequently writes
/// a wrong or time-zone-shifted `creation_time` (the well-documented 1951/TZ bug), and after a
/// concat join we want the output to carry the authoritative date from segment 1. FFmpeg's
/// `-metadata creation_time` (task 2.5) covers the common case during the join; this writer is
/// the native, re-mux-free path for correcting an existing file.
///
/// **Why native, not exiftool:** the project ships no exiftool; this is a focused, dependency-free
/// patch of fixed-size header fields. It is deliberately **size-preserving** — it only overwrites
/// existing 32-/64-bit time fields, so no sample-offset (`stco`/`co64`) fixups are needed and the
/// operation is safe on multi-gigabyte files (only the small `moov` atom is read into memory).
///
/// **Scope / follow-up:** inserting the Apple `Keys` atom
/// `com.apple.quicktime.creationdate` (what Finder's Get Info and the QuickTime Inspector read,
/// and what `AVAsset.creationDate` surfaces) changes file size and requires rewriting chunk
/// offsets — and with `+faststart` the `moov` precedes `mdat`, so every offset shifts. That is
/// intentionally **not** done here; it needs validation against real footage (Wave 6, task 6.3).
/// This writer correctly sets the header times that ffprobe reports as `creation_time` and that
/// downstream tooling reads.
enum QuickTimeAtomWriter {

    /// Seconds between the QuickTime epoch (1904-01-01 00:00:00 UTC) and the Unix epoch.
    static let epoch1904Offset: Int64 = 2_082_844_800

    enum AtomError: LocalizedError {
        case noMovieHeader
        case malformed(String)
        case io(String)

        var errorDescription: String? {
            switch self {
            case .noMovieHeader:    return "No 'moov' movie header found — not a valid MP4/MOV"
            case .malformed(let m): return "Malformed atom structure: \(m)"
            case .io(let m):        return "File I/O error: \(m)"
            }
        }
    }

    // MARK: - 1904 epoch conversion

    /// Converts a `Date` to seconds since the 1904 QuickTime epoch (clamped at 0).
    static func quickTimeSeconds(from date: Date) -> UInt64 {
        let seconds = Int64(date.timeIntervalSince1970.rounded()) + epoch1904Offset
        return seconds < 0 ? 0 : UInt64(seconds)
    }

    /// Converts seconds since the 1904 QuickTime epoch back to a `Date`.
    static func date(fromQuickTimeSeconds seconds: UInt64) -> Date {
        Date(timeIntervalSince1970: Double(Int64(bitPattern: seconds) - epoch1904Offset))
    }

    // MARK: - File API

    /// Sets the creation (and modification) date on `mvhd`/`tkhd`/`mdhd` of the file in place.
    /// Reads only the `moov` atom into memory, so it is safe on large files.
    /// - Returns: the number of header atoms patched (always ≥ 1 on success).
    @discardableResult
    static func setCreationDate(_ date: Date, inFileAt url: URL) throws -> Int {
        let qt = quickTimeSeconds(from: date)

        let handle: FileHandle
        do { handle = try FileHandle(forUpdating: url) }
        catch { throw AtomError.io(error.localizedDescription) }
        defer { try? handle.close() }

        let fileSize = try seekToEnd(handle)
        guard let moov = try locateTopLevelBox(type: "moov", handle: handle, fileSize: fileSize) else {
            throw AtomError.noMovieHeader
        }

        // Read the whole moov box (header + content) — small even for hours of footage.
        try seek(handle, to: moov.start)
        guard let moovData = try read(handle, count: moov.length), moovData.count == moov.length else {
            throw AtomError.io("could not read moov atom")
        }

        var bytes = [UInt8](moovData)
        let sites = try collectDateSites(in: bytes, range: 0..<bytes.count)
        guard !sites.isEmpty else {
            throw AtomError.malformed("no mvhd/tkhd/mdhd inside moov")
        }
        for site in sites { write(qt, at: site, into: &bytes) }

        try seek(handle, to: moov.start)
        do { try writeData(handle, Data(bytes)) }
        catch { throw AtomError.io(error.localizedDescription) }

        return sites.count
    }

    /// Reads the movie creation date from the file's `mvhd`. Returns `nil` if the stored time is
    /// 0 (DJI often leaves it unset) so callers can fall back to other signals.
    static func readCreationDate(fromFileAt url: URL) throws -> Date? {
        let handle: FileHandle
        do { handle = try FileHandle(forReadingFrom: url) }
        catch { throw AtomError.io(error.localizedDescription) }
        defer { try? handle.close() }

        let fileSize = try seekToEnd(handle)
        guard let moov = try locateTopLevelBox(type: "moov", handle: handle, fileSize: fileSize) else {
            throw AtomError.noMovieHeader
        }
        try seek(handle, to: moov.start)
        guard let moovData = try read(handle, count: moov.length) else { return nil }
        return readCreationDate(fromMoov: [UInt8](moovData))
    }

    // MARK: - In-memory API (pure, unit-testable)

    /// Patches `mvhd`/`tkhd`/`mdhd` dates in an in-memory ISO-BMFF buffer. Used by tests and by
    /// callers that already hold the bytes. Returns the number of atoms patched.
    @discardableResult
    static func patch(_ data: inout Data, creationDate: Date) throws -> Int {
        let qt = quickTimeSeconds(from: creationDate)
        var bytes = [UInt8](data)
        let sites = try collectDateSites(in: bytes, range: 0..<bytes.count)
        for site in sites { write(qt, at: site, into: &bytes) }
        data = Data(bytes)
        return sites.count
    }

    /// Reads the `mvhd` creation date from an in-memory `moov` buffer (the bytes of the moov box,
    /// including its header). Returns `nil` if absent or zero.
    static func readCreationDate(fromMoov bytes: [UInt8]) -> Date? {
        guard let sites = try? collectDateSites(in: bytes, range: 0..<bytes.count),
              let mvhd = sites.first(where: { $0.kind == .mvhd }) else {
            return nil
        }
        let seconds = mvhd.is64
            ? readUInt64(bytes, at: mvhd.creationOffset)
            : UInt64(readUInt32(bytes, at: mvhd.creationOffset))
        return seconds == 0 ? nil : date(fromQuickTimeSeconds: seconds)
    }

    // MARK: - Atom walking

    private enum HeaderKind { case mvhd, tkhd, mdhd }

    /// Absolute byte offsets of a full-box's time fields within the buffer.
    private struct DateSite {
        let kind: HeaderKind
        let creationOffset: Int
        let modificationOffset: Int
        let is64: Bool   // version 1 → 64-bit times; version 0 → 32-bit
    }

    /// Container boxes whose contents we descend into to reach the header atoms.
    private static let containerTypes: Set<String> = ["moov", "trak", "mdia"]
    /// Leaf full-boxes that carry creation/modification times in the same layout.
    private static let timeHeaderTypes: [String: HeaderKind] = [
        "mvhd": .mvhd, "tkhd": .tkhd, "mdhd": .mdhd,
    ]

    /// Recursively collects the time-field sites of every `mvhd`/`tkhd`/`mdhd` within `range`.
    private static func collectDateSites(in bytes: [UInt8], range: Range<Int>) throws -> [DateSite] {
        var sites: [DateSite] = []
        var cursor = range.lowerBound

        while cursor + 8 <= range.upperBound {
            let size32 = Int(readUInt32(bytes, at: cursor))
            let type = fourCC(bytes, at: cursor + 4)

            var headerSize = 8
            var boxSize: Int
            switch size32 {
            case 1:  // 64-bit size in the 8 bytes after the type
                guard cursor + 16 <= range.upperBound else {
                    throw AtomError.malformed("truncated 64-bit box header for '\(type)'")
                }
                boxSize = Int(readUInt64(bytes, at: cursor + 8))
                headerSize = 16
            case 0:  // box extends to the end of the enclosing range
                boxSize = range.upperBound - cursor
            default:
                boxSize = size32
            }

            guard boxSize >= headerSize, cursor + boxSize <= range.upperBound else {
                throw AtomError.malformed("box '\(type)' size \(boxSize) overruns its parent")
            }

            let contentStart = cursor + headerSize
            if let kind = timeHeaderTypes[type] {
                // Full box: [version(1)][flags(3)][creation][modification]…
                guard contentStart + 4 <= cursor + boxSize else {
                    throw AtomError.malformed("'\(type)' too small for version/flags")
                }
                let version = bytes[contentStart]
                let is64 = (version == 1)
                let timeWidth = is64 ? 8 : 4
                let creationOffset = contentStart + 4
                let modificationOffset = creationOffset + timeWidth
                guard modificationOffset + timeWidth <= cursor + boxSize else {
                    throw AtomError.malformed("'\(type)' too small for its time fields")
                }
                sites.append(DateSite(kind: kind,
                                      creationOffset: creationOffset,
                                      modificationOffset: modificationOffset,
                                      is64: is64))
            } else if containerTypes.contains(type) {
                sites += try collectDateSites(in: bytes, range: contentStart..<(cursor + boxSize))
            }

            cursor += boxSize
        }
        return sites
    }

    /// Writes `seconds` to both the creation and modification fields of a site (big-endian).
    private static func write(_ seconds: UInt64, at site: DateSite, into bytes: inout [UInt8]) {
        if site.is64 {
            writeUInt64(seconds, into: &bytes, at: site.creationOffset)
            writeUInt64(seconds, into: &bytes, at: site.modificationOffset)
        } else {
            let truncated = UInt32(truncatingIfNeeded: seconds)
            writeUInt32(truncated, into: &bytes, at: site.creationOffset)
            writeUInt32(truncated, into: &bytes, at: site.modificationOffset)
        }
    }

    // MARK: - Top-level box location (FileHandle)

    private struct TopLevelBox { let start: Int; let length: Int }

    /// Scans top-level boxes via the file handle (reading only 8/16-byte headers + seeking) and
    /// returns the first box of `type`. Avoids loading anything but headers into memory.
    private static func locateTopLevelBox(type wanted: String, handle: FileHandle, fileSize: Int) throws -> TopLevelBox? {
        var cursor = 0
        while cursor + 8 <= fileSize {
            try seek(handle, to: cursor)
            guard let header = try read(handle, count: 8), header.count == 8 else { break }
            let h = [UInt8](header)
            let size32 = Int(readUInt32(h, at: 0))
            let type = fourCC(h, at: 4)

            var boxSize: Int
            switch size32 {
            case 1:
                guard let ext = try read(handle, count: 8), ext.count == 8 else {
                    throw AtomError.malformed("truncated 64-bit top-level box header")
                }
                boxSize = Int(readUInt64([UInt8](ext), at: 0))
            case 0:
                boxSize = fileSize - cursor
            default:
                boxSize = size32
            }
            guard boxSize >= 8, cursor + boxSize <= fileSize else {
                throw AtomError.malformed("top-level box '\(type)' size \(boxSize) overruns file")
            }
            if type == wanted { return TopLevelBox(start: cursor, length: boxSize) }
            cursor += boxSize
        }
        return nil
    }

    // MARK: - Byte helpers (big-endian)

    private static func readUInt32(_ b: [UInt8], at i: Int) -> UInt32 {
        (UInt32(b[i]) << 24) | (UInt32(b[i + 1]) << 16) | (UInt32(b[i + 2]) << 8) | UInt32(b[i + 3])
    }
    private static func readUInt64(_ b: [UInt8], at i: Int) -> UInt64 {
        var v: UInt64 = 0
        for k in 0..<8 { v = (v << 8) | UInt64(b[i + k]) }
        return v
    }
    private static func writeUInt32(_ v: UInt32, into b: inout [UInt8], at i: Int) {
        b[i]     = UInt8((v >> 24) & 0xFF)
        b[i + 1] = UInt8((v >> 16) & 0xFF)
        b[i + 2] = UInt8((v >> 8) & 0xFF)
        b[i + 3] = UInt8(v & 0xFF)
    }
    private static func writeUInt64(_ v: UInt64, into b: inout [UInt8], at i: Int) {
        for k in 0..<8 { b[i + k] = UInt8((v >> (8 * (7 - k))) & 0xFF) }
    }
    private static func fourCC(_ b: [UInt8], at i: Int) -> String {
        String(bytes: b[i..<i + 4], encoding: .ascii) ?? ""
    }

    // MARK: - FileHandle shims (typed-throws-free, pre-macOS-13 friendly)

    private static func seekToEnd(_ h: FileHandle) throws -> Int {
        do { return Int(try h.seekToEnd()) }
        catch { throw AtomError.io(error.localizedDescription) }
    }
    private static func seek(_ h: FileHandle, to offset: Int) throws {
        do { try h.seek(toOffset: UInt64(offset)) }
        catch { throw AtomError.io(error.localizedDescription) }
    }
    private static func read(_ h: FileHandle, count: Int) throws -> Data? {
        do { return try h.read(upToCount: count) }
        catch { throw AtomError.io(error.localizedDescription) }
    }
    private static func writeData(_ h: FileHandle, _ data: Data) throws {
        do { try h.write(contentsOf: data) }
        catch { throw AtomError.io(error.localizedDescription) }
    }
}
