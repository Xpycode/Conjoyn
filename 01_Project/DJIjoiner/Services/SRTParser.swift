import Foundation

// MARK: - SRT Telemetry Parser (Wave 3, task 3.1)

/// A tolerant parser for DJI sidecar `.SRT` telemetry files.
///
/// DJI has shipped at least three subtitle layouts over the years, and this parser handles all
/// of them by treating the SubRip *structure* (index → `start --> end` → payload block) as the
/// only thing it must understand, while leaving the telemetry payload **verbatim**:
///
/// - **Modern bracketed** (DJI Fly era — Mavic 3, Air 2S, Mini 3): a `<font>`-wrapped block
///   carrying `FrameCnt`/`DiffTime`, a wall-clock line, and space-separated `[key: value]`
///   pairs (`[iso: 100] [latitude: 40.1] …`).
/// - **`FrameCnt`/`DiffTime` + wall-clock** (Mavic 2 / Phantom 4 era): the same fields without
///   the `<font>` wrapper, the wall-clock often using comma sub-second groups
///   (`2017-09-08 14:38:30,234,567`).
/// - **Legacy `<font>` / `GPS()` / `HOME()`** (Phantom 3 / early Mavic): a dotted-date
///   wall-clock plus `GPS(lon,lat,sats)` / `HOME(lon,lat)` / `ISO:` / `Shutter:` tokens.
///
/// The offset stitcher (task 3.2) re-times and renumbers cues using **decoded segment duration**
/// from ffprobe — never cue arithmetic — so this parser deliberately does *not* interpret the
/// telemetry. It only surfaces enough structure (timecodes, original index, the embedded
/// wall-clock for continuity diagnostics) for the stitcher to splice segments, and preserves
/// each payload exactly so it can be re-emitted unchanged.
///
/// Tolerances: a leading UTF-8 BOM, CRLF / lone-CR line endings, blank lines between blocks,
/// `.` or `,` as the millisecond separator, and missing or non-numeric index lines (the
/// `-->` timecode line is the real anchor; the index is advisory and falls back to position).
/// Malformed blocks are skipped rather than throwing — a single corrupt cue never loses the file.
enum SRTParser {

    // MARK: - Output

    /// One SubRip cue: its timing, original index, the verbatim telemetry payload, and the
    /// wall-clock timestamp embedded in that payload (when one is present).
    struct Cue: Equatable {
        /// 1-based index as written in the file. Falls back to the cue's position in the file
        /// (also 1-based) when the index line is missing or non-numeric. The stitcher renumbers
        /// globally across segments, so this is informational.
        let index: Int
        /// Cue start, in milliseconds from the segment's own start (DJI cues are segment-relative).
        let startMilliseconds: Int
        /// Cue end, in milliseconds from the segment's own start.
        let endMilliseconds: Int
        /// The payload lines between the timecode line and the block separator, joined by `\n`
        /// with line endings normalized but content otherwise **unchanged**. Re-emit as-is.
        let payload: String
        /// Capture wall-clock parsed from the payload, if found. Time-zone-free (the file carries
        /// none) — returned as `DateComponents` down to `nanosecond` when sub-second digits exist.
        /// Used only for continuity diagnostics, never for offset math.
        let wallClock: DateComponents?
    }

    /// A parsed `.SRT` file: its cues in file order. Empty `cues` means nothing parseable was
    /// found (an empty or non-SRT file) — callers degrade gracefully, as a missing sidecar would.
    struct Document: Equatable {
        let cues: [Cue]
    }

    // MARK: - Entry points

    /// Parses raw `.SRT` text. Never throws — unparseable blocks are dropped.
    static func parse(_ text: String) -> Document {
        let normalized = normalizeLineEndings(stripBOM(text))
        let blocks = splitIntoBlocks(normalized)
        var cues: [Cue] = []
        cues.reserveCapacity(blocks.count)
        for (position, block) in blocks.enumerated() {
            if let cue = parseBlock(block, position: position) {
                cues.append(cue)
            }
        }
        return Document(cues: cues)
    }

