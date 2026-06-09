import Foundation

// MARK: - SRT Offset Stitcher (Wave 3, task 3.2)

/// Splices the per-segment `.SRT` sidecars of a joined recording into one continuous telemetry
/// track whose cue timings stay aligned with the stitched video.
///
/// DJI writes each segment's subtitle timestamps **relative to that segment's own start** (every
/// `.SRT` begins at `00:00:00,000`). Concatenating them naively would replay the same opening
/// timestamps at every seam. To re-time them we shift each segment's cues by the cumulative
/// duration of all preceding segments — and crucially that offset comes from the **decoded
/// container duration** (`ffprobe -show_format` → `format=duration`), *not* from the cues
/// themselves. Cue math drifts (the last cue rarely lands exactly on the segment's true end, and
/// DiffTime rounding accumulates); the container duration is the same quantity FFmpeg's concat
/// demuxer uses to lay segments end-to-end, so SRT and video stay locked together at every seam.
///
/// Indices are renumbered globally (1…N across the whole recording). A segment with **no** `.SRT`
/// sidecar contributes no cues but still advances the offset by its duration, so a missing middle
/// sidecar never shifts the cues that follow it out of alignment.
///
/// The stitch itself is pure and unit-testable (durations + parsed documents in → one document
/// out); the ffprobe duration probe and sidecar reading live in the `FFmpegWrapper` extension.
enum SRTStitcher {

    // MARK: - Input

    /// One segment's contribution: its decoded duration and its parsed sidecar (`nil` when the
    /// segment has no `.SRT`). Durations are milliseconds — SRT is millisecond-resolution, and
    /// rounding each segment to the nearest ms keeps seam error far below one video frame.
    struct Segment: Equatable {
        /// Decoded container duration in milliseconds (from ffprobe `format=duration`). Always
        /// advances the cumulative offset, even when `document` is `nil`.
        let durationMilliseconds: Int
        /// The segment's parsed telemetry, or `nil` if no sidecar was present.
        let document: SRTParser.Document?

        init(durationMilliseconds: Int, document: SRTParser.Document?) {
            self.durationMilliseconds = durationMilliseconds
            self.document = document
        }
    }

    // MARK: - Pure stitch

    /// Re-times and renumbers every segment's cues into one continuous document. Segment *i*'s
    /// cues are shifted by Σ of segments `0..<i` durations; indices run 1…N across the result.
    static func stitch(_ segments: [Segment]) -> SRTParser.Document {
        var cues: [SRTParser.Cue] = []
        var offset = 0          // cumulative duration of preceding segments, in ms
        var nextIndex = 1       // global 1-based index across the whole recording

        for segment in segments {
            if let document = segment.document {
                for cue in document.cues {
                    cues.append(SRTParser.Cue(
                        index: nextIndex,
                        startMilliseconds: cue.startMilliseconds + offset,
                        endMilliseconds: cue.endMilliseconds + offset,
                        payload: cue.payload,        // verbatim — telemetry is never rewritten
                        wallClock: cue.wallClock
                    ))
                    nextIndex += 1
                }
            }
            // Advance the offset whether or not this segment had a sidecar.
            offset += segment.durationMilliseconds
        }

        return SRTParser.Document(cues: cues)
    }

    /// Convenience: stitch and render to canonical SubRip text in one call.
    static func stitchToString(_ segments: [Segment]) -> String {
        SRTParser.serialize(stitch(segments).cues)
    }
}

// MARK: - ffprobe-backed duration probing + sidecar stitch

extension FFmpegWrapper {

    /// Probes a media file's decoded container duration via `ffprobe -show_format`, returned in
    /// milliseconds (rounded). This is the drift-free quantity to offset SRT cues by — it matches
    /// how the concat demuxer lays segments end-to-end.
    func probeDurationMilliseconds(_ url: URL) throws -> Int {
        guard let ffprobe = toolResolver.path(for: .ffprobe) else {
            throw StreamParameterGuard.GuardError.probeFailed("ffprobe binary not found")
        }

        let process = Process()
        process.executableURL = ffprobe
        process.arguments = [
            "-v", "quiet",
            "-print_format", "json",
            "-show_format",
            url.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        do {
            try process.run()
        } catch {
            throw StreamParameterGuard.GuardError.probeFailed(error.localizedDescription)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw StreamParameterGuard.GuardError.probeFailed(
                "exit code \(process.terminationStatus) for \(url.lastPathComponent)")
        }

        let format: FFProbeFormat
        do {
            format = try JSONDecoder().decode(FFProbeFormat.self, from: data)
        } catch {
            throw StreamParameterGuard.GuardError.malformedProbeOutput(
                "\(url.lastPathComponent): \(error.localizedDescription)")
        }
        guard let seconds = format.format.duration.flatMap(Double.init), seconds >= 0 else {
            throw StreamParameterGuard.GuardError.malformedProbeOutput(
                "\(url.lastPathComponent): missing or invalid format.duration")
        }
        return Int((seconds * 1000).rounded())
    }

    /// High-level stitch: for each `(video, srt?)` pair, probe the video's duration and parse its
    /// sidecar (when present), then produce one continuous, correctly-timed, globally-numbered
    /// `.SRT`. A `nil` or unreadable sidecar still advances the offset by the segment's duration,
    /// so later cues stay aligned. Returns the stitched SubRip text, or `nil` if no segment had a
    /// sidecar (nothing to write).
    func stitchSRT(
        segments: [(video: URL, srt: URL?)],
        logHandler: LogHandler = { _ in }
    ) throws -> String? {
        var built: [SRTStitcher.Segment] = []
        var sawAnySidecar = false

        for (video, srt) in segments {
            let duration = try probeDurationMilliseconds(video)

            var document: SRTParser.Document?
            if let srt {
                do {
                    document = try SRTParser.parse(contentsOf: srt)
                    sawAnySidecar = true
                } catch {
                    // A missing/unreadable sidecar isn't fatal — note it and keep the offset moving.
                    logHandler("SRT stitch: could not read \(srt.lastPathComponent) — \(error.localizedDescription); skipping its cues")
                    document = nil
                }
            }
            built.append(.init(durationMilliseconds: duration, document: document))
        }

        guard sawAnySidecar else {
            logHandler("SRT stitch: no sidecars present — nothing to write")
            return nil
        }

        let stitched = SRTStitcher.stitch(built)
        logHandler("SRT stitch: \(stitched.cues.count) cues across \(segments.count) segments")
        return SRTParser.serialize(stitched.cues)
    }

    /// Codable mirror of the slice of `ffprobe -show_format` JSON we read. ffprobe reports
    /// `duration` as a seconds string (e.g. `"12.345000"`).
    private struct FFProbeFormat: Decodable {
        let format: Format
        struct Format: Decodable {
            let duration: String?
        }
    }
}
