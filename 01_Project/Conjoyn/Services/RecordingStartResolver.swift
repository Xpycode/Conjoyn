import Foundation

// MARK: - Recording-Start Resolver (Wave 2, task 2.8)

/// Resolves the **recording-start wall-clock** for a record group — the single authoritative value
/// from which *both* the output's `creation_time` date atoms **and** its `tmcd` start-timecode track
/// are derived. This inverts the original "source timecode is authoritative" model: DJI's embedded
/// `tmcd` is almost always `00:00:00:00` and its `creation_time` is frequently wrong (the QuickTime
/// 1904/1951-epoch bug + timezone shifts), so there is usually no meaningful source timecode to
/// trust. Instead we resolve a start instant from the signals DJI *does* write correctly, in
/// priority order, and derive everything downstream from that one value (decisions.md, 2026-06-09).
///
/// Resolution order (best DJI signal first):
///  1. **Manual override** — always wins when the user sets it (covers the "no usable signal" tail).
///  2. **SRT telemetry first-cue wall-clock** — DJI writes a real timestamp into the `.SRT`.
///  3. **Filename-embedded datetime** — the `DJI_YYYYMMDDHHMMSS_NNNN_<suffix>` scheme carries it.
///  4. **Embedded `creation_time`** — used only when *sane* (rejects the 1904/1951 epoch + far-future).
///  5. **Filesystem `creationDate`** — reliable only on a fresh SD-card read; resets on Finder copies.
///
/// **Time zones.** The SRT and filename signals are wall-clock with *no* zone, so they are
/// interpreted in `calendar`'s zone (default `.current` — the operator's machine). The embedded and
/// filesystem signals are already absolute `Date`s. The resolved `Date` then feeds
/// `TimecodeFormatter.wallClockTimecode` (recovers the local H:M:S:FF) and `ISO8601Z.format`
/// (UTC `creation_time`). Ported from Penumbra's `DateCorrectionResolver`, extended for DJI with an
/// SRT-first chain and a sanity gate on the embedded date.
enum RecordingStartResolver {

    /// Which signal produced the resolved date.
    enum Provenance: String, Equatable, Sendable {
        case manualOverride
        case srtFirstCue
        case filename
        case embeddedCreationTime
        case filesystem
        case unavailable

        /// Short human-facing label for logs / UI.
        var label: String {
            switch self {
            case .manualOverride:       return "manual override"
            case .srtFirstCue:          return "SRT first cue"
            case .filename:             return "filename datetime"
            case .embeddedCreationTime: return "embedded creation_time"
            case .filesystem:           return "filesystem date"
            case .unavailable:          return "no usable signal"
            }
        }
    }

    /// A cross-check between the two independent *wall-clock* signals (SRT vs filename). Both are
    /// interpreted in the same zone, so their delta is timezone-safe to compare (unlike comparing a
    /// wall-clock signal against the absolute embedded/filesystem dates, where a legitimate UTC
    /// offset would masquerade as a mismatch — so those are deliberately not compared).
    struct Mismatch: Equatable, Sendable {
        let srtDate: Date
        let filenameDate: Date
        /// Absolute difference in seconds.
        var deltaSeconds: TimeInterval { abs(srtDate.timeIntervalSince(filenameDate)) }
    }

    /// The outcome of a resolution: the date, where it came from, and any detected inconsistency.
    struct Resolution: Equatable, Sendable {
        let date: Date?
        let provenance: Provenance
        var mismatch: Mismatch?

        var isResolved: Bool { date != nil }
    }

    /// Seconds beyond which the SRT-vs-filename wall-clocks are considered inconsistent. The first
    /// SRT cue and the filename both mark the recording start, so a healthy pair agrees within a
    /// frame or two; 120 s of slack absorbs rounding and the occasional cue that starts a beat late.
    static let mismatchThresholdSeconds: TimeInterval = 120

    // MARK: - Pure core (unit-testable; no I/O)

