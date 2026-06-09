import Foundation

// MARK: - DJI Filename Parser (Wave 2, task 2.1)

/// Parses DJI media filenames into structured fields.
///
/// DJI uses two naming schemes:
/// - **Legacy** — `DJI_NNNN.MP4`: a four-digit sequential index that resets to `0001` when the
///   card is formatted in-drone and rolls a new `DCIM` media folder after 999 files
///   (e.g. `DJI_0001.MP4`).
/// - **Timestamped** — `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>.MP4`: newer models (Mavic 3 Pro and
///   later) embed a capture date-time and a trailing lens/camera **variant suffix**
///   (e.g. `DJI_20230813102011_0008_D.MP4`).
///
/// Filenames are a *corroborating* grouping signal only — index order to break ties within a
/// confirmed group, and the variant suffix as a hard no-merge boundary — never the sole key
/// (numbering collides across drones and resets on format). This parser only *extracts* fields;
/// all grouping decisions live in the grouping engine (task 2.4).
enum DJIFilenameParser {

    // MARK: - Output

    /// The kind of file, inferred from its extension.
    enum MediaKind: Equatable {
        case video      // .MP4 / .MOV — the joinable essence
        case telemetry  // .SRT sidecar (per-segment flight telemetry)
        case proxy      // .LRF low-resolution proxy (excluded from the join)
        case other      // anything else (e.g. .JPG, .DNG)
    }

    /// Which naming scheme produced the name.
    enum Scheme: Equatable {
        case legacy        // DJI_NNNN
        case timestamped   // DJI_YYYYMMDDHHMMSS_NNNN_<suffix>
    }

    /// Structured view of a parsed DJI filename. Extension-independent fields (`index`,
    /// `timestamp`, `variantSuffix`, `stem`) are identical for a video and its `.SRT`/`.LRF`
    /// sidecars, so they pair by `stem`.
    struct Parsed: Equatable {
        /// The original filename as given (including extension).
        let original: String
        /// Detected naming scheme.
        let scheme: Scheme
        /// Sequential capture index (the `NNNN` field). Present in both schemes.
        let index: Int
        /// Capture date-time from the timestamped scheme; `nil` for legacy names. Returned as
        /// `DateComponents` (year…second) because the filename carries no time zone — interpret
        /// against the segment's metadata, don't assume UTC/local here.
        let timestamp: DateComponents?
        /// Trailing variant suffix, uppercased (e.g. `"D"`, `"W"`, `"Z"`, `"T"`); `nil` for
        /// legacy names. The grouping engine must **never** merge clips across differing suffixes.
        let variantSuffix: String?
        /// File kind, from the extension.
        let mediaKind: MediaKind
        /// The filename minus its extension (e.g. `DJI_0001`, `DJI_20230813102011_0008_D`).
        /// A video and its sidecars share this — use it to pair them.
        let stem: String
    }

    // MARK: - Known variant suffixes (reference, not exhaustive)

    /// Documented camera/lens variant suffixes. `D` is the normal single-camera video; the rest
    /// denote distinct lenses or sensors that must never be merged together. Unknown future
    /// suffixes are still parsed (kept verbatim in `variantSuffix`) and treated as their own
    /// bucket by the grouping engine, so this set is informational only.
    static let knownVariantSuffixes: Set<String> = ["D", "W", "Z", "T", "V", "S"]

    // MARK: - Parsing

    private static let timestampedRegex = try! NSRegularExpression(
        pattern: #"^DJI_(\d{14})_(\d{4})_([A-Za-z0-9]+)$"#,
        options: [.caseInsensitive]
    )
    private static let legacyRegex = try! NSRegularExpression(
        pattern: #"^DJI_(\d{4})$"#,
        options: [.caseInsensitive]
    )

    /// Parses a filename (with or without a path). Returns `nil` for names that don't match
    /// either DJI scheme.
    static func parse(_ filename: String) -> Parsed? {
        // Work from the last path component so callers can pass a full path or a bare name.
        let name = (filename as NSString).lastPathComponent
        let stem = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension.lowercased()
        let mediaKind = kind(forExtension: ext)
        let range = NSRange(stem.startIndex..<stem.endIndex, in: stem)

        // Timestamped scheme takes priority (it's strictly more specific).
        if let m = timestampedRegex.firstMatch(in: stem, range: range) {
            let digits = substring(stem, m.range(at: 1))   // 14-digit timestamp
            let indexStr = substring(stem, m.range(at: 2))  // NNNN
            let suffix = substring(stem, m.range(at: 3)).uppercased()
            guard let index = Int(indexStr) else { return nil }
            return Parsed(
                original: name,
                scheme: .timestamped,
                index: index,
                timestamp: timestampComponents(from: digits),
                variantSuffix: suffix,
                mediaKind: mediaKind,
                stem: stem
            )
        }

        if let m = legacyRegex.firstMatch(in: stem, range: range) {
            let indexStr = substring(stem, m.range(at: 1))
            guard let index = Int(indexStr) else { return nil }
            return Parsed(
                original: name,
                scheme: .legacy,
                index: index,
                timestamp: nil,
                variantSuffix: nil,
                mediaKind: mediaKind,
                stem: stem
            )
        }

        return nil
    }

    /// Convenience overload for `URL` inputs.
    static func parse(_ url: URL) -> Parsed? {
        parse(url.lastPathComponent)
    }

    // MARK: - Helpers

    private static func kind(forExtension ext: String) -> MediaKind {
        switch ext {
        case "mp4", "mov": return .video
        case "srt":        return .telemetry
        case "lrf":        return .proxy
        default:           return .other
        }
    }

    /// Splits a 14-digit `YYYYMMDDHHMMSS` string into calendar components. Returns `nil` if the
    /// string isn't exactly 14 digits (the regex guarantees this for matched names).
    private static func timestampComponents(from digits: String) -> DateComponents? {
        guard digits.count == 14, digits.allSatisfy(\.isNumber) else { return nil }
        func field(_ start: Int, _ length: Int) -> Int? {
            let lower = digits.index(digits.startIndex, offsetBy: start)
            let upper = digits.index(lower, offsetBy: length)
            return Int(digits[lower..<upper])
        }
        var components = DateComponents()
        components.year   = field(0, 4)
        components.month  = field(4, 2)
        components.day    = field(6, 2)
        components.hour   = field(8, 2)
        components.minute = field(10, 2)
        components.second = field(12, 2)
        return components
    }

    private static func substring(_ string: String, _ nsRange: NSRange) -> String {
        guard let range = Range(nsRange, in: string) else { return "" }
        return String(string[range])
    }
}

private extension NSRegularExpression {
    func firstMatch(in string: String, range: NSRange) -> NSTextCheckingResult? {
        firstMatch(in: string, options: [], range: range)
    }
}