    /// Parses `.SRT` bytes, tolerating a UTF-8 BOM and falling back to Latin-1 for the rare file
    /// with non-UTF-8 bytes (DJI telemetry is ASCII, but degrade rather than fail). Returns an
    /// empty document if the bytes can't be decoded at all.
    static func parse(data: Data) -> Document {
        let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .isoLatin1)
            ?? ""
        return parse(text)
    }

    /// Reads and parses an `.SRT` file. Throws only on a file-system read error; a readable but
    /// malformed file yields whatever cues are recoverable (possibly none).
    static func parse(contentsOf url: URL) throws -> Document {
        let data = try Data(contentsOf: url)
        return parse(data: data)
    }

    // MARK: - Serialization (round-trip support for the stitcher, task 3.2)

    /// Renders cues back to canonical SubRip text (`index`, `HH:MM:SS,mmm --> …`, payload, blank
    /// line). Indices are written verbatim from each `Cue.index`, so the stitcher renumbers by
    /// constructing cues with sequential indices before calling this. Payloads are emitted exactly.
    static func serialize(_ cues: [Cue]) -> String {
        var out = ""
        for cue in cues {
            out += "\(cue.index)\n"
            out += "\(formatTimecode(cue.startMilliseconds)) --> \(formatTimecode(cue.endMilliseconds))\n"
            out += cue.payload
            out += "\n\n"
        }
        return out
    }

    /// Formats a millisecond count as a SubRip timecode `HH:MM:SS,mmm`.
    static func formatTimecode(_ totalMilliseconds: Int) -> String {
        let ms = max(0, totalMilliseconds)
        let millis = ms % 1000
        let totalSeconds = ms / 1000
        let seconds = totalSeconds % 60
        let minutes = (totalSeconds / 60) % 60
        let hours = totalSeconds / 3600
        return String(format: "%02d:%02d:%02d,%03d", hours, minutes, seconds, millis)
    }

    // MARK: - Block parsing

    /// Parses one block. Anchors on the line containing `-->`; the index is taken from the last
    /// numeric line before it (or the file position), and the payload is everything after it.
    private static func parseBlock(_ block: String, position: Int) -> Cue? {
        let lines = block.components(separatedBy: "\n")
        guard let arrowLine = lines.firstIndex(where: { $0.contains("-->") }) else {
            return nil   // no timecode line → not a cue
        }
        guard let timing = parseTiming(lines[arrowLine]) else {
            return nil   // malformed timecode → skip
        }

        // Index: last numeric line above the timecode line; else 1-based file position.
        var index = position + 1
        if arrowLine > 0 {
            for line in lines[0..<arrowLine].reversed() {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if let parsed = Int(trimmed) {
                    index = parsed
                    break
                }
            }
        }

        // Payload: lines after the timecode, with trailing blank lines trimmed. Verbatim.
        let payloadLines = lines[(arrowLine + 1)...]
        let payload = trimTrailingBlankLines(Array(payloadLines)).joined(separator: "\n")

        return Cue(
            index: index,
            startMilliseconds: timing.start,
            endMilliseconds: timing.end,
            payload: payload,
            wallClock: parseWallClock(payload)
        )
    }

    // MARK: - Timecode line

    private static let timingRegex = try! NSRegularExpression(
        pattern: #"(\d+):(\d{1,2}):(\d{1,2})[.,](\d{1,3})\s*-->\s*(\d+):(\d{1,2}):(\d{1,2})[.,](\d{1,3})"#
    )

    private static func parseTiming(_ line: String) -> (start: Int, end: Int)? {
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let m = timingRegex.firstMatch(in: line, options: [], range: range) else { return nil }
        guard let start = milliseconds(line, m, base: 1),
              let end = milliseconds(line, m, base: 5) else { return nil }
        return (start, end)
    }

    /// Reads `HH`, `MM`, `SS`, `mmm` from four consecutive capture groups starting at `base`.
    private static func milliseconds(_ line: String, _ m: NSTextCheckingResult, base: Int) -> Int? {
        guard let h = Int(substring(line, m.range(at: base))),
              let min = Int(substring(line, m.range(at: base + 1))),
              let s = Int(substring(line, m.range(at: base + 2))) else { return nil }
        let fraction = substring(line, m.range(at: base + 3))
        let millis = paddedMilliseconds(fraction)
        return ((h * 60 + min) * 60 + s) * 1000 + millis
    }

    /// Normalizes a 1–3 digit sub-second string to milliseconds (`"5"` → 500, `"05"` → 50,
    /// `"050"` → 50, `"123"` → 123).
    private static func paddedMilliseconds(_ fraction: String) -> Int {
        let trimmed = String(fraction.prefix(3))
        guard let value = Int(trimmed) else { return 0 }
        switch trimmed.count {
        case 1: return value * 100
        case 2: return value * 10
        default: return value
        }
    }

    // MARK: - Wall-clock extraction

    /// Tolerant capture-date matcher. Accepts `-`, `.` or `/` date separators, a space or `T`
    /// between date and time, and an optional first sub-second group after `.` or `,`
    /// (`2023-08-13 10:20:11.234`, `2017-09-08 14:38:30,234,567`, `2016.08.15 14:38:50`).
    private static let wallClockRegex = try! NSRegularExpression(
        pattern: #"(\d{4})[-./](\d{1,2})[-./](\d{1,2})[ T](\d{1,2}):(\d{1,2}):(\d{1,2})(?:[.,](\d{1,3}))?"#
    )

    private static func parseWallClock(_ payload: String) -> DateComponents? {
        let range = NSRange(payload.startIndex..<payload.endIndex, in: payload)
        guard let m = wallClockRegex.firstMatch(in: payload, options: [], range: range) else {
            return nil
        }
        func field(_ i: Int) -> Int? { Int(substring(payload, m.range(at: i))) }
        var components = DateComponents()
        components.year   = field(1)
        components.month  = field(2)
        components.day    = field(3)
        components.hour   = field(4)
        components.minute = field(5)
        components.second = field(6)
        let fraction = substring(payload, m.range(at: 7))
        if !fraction.isEmpty {
            components.nanosecond = paddedMilliseconds(fraction) * 1_000_000
        }
        return components
    }

    // MARK: - Text helpers

    private static func stripBOM(_ text: String) -> String {
        text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
    }

    private static func normalizeLineEndings(_ text: String) -> String {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
    }

    /// Splits on one-or-more blank lines into non-empty blocks, ignoring surrounding whitespace.
    private static func splitIntoBlocks(_ text: String) -> [String] {
        text.components(separatedBy: blockSeparator)
            .map { $0.trimmingCharacters(in: .newlines) }
            .filter { !$0.isEmpty }
    }

    private static let blockSeparator = try! NSRegularExpression(pattern: #"\n[ \t]*\n"#)

    private static func trimTrailingBlankLines(_ lines: [String]) -> [String] {
        var result = lines
        while let last = result.last, last.trimmingCharacters(in: .whitespaces).isEmpty {
            result.removeLast()
        }
        return result
    }

    private static func substring(_ string: String, _ nsRange: NSRange) -> String {
        guard let range = Range(nsRange, in: string) else { return "" }
        return String(string[range])
    }
}

// MARK: - String split on a regex separator

private extension String {
    /// Splits the string on every match of `separator` (used for blank-line block separation).
    func components(separatedBy separator: NSRegularExpression) -> [String] {
        let range = NSRange(startIndex..<endIndex, in: self)
        let matches = separator.matches(in: self, options: [], range: range)
        guard !matches.isEmpty else { return [self] }
        var pieces: [String] = []
        var cursor = startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: self) else { continue }
            pieces.append(String(self[cursor..<matchRange.lowerBound]))
            cursor = matchRange.upperBound
        }
        pieces.append(String(self[cursor...]))
        return pieces
    }
}
