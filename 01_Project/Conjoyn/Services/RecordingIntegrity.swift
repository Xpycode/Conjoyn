import Foundation

// MARK: - Recording Integrity (recordings-list inline flags)

/// Display-only, per-recording metadata-integrity summary shown inline on a discovered-recording row.
/// It surfaces the cases where a clip's date/timecode is missing, implausible, inconsistent, or
/// slow-motion — and *which* signal Conjoyn will actually stamp from — so the row never silently
/// shows a wrong embedded date as if it were authoritative.
///
/// **No engine coupling.** Every value is recomputed from the group's first segment with the very
/// same `RecordingStartResolver` (+ `TimecodeDisclosure.detectSlowMotion`) the join uses, so what the
/// row flags is exactly what gets stamped on export. Built lazily by the row (`.task`), never
/// persisted — purely a readout. Cheaper than `TimecodeDisclosure.build`: it skips the
/// `SourceTimecodeReader` (embedded `tmcd`) read, since DJI clips almost never carry one and it is
/// irrelevant to the integrity story (engine basis: `docs/decisions.md`, 2026-06-09 stamp model).
struct RecordingIntegrity: Equatable, Sendable {
    /// Ordered warnings-before-info; empty means the recording is clean (no inline line is shown).
    let flags: [Flag]
    /// The corrected recording start the resolver picked (may differ from the embedded date). `nil`
    /// when no signal resolved. Drives the row's date line so list and queue agree.
    let resolvedDate: Date?
    /// Which signal produced `resolvedDate`.
    let provenance: RecordingStartResolver.Provenance
    /// True when `resolvedDate` came from something other than the embedded `creation_time` — the row
    /// shows an origin tag ("from filename" / "from SRT cue") only in that case.
    let usedNonEmbeddedSignal: Bool

    var hasIssues: Bool { !flags.isEmpty }
    var hasWarning: Bool { flags.contains { $0.severity == .warning } }

    /// Short "from X" tag for the date line; `nil` for the clean embedded case (nothing to say).
    var originTag: String? {
        guard usedNonEmbeddedSignal else { return nil }
        switch provenance {
        case .srtFirstCue:    return "from SRT cue"
        case .filename:       return "from filename"
        case .filesystem:     return "from file date"
        case .manualOverride: return "manual"
        default:              return nil
        }
    }

    // MARK: Severity

    enum Severity: Int, Comparable {
        case info = 0, warning = 1
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    // MARK: Flag

    struct Flag: Equatable, Sendable {
        let kind: Kind
        var severity: Severity { kind.severity }
        var label: String { kind.label }       // inline chip text
        var detail: String { kind.detail }     // .help tooltip

        enum Kind: Equatable, Sendable {
            /// No SRT, filename, or sane embedded date — nothing to stamp.
            case noSignalAtAll
            /// SRT and filename wall-clocks disagree beyond the resolver's tolerance; SRT wins.
            case srtFilenameMismatch(deltaSeconds: TimeInterval)
            /// Embedded `creation_time` is present but implausible; the named signal is substituted.
            case embeddedDateUnusable(RecordingStartResolver.Provenance)
            /// Container playback runs longer than real time (SRT-derived).
            case slowMotionDualTimebase

            var severity: Severity {
                switch self {
                case .noSignalAtAll, .srtFilenameMismatch, .embeddedDateUnusable: return .warning
                case .slowMotionDualTimebase: return .info
                }
            }

            var label: String {
                switch self {
                case .noSignalAtAll:
                    return "no recording date"
                case .srtFilenameMismatch(let delta):
                    return "SRT/filename differ by \(RecordingIntegrity.formatDelta(delta))"
                case .embeddedDateUnusable:
                    return "bad embedded date"
                case .slowMotionDualTimebase:
                    return "slow-mo"
                }
            }