    /// Resolves from already-extracted signals. Wall-clock components (`srtWallClock`,
    /// `filenameTimestamp`) carry no zone and are interpreted in `calendar`; `embeddedCreationTime`
    /// and `filesystemDate` are absolute. `now` bounds the sanity gate (injected for tests).
    static func resolve(
        srtWallClock: DateComponents?,
        filenameTimestamp: DateComponents?,
        embeddedCreationTime: Date?,
        filesystemDate: Date?,
        manualOverride: Date?,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Resolution {
        let srtDate = date(from: srtWallClock, calendar: calendar)
        let filenameDate = date(from: filenameTimestamp, calendar: calendar)

        // Cross-check the two wall-clock signals when both exist (timezone-safe).
        var mismatch: Mismatch?
        if let s = srtDate, let f = filenameDate {
            let m = Mismatch(srtDate: s, filenameDate: f)
            if m.deltaSeconds > mismatchThresholdSeconds { mismatch = m }
        }

        // Manual override always wins.
        if let manual = manualOverride {
            return Resolution(date: manual, provenance: .manualOverride, mismatch: mismatch)
        }
        if let s = srtDate {
            return Resolution(date: s, provenance: .srtFirstCue, mismatch: mismatch)
        }
        if let f = filenameDate {
            return Resolution(date: f, provenance: .filename, mismatch: mismatch)
        }
        if let embedded = embeddedCreationTime, isSane(embedded, now: now) {
            return Resolution(date: embedded, provenance: .embeddedCreationTime, mismatch: mismatch)
        }
        if let fs = filesystemDate, isSane(fs, now: now) {
            return Resolution(date: fs, provenance: .filesystem, mismatch: mismatch)
        }
        return Resolution(date: nil, provenance: .unavailable, mismatch: mismatch)
    }

    /// A date is "sane" as a capture instant if it falls in a plausible window: on/after 2010-01-01
    /// (rejects the 1904 and 1951 QuickTime-epoch artifacts) and no later than one day past `now`
    /// (rejects far-future clock garbage). Wall-clock-derived signals skip this gate; only the
    /// absolute embedded/filesystem dates pass through it.
    static func isSane(_ date: Date, now: Date = Date()) -> Bool {
        let floor = Date(timeIntervalSince1970: 1_262_304_000)   // 2010-01-01T00:00:00Z
        let ceiling = now.addingTimeInterval(86_400)             // now + 1 day
        return date >= floor && date <= ceiling
    }

    /// Builds an absolute `Date` from zone-free wall-clock components by interpreting them in
    /// `calendar`. Returns `nil` if the components lack a full Y/M/D H:M:S or don't form a real date.
    static func date(from components: DateComponents?, calendar: Calendar) -> Date? {
        guard let c = components,
              c.year != nil, c.month != nil, c.day != nil,
              c.hour != nil, c.minute != nil, c.second != nil else { return nil }
        var resolved = c
        resolved.calendar = calendar
        resolved.timeZone = calendar.timeZone
        return calendar.date(from: resolved)
    }

    // MARK: - Convenience (gathers signals from a clip; reads the SRT + filesystem)

    /// Resolves the recording start for the **first segment** of a record group, reading its `.SRT`
    /// first-cue wall-clock and filesystem creation date. Pass the group's leading clip.
    static func resolve(
        forFirstSegment clip: DJIClip,
        manualOverride: Date?,
        calendar: Calendar = .current,
        now: Date = Date()
    ) -> Resolution {
        resolve(
            srtWallClock: firstCueWallClock(srtURL: clip.srtURL),
            filenameTimestamp: clip.filenameTimestamp,
            embeddedCreationTime: clip.creationDate,
            filesystemDate: filesystemCreationDate(for: clip.videoURL),
            manualOverride: manualOverride,
            calendar: calendar,
            now: now
        )
    }

    /// Reads the wall-clock embedded in a segment's first `.SRT` cue, if a sidecar is present and
    /// parseable. Never throws — a missing/garbage sidecar simply yields `nil`.
    static func firstCueWallClock(srtURL: URL?) -> DateComponents? {
        guard let srtURL, let doc = try? SRTParser.parse(contentsOf: srtURL) else { return nil }
        return doc.cues.first(where: { $0.wallClock != nil })?.wallClock
    }

    private static func filesystemCreationDate(for url: URL) -> Date? {
        let values = try? url.resourceValues(forKeys: [.creationDateKey])
        return values?.creationDate
    }
}

// MARK: - Timecode / date formatting (ported from Penumbra)

/// SMPTE timecode formatter — converts a wall-clock `Date` to `HH:MM:SS:FF` (or `HH:MM:SS;FF` for
/// drop-frame). Derives FFmpeg's `-timecode` argument. Ported from Penumbra's `TimecodeFormatter`.
enum TimecodeFormatter {
    enum TimecodeError: Error, Equatable {
        case dropFrameOnUnsupportedRate(rate: Double)
    }

    /// Converts a wall-clock `Date` to SMPTE `HH:MM:SS:FF` (or `;FF` for drop-frame). H/M/S/FF are
    /// extracted in `calendar`'s zone (default `.current`) — a camera start timecode represents the
    /// operator's wall-clock at record time, not zulu. Throws `dropFrameOnUnsupportedRate` when
    /// `isDropFrame` is set at any rate that isn't ~29.97 or ~59.94 (FFmpeg's `av_timecode_init`
    /// enforces this). Frame is `floor(subsecond * frameRate)`.
    static func wallClockTimecode(
        for date: Date,
        frameRate: Double,
        isDropFrame: Bool,
        calendar: Calendar = .current
    ) throws -> String {
        if isDropFrame {
            let supported = abs(frameRate - 29.97) < 0.01 || abs(frameRate - 59.94) < 0.01
            guard supported else { throw TimecodeError.dropFrameOnUnsupportedRate(rate: frameRate) }
        }

        let comps = calendar.dateComponents([.hour, .minute, .second, .nanosecond], from: date)
        let h = comps.hour ?? 0
        let m = comps.minute ?? 0
        let s = comps.second ?? 0
        let subsecond = Double(comps.nanosecond ?? 0) / 1_000_000_000.0
        let frame = Int(floor(subsecond * frameRate))

        let sep = isDropFrame ? ";" : ":"
        return String(format: "%02d:%02d:%02d%@%02d", h, m, s, sep, frame)
    }
}

/// ISO 8601 formatter pinned to UTC with fractional-second precision. Produces the `creation_time`
/// value FFmpeg writes onto the joined file's header atoms. Ported from Penumbra's `ISO8601Z`.
enum ISO8601Z {
    // Configured once and only read from thereafter (`string(from:)` is effectively read-only), so
    // the shared instance is safe to share across actors despite `ISO8601DateFormatter` not being
    // `Sendable`. Mirrors the formatter-caching pattern used elsewhere in the app.
    nonisolated(unsafe) private static let formatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()

    static func format(_ date: Date) -> String { formatter.string(from: date) }
}
