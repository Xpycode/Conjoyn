import Foundation

// MARK: - Rename Pattern Engine (output-name templating)

/// Pure, stateless engine that turns a user's naming *pattern* (with `{name}` `{date}` `{time}`
/// `{###}` tokens) into a filesystem-safe output **stem** (no extension). It is the Swift port of
/// the design handoff's `cjApplyPattern` (`02_Design/design_handoff_rename_popover/rename.jsx`),
/// kept 1:1 on token semantics, illegal-char stripping, and the empty→`{name}` fallback.
///
/// Deliberately I/O-free and `Calendar`-injectable (like `RecordingStartResolver` /
/// `TimecodeFormatter`): the caller resolves the recording-start `Date` once — from the *same*
/// `RecordingStartResolver` the date/timecode stamp uses, so the filename and the embedded metadata
/// can never disagree — and hands it in. The engine just formats. Collision handling is the only
/// stateful concern, and even that is expressed as the pure `uniqueStem(_:taken:)` below.
enum RenamePatternEngine {

    /// The session-only rename settings the popover edits and `applyStem` consumes.
    struct Options: Equatable, Sendable {
        /// The token pattern, e.g. `{name}_{date}_joined`.
        var pattern: String
        /// First counter value for the 0-based batch (the `{###}` of the first recording).
        var start: Int
        /// Zero-padding width for `{###}` (2, 3, or 4).
        var digits: Int

        /// Handoff default: `RENAME_DEFAULTS = { pattern: "{name}_{date}_joined", start: 1, pad: 3 }`.
        static let `default` = Options(pattern: "{name}_{date}_joined", start: 1, digits: 3)
    }

    /// Insertable tokens (token, human label) — drives the popover's token pills, in handoff order.
    static let tokens: [(token: String, label: String)] = [
        ("{name}", "First clip name"),
        ("{date}", "Recording date"),
        ("{time}", "Start time"),
        ("{###}", "Counter"),
    ]

    /// Preset (label, pattern) pairs — drives the popover's preset chips, in handoff order.
    static let presets: [(label: String, pattern: String)] = [
        ("Original + date", "{name}_{date}_joined"),
        ("Date + counter", "{date}_flight_{###}"),
        ("Date + time", "{date}_{time}"),
    ]

    /// Filesystem-illegal characters, each mapped to `-` (matches the JS `/[\\/:*?"<>|]/g`).
    private static let illegalCharacters = CharacterSet(charactersIn: "\\/:*?\"<>|")

    /// Whether a pattern uses the counter token (gates the popover's "Counter" row).
    static func usesCounter(_ pattern: String) -> Bool { pattern.contains("{###}") }

    // MARK: - Apply

    /// Renders `options.pattern` into a filesystem-safe output stem (no extension) for one recording.
    ///
    /// - Parameters:
    ///   - name: the first segment's basename without extension (e.g. `DJI_20260521195303_0009_D`).
    ///   - date: the resolved recording-start wall-clock; `{date}`/`{time}` expand from it. When
    ///     `nil` (resolver found no usable signal) both tokens expand to empty — the empty→`name`
    ///     fallback then catches a pattern that is *only* date/time tokens.
    ///   - options: the active pattern + counter settings.
    ///   - index: 0-based position of this recording in its Add-to-Queue batch; `{###}` =
    ///     `options.start + index`. The counter restarts each batch (product decision 2026-06-10).
    ///   - calendar: zone in which `date` is broken into Y/M/D H:M:S (default `.current`).
    static func applyStem(
        name: String,
        date: Date?,
        options: Options,
        index: Int,
        calendar: Calendar = .current
    ) -> String {
        let counter = String(format: "%0\(max(0, options.digits))d", options.start + index)
        let dateString = date.map { formattedDate($0, calendar: calendar) } ?? ""
        let timeString = date.map { formattedTime($0, calendar: calendar) } ?? ""

        var out = options.pattern
            .replacingOccurrences(of: "{name}", with: name)
            .replacingOccurrences(of: "{date}", with: dateString)
            .replacingOccurrences(of: "{time}", with: timeString)
            .replacingOccurrences(of: "{###}", with: counter)

        out = out.components(separatedBy: illegalCharacters).joined(separator: "-")
        out = out.trimmingCharacters(in: .whitespacesAndNewlines)

        return out.isEmpty ? name : out
    }

    // MARK: - Collision suffixing

    /// Returns `stem` if free, else the first `stem_2`, `stem_3`, … not already in `taken`.
    /// Comparison is **case-insensitive** (macOS volumes are case-insensitive by default, so
    /// `Flight` and `flight` would collide on disk). The caller threads a running `taken` set across
    /// the batch and seeds it with the queue + destination-folder listing so no two outputs — or an
    /// existing file — ever share a name (product decision 2026-06-10).
    static func uniqueStem(_ stem: String, taken: Set<String>) -> String {
        func isTaken(_ candidate: String) -> Bool {
            taken.contains { $0.caseInsensitiveCompare(candidate) == .orderedSame }
        }
        guard isTaken(stem) else { return stem }
        var n = 2
        while isTaken("\(stem)_\(n)") { n += 1 }
        return "\(stem)_\(n)"
    }

    // MARK: - Token formatting (zone-aware, locale-independent)

    /// `{date}` → `YYYY-MM-DD`. Built from `Calendar` components (not `DateFormatter`) so the result
    /// is independent of the machine's locale/format settings — only its time zone matters.
    private static func formattedDate(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// `{time}` → `HH.MM.SS` (colon-free so it is filesystem-safe and matches the handoff's
    /// `rec.time.split(":").join(".")`).
    private static func formattedTime(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.hour, .minute, .second], from: date)
        return String(format: "%02d.%02d.%02d", c.hour ?? 0, c.minute ?? 0, c.second ?? 0)
    }
}