            var detail: String {
                switch self {
                case .noSignalAtAll:
                    return "No .SRT, filename, or valid embedded date — Conjoyn can't stamp a real "
                        + "timecode. Re-export with a manual date to fix."
                case .srtFilenameMismatch:
                    return "The .SRT telemetry and the filename timestamp disagree by more than two "
                        + "minutes; the SRT value is used. Verify the camera clock."
                case .embeddedDateUnusable(let p):
                    return "The file's embedded creation time is implausible; Conjoyn uses the "
                        + "\(p.label) instead. Re-export to stamp a correct timecode."
                case .slowMotionDualTimebase:
                    return "Slow-motion: playback runs longer than real time. The timecode starts at "
                        + "the real recording instant and advances at the playback rate."
                }
            }
        }
    }
}

extension RecordingIntegrity {

    /// Builds the integrity summary for a group's first segment, reusing the engine's resolver and the
    /// slow-mo detector. `async` only because the resolver/slow-mo read the `.SRT` sidecar off disk;
    /// never throws — a missing/garbage sidecar degrades to fewer flags, not a failure.
    ///
    /// The first segment speaks for the whole group: the grouping gate refuses to chain mismatched
    /// signals, so its resolved start is the group's. (Accepts the small cost of parsing the SRT twice
    /// — once in `resolve`, once in `detectSlowMotion` — for the simplicity of reusing both verbatim;
    /// it runs lazily per visible row on the first segment only.)
    static func build(
        group: RecordGroup,
        settings: ConversionSettings,
        calendar: Calendar = .current
    ) async -> RecordingIntegrity {
        guard let first = group.clips.first else {
            return RecordingIntegrity(
                flags: [], resolvedDate: nil, provenance: .unavailable, usedNonEmbeddedSignal: false
            )
        }

        let resolution = RecordingStartResolver.resolve(
            forFirstSegment: first, manualOverride: settings.dateOverride, calendar: calendar
        )
        let provenance = resolution.provenance
        let embedded = first.creationDate
        let embeddedSane = embedded.map { RecordingStartResolver.isSane($0) } ?? false
        let isSlowMotion = TimecodeDisclosure.detectSlowMotion(clip: first, calendar: calendar)
        let usedNonEmbeddedSignal = resolution.date != nil && provenance != .embeddedCreationTime

        var flags: [Flag] = []

        // Warnings ───────────────────────────────────────────────────────────
        if provenance == .unavailable {
            flags.append(Flag(kind: .noSignalAtAll))
        } else if embedded != nil, !embeddedSane {
            // Embedded date present but rejected by the sanity gate; a substitute was used.
            flags.append(Flag(kind: .embeddedDateUnusable(provenance)))
        }
        // A manual override makes the "SRT value is used" copy untrue, so suppress the mismatch there.
        if provenance != .manualOverride, resolution.mismatch != nil {
            flags.append(Flag(kind: .srtFilenameMismatch(deltaSeconds: resolution.mismatch!.deltaSeconds)))
        }

        // Info ───────────────────────────────────────────────────────────────
        // The "date from X" origin is shown inline on the date line (originTag), not as a chip — a
        // chip there would just duplicate it. The strip is reserved for genuine issues + slow-mo.
        if isSlowMotion { flags.append(Flag(kind: .slowMotionDualTimebase)) }

        return RecordingIntegrity(
            flags: flags,
            resolvedDate: resolution.date,
            provenance: provenance,
            usedNonEmbeddedSignal: usedNonEmbeddedSignal
        )
    }

    /// Formats a wall-clock delta for the mismatch chip: "45 s", "2 min", "1 h 4 min".
    static func formatDelta(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let minutes = total / 60
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let remMin = minutes % 60
        return remMin == 0 ? "\(hours) h" : "\(hours) h \(remMin) min"
    }
}

// MARK: - Provenance short label (chip-sized)

private extension RecordingStartResolver.Provenance {
    /// A terse signal name for inline chips ("date from filename"); `label` is the longer log form.
    var shortLabel: String {
        switch self {
        case .manualOverride:       return "manual"
        case .srtFirstCue:          return "SRT"
        case .filename:             return "filename"
        case .embeddedCreationTime: return "creation time"
        case .filesystem:           return "file date"
        case .unavailable:          return "—"
        }
    }
}
