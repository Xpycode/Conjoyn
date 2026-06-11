import Foundation

// MARK: - Timecode Disclosure (rename-and-tc-disclosure, Part 2)

/// Display-only summary of the timecode transformation Conjoyn performs for one queued job, shown in
/// the queue row's expandable disclosure panel. It surfaces the gap between DJI's (almost always
/// empty) **source** `tmcd` and the **applied** start timecode the engine derives from the resolved
/// recording-start wall-clock.
///
/// **No engine coupling.** Every value here is recomputed from the job's *already-frozen* `clips`
/// and `settings` with the very same `RecordingStartResolver` + `TimecodeFormatter` the join uses in
/// `QueueManager.resolveJoinMetadata`, so what the row shows is exactly what gets stamped. It is
/// built lazily by the row (`.task`) and never persisted — purely a readout. (Engine basis:
/// `docs/decisions.md`, 2026-06-09 "date+timecode stamp model".)
struct TimecodeDisclosure: Equatable, Sendable {
    /// Segment-1's embedded `tmcd`, formatted `HH:MM:SS:FF`. `nil` when the source has no timecode
    /// track at all (the common DJI case) — the row shows "—".
    let sourceTimecode: String?
    /// The `HH:MM:SS:FF` Conjoyn stamps onto the joined output. `nil` when "Timecode from recording
    /// time" is off, or when no recording-start signal resolved.
    let appliedTimecode: String?
    /// Which resolver signal won — drives the origin tag beside the applied TC.
    let origin: RecordingStartResolver.Provenance
    /// Frame rate used for the `FF` component (segment-1's probed fps; the param guard proved the
    /// group shares one rate). Falls back to 30 when unprobed.
    let frameRate: Double
    /// Whether "Timecode from recording time" is enabled for this job (drives the OFF copy).
    let timecodeEnabled: Bool
    /// True when segment 1 is a slow-motion recording (container playback duration ≫ real elapsed,
    /// detected from the SRT wall-clock span). Drives the one-line slow-mo note.
    let isSlowMotion: Bool

    /// Short origin tag for the applied TC, matching which resolver source won.
    var originTag: String {
        switch origin {
        case .manualOverride:       return "manual"
        case .srtFirstCue:          return "from SRT cue"
        case .filename:             return "from filename"
        case .embeddedCreationTime: return "from creation time"
        case .filesystem:           return "from file date"
        case .unavailable:          return "no signal"
        }
    }

    /// `25` → "25", `29.97` → "29.97". Integer rates lose the trailing `.00`.
    var frameRateLabel: String {
        frameRate == frameRate.rounded() ? String(Int(frameRate)) : String(format: "%.2f", frameRate)
    }
}

extension TimecodeDisclosure {

    /// Slow-mo detection threshold: the cue **playback** span must exceed the **real** wall-clock
    /// span by at least this factor to be flagged. A normal recording sits at ~1.0; DJI slow-mo runs
    /// 2×–8×. 1.5 leaves generous slack for rounding without false-positiving a normal clip.
    static let slowMotionRatioThreshold = 1.5

    /// Builds the disclosure for a job's first segment. `async` only because reading the source
    /// `tmcd` uses `AVAssetReader`; the resolver / formatter / slow-mo work is synchronous. Safe to
    /// call off the main actor, and never throws — a missing tmcd or unparseable SRT degrades to
    /// `nil` / `false` rather than failing.
    ///
    /// - Parameter tcOverride: A manually-entered `HH:MM:SS:FF` string (from
    ///   `ConversionJob.timecodeStringOverride`). When non-nil it wins over all resolver signals and
    ///   is shown verbatim as the applied timecode with `origin: .manualOverride`. The existing
    ///   `settings.dateOverride` path (which flows through `RecordingStartResolver`) is left
    ///   unchanged for cases where the override is a `Date` rather than a pre-formatted string.
    static func build(
        clips: [DJIClip],
        settings: ConversionSettings,
        tcOverride: String? = nil,
        calendar: Calendar = .current
    ) async -> TimecodeDisclosure {
        guard let first = clips.first else {
            return TimecodeDisclosure(
                sourceTimecode: nil, appliedTimecode: nil, origin: .unavailable,
                frameRate: 30, timecodeEnabled: settings.preserveTimecode, isSlowMotion: false
            )
        }

        // Source tmcd — almost always absent for DJI; a missing track is the normal "—" case.
        let sourceTimecode = try? await SourceTimecodeReader().read(from: first.videoURL).formatted

        let fps = first.streamInfo?.video.framesPerSecond ?? 30.0
        let isSlowMo = detectSlowMotion(clip: first, calendar: calendar)

        // A pre-formatted string override wins over all resolver logic. The UI passes this when the
        // user has typed a timecode directly in the queue row — it skips date resolution entirely.
        if let override = tcOverride {
            return TimecodeDisclosure(
                sourceTimecode: sourceTimecode,
                appliedTimecode: override,
                origin: .manualOverride,
                frameRate: fps,
                timecodeEnabled: settings.preserveTimecode,
                isSlowMotion: isSlowMo
            )
        }

        // Resolve the recording start exactly as the engine does (same resolver, same fallback fps),
        // so the applied TC the row shows is identical to what `resolveJoinMetadata` stamps.
        let resolution = RecordingStartResolver.resolve(
            forFirstSegment: first, manualOverride: settings.dateOverride, calendar: calendar
        )

        var appliedTimecode: String?
        if settings.preserveTimecode, let date = resolution.date {
            // DJI records non-drop-frame; mirrors resolveJoinMetadata's call.
            appliedTimecode = try? TimecodeFormatter.wallClockTimecode(
                for: date, frameRate: fps, isDropFrame: false, calendar: calendar
            )
        }

        return TimecodeDisclosure(
            sourceTimecode: sourceTimecode,
            appliedTimecode: appliedTimecode,
            origin: resolution.provenance,
            frameRate: fps,
            timecodeEnabled: settings.preserveTimecode,
            isSlowMotion: isSlowMo
        )
    }

    /// Best-effort slow-mo detection from the SRT. The cue **playback** span (the subtitle display
    /// timeline, which tracks the file's playback duration) is compared against the **real**
    /// wall-clock span embedded in the cue payloads. A normal clip's two spans match (~1.0); a
    /// slow-mo clip's playback span is several × the real span (the keystone `slowmo-dual-timebase`
    /// finding). No SRT, or fewer than two timestamped cues, → not flagged.
    static func detectSlowMotion(clip: DJIClip, calendar: Calendar) -> Bool {
        guard let srtURL = clip.srtURL,
              let doc = try? SRTParser.parse(contentsOf: srtURL) else { return false }
        let timestamped = doc.cues.filter { $0.wallClock != nil }
        guard let firstCue = timestamped.first, let lastCue = timestamped.last,
              firstCue.startMilliseconds != lastCue.startMilliseconds,
              let firstWall = RecordingStartResolver.date(from: firstCue.wallClock, calendar: calendar),
              let lastWall  = RecordingStartResolver.date(from: lastCue.wallClock, calendar: calendar)
        else { return false }

        let playbackSpan = Double(lastCue.startMilliseconds - firstCue.startMilliseconds) / 1000.0
        let realSpan = lastWall.timeIntervalSince(firstWall)
        guard realSpan > 0, playbackSpan > 0 else { return false }
        return playbackSpan / realSpan >= slowMotionRatioThreshold
    }
}
