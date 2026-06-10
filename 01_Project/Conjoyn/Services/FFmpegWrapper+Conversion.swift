import Foundation

// MARK: - Lossless Concat Join (Wave 2, task 2.5)

/// DJI MP4 segments are self-contained, so joining is a container re-mux with the elementary
/// streams copied byte-for-byte — FFmpeg's **concat demuxer** with `-c copy`. There is no BMX
/// rewrap stage (that was P2-only and has been dropped).
///
/// The argument/list construction is split into **pure** static builders (no process, no
/// bundle, no I/O — directly unit-testable) and a thin `mergeClips(...)` that writes the list
/// file and drives `runFFmpeg`.
extension FFmpegWrapper {

    /// Output-side metadata stamped onto the joined file during the join. Populated by
    /// `QueueManager.resolveJoinMetadata` (task 2.8) from the group's resolved recording-start
    /// wall-clock (`RecordingStartResolver`): `creationTime` is the ISO-8601 instant, `timecode`
    /// the derived `HH:MM:SS:FF` start. Both stay optional — either toggle off, or no signal
    /// resolves, leaves a field `nil` and the builder simply omits that flag.
    struct JoinMetadata: Equatable {
        /// `creation_time` value in a form FFmpeg accepts (ISO-8601, e.g.
        /// `2023-08-13T10:20:11.000000Z`). Written via `-metadata creation_time=…`.
        var creationTime: String?
        /// Start timecode `HH:MM:SS:FF` for the output `tmcd` track. Written via `-timecode`.
        var timecode: String?

        init(creationTime: String? = nil, timecode: String? = nil) {
            self.creationTime = creationTime
            self.timecode = timecode
        }
    }

    // MARK: - Pure builders (unit-testable)

    /// Builds the concat-demuxer list-file body for an ordered set of segment URLs.
    ///
    /// Each line is `file '<absolute-path>'`. Embedded single quotes are escaped using FFmpeg's
    /// `'\''` convention so paths with apostrophes are handled. The trailing newline is included.
    static func buildConcatList(for segments: [URL]) -> String {
        segments
            .map { "file '\(concatEscape($0.path))'" }
            .joined(separator: "\n") + "\n"
    }

    /// Builds the full FFmpeg argument vector for a lossless concat join.
    ///
    /// Shape (matches the spec / `CLAUDE.md`):
    /// ```
    /// -f concat -safe 0 -i <list> -map 0:v:0 -map 0:a? -map -0:d -c copy \
    ///   -fflags +genpts -movflags +faststart [-metadata creation_time=…] [-timecode …] -y <out>
    /// ```
    /// - `-map 0:v:0` keeps **only the primary** video stream. DJI MP4s embed a second, low-res
    ///   mjpeg *preview* track (`v:1`); a bare `-map 0:v` would carry it into the joined master,
    ///   where the concat copy mangles it into a malformed 3-frame stream (real-footage finding,
    ///   2026-06). `-map 0:a?` keeps audio when present; `-map -0:d` drops DJI's in-container data
    ///   (telemetry) tracks that would otherwise break `-c copy`.
    /// - `-fflags +genpts` regenerates a clean PTS across the seam; `+faststart` moves the moov
    ///   atom to the front for progressive playback.
    static func buildMergeArguments(
        listFileURL: URL,
        outputURL: URL,
        metadata: JoinMetadata = JoinMetadata()
    ) -> [String] {
        var args: [String] = [
            "-f", "concat",
            "-safe", "0",
            "-i", listFileURL.path,
            "-map", "0:v:0",
            "-map", "0:a?",
            "-map", "-0:d",
            "-c", "copy",
            "-fflags", "+genpts",
            "-movflags", "+faststart",
        ]

        if let creationTime = metadata.creationTime {
            args.append(contentsOf: ["-metadata", "creation_time=\(creationTime)"])
        }
        if let timecode = metadata.timecode {
            args.append(contentsOf: ["-timecode", timecode])
        }

        args.append(contentsOf: ["-y", outputURL.path])
        return args
    }

    /// Escapes a filesystem path for a concat-demuxer `file '…'` directive: a literal single
    /// quote becomes `'\''` (close-quote, escaped quote, re-open-quote).
    static func concatEscape(_ path: String) -> String {
        path.replacingOccurrences(of: "'", with: "'\\''")
    }

    // MARK: - Execution

    /// Joins ordered DJI segments into a single lossless file.
    ///
    /// Writes a temporary concat list, runs the join, and removes the list afterward. The caller
    /// is responsible for grouping (segments must share codec/res/fps — the param guard, task
    /// 2.6, lands in this path next) and for supplying `totalFrames` for accurate progress.
    /// - Parameters:
    ///   - segments: Ordered segment URLs (already validated as a contiguous group).
    ///   - outputURL: Destination for the joined file.
    ///   - metadata: Optional `creation_time` / start timecode to stamp on the output.
    ///   - totalFrames: Optional combined frame count for progress estimation.
    ///   - verifyParameters: When true (default), runs the stream-parameter guard (task 2.6)
    ///     and refuses the `-c copy` join if the segments' codec/res/fps/timebase/audio differ.
    func mergeClips(
        _ segments: [URL],
        to outputURL: URL,
        metadata: JoinMetadata = JoinMetadata(),
        totalFrames: Int? = nil,
        verifyParameters: Bool = true,
        progress: @escaping ProgressHandler,
        logHandler: @escaping LogHandler = { _ in },
        metricsHandler: MetricsHandler? = nil
    ) async throws {
        resetCancellation()

        guard let ffmpeg = ffmpegPath else {
            logHandler("ERROR: FFmpeg not found!")
            throw FFmpegError.ffmpegNotFound
        }
        guard segments.count >= 2 else {
            throw FFmpegError.invalidInput("Need at least two segments to join (got \(segments.count))")
        }

        progress(0.0, "Preparing join…")

        // Pre-join parameter guard (task 2.6): refuse a lossless copy of mismatched streams.
        if verifyParameters {
            progress(0.05, "Verifying segment compatibility…")
            try ensureJoinable(segments, logHandler: logHandler)
        }

        // Write the concat list to a temp file (TempDirectoryManager lands in Wave 1.5).
        let listFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("djijoiner-concat-\(UUID().uuidString).txt")
        let listBody = Self.buildConcatList(for: segments)
        try listBody.write(to: listFileURL, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: listFileURL) }

        let args = Self.buildMergeArguments(
            listFileURL: listFileURL,
            outputURL: outputURL,
            metadata: metadata
        )
        logHandler("Command: ffmpeg " + args.joined(separator: " "))
        logHandler("Joining \(segments.count) segments → \(outputURL.lastPathComponent)")

        progress(0.1, "Starting FFmpeg…")
        try await runFFmpeg(
            at: ffmpeg,
            arguments: args,
            totalFrames: totalFrames,
            progress: progress,
            logHandler: logHandler,
            metricsHandler: metricsHandler
        )
        progress(1.0, "Join complete")
    }
}
