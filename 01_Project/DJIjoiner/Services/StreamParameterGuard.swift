import Foundation

// MARK: - Pre-join Stream-Parameter Guard (Wave 2, task 2.6)

/// FFmpeg's concat demuxer with `-c copy` re-muxes the container while copying the elementary
/// streams verbatim — it does **not** re-encode. That only produces a valid file when every
/// segment shares the same codec, resolution, pixel format, frame rate, and timebase (and a
/// matching audio layout). Joining mismatched segments with `-c copy` yields corruption or a
/// hard FFmpeg failure, so we probe each segment with ffprobe and refuse up front with a clear,
/// field-level message.
///
/// The comparison and ffprobe-JSON decoding are pure and unit-testable (no process, no files);
/// the ffprobe invocation lives in the `FFmpegWrapper` extension below.
enum StreamParameterGuard {

    // MARK: - Parsed parameters

    /// The copy-relevant parameters of a segment's video stream.
    ///
    /// `Codable`/`Sendable` so it can be embedded on `DJIClip` (the single source of truth for the
    /// param gate, persisted with the queue); `Hashable` so the embedding clip stays `Hashable`.
    struct VideoStreamParams: Hashable, Codable, Sendable {
        var codecName: String        // e.g. "h264", "hevc"
        var width: Int
        var height: Int
        var pixelFormat: String      // e.g. "yuv420p"
        var avgFrameRate: String     // raw rational, e.g. "30000/1001"
        var timeBase: String         // raw rational, e.g. "1/30000"
    }

    /// The copy-relevant parameters of a segment's (optional) audio stream.
    struct AudioStreamParams: Hashable, Codable, Sendable {
        var codecName: String        // e.g. "aac"
        var sampleRate: String       // ffprobe reports this as a string, e.g. "48000"
        var channels: Int
        var channelLayout: String?   // e.g. "stereo"; may be absent
    }

    /// One segment's joinable stream parameters.
    struct SegmentStreamInfo: Hashable, Codable, Sendable {
        var video: VideoStreamParams
        var audio: AudioStreamParams?
    }

    /// Result of comparing a set of segments.
    enum Compatibility: Equatable {
        case compatible
        case incompatible(reason: String)
    }

    enum GuardError: LocalizedError {
        case noVideoStream(String)
        case probeFailed(String)
        case malformedProbeOutput(String)
        case incompatible(String)

        var errorDescription: String? {
            switch self {
            case .noVideoStream(let f):       return "No video stream found in \(f)"
            case .probeFailed(let m):         return "ffprobe failed: \(m)"
            case .malformedProbeOutput(let m): return "Could not read ffprobe output: \(m)"
            case .incompatible(let m):        return "Segments cannot be joined losslessly: \(m)"
            }
        }
    }

    // MARK: - Pure comparison

    /// Checks that every segment matches the first on all copy-relevant parameters. Returns the
    /// first mismatch found (naming the field, both values, and the 1-based segment number) so
    /// the UI/log can explain exactly why a `-c copy` join was refused.
    static func check(_ segments: [SegmentStreamInfo]) -> Compatibility {
        guard let reference = segments.first else { return .compatible }

        for (offset, segment) in segments.enumerated().dropFirst() {
            let n = offset + 1   // 1-based for human-facing messages
            let v = segment.video, rv = reference.video

            if v.codecName != rv.codecName {
                return mismatch("video codec", rv.codecName, v.codecName, n)
            }
            if v.width != rv.width || v.height != rv.height {
                return mismatch("resolution", "\(rv.width)x\(rv.height)", "\(v.width)x\(v.height)", n)
            }
            if v.pixelFormat != rv.pixelFormat {
                return mismatch("pixel format", rv.pixelFormat, v.pixelFormat, n)
            }
            if v.avgFrameRate != rv.avgFrameRate {
                return mismatch("frame rate", rv.avgFrameRate, v.avgFrameRate, n)
            }
            if v.timeBase != rv.timeBase {
                return mismatch("time base", rv.timeBase, v.timeBase, n)
            }

            // Audio must match in presence and parameters, or the copied stream desyncs.
            switch (reference.audio, segment.audio) {
            case (nil, nil):
                break
            case (.some, nil):
                return mismatch("audio presence", "audio", "none", n)
            case (nil, .some):
                return mismatch("audio presence", "none", "audio", n)
            case let (ra?, a?):
                if a.codecName != ra.codecName {
                    return mismatch("audio codec", ra.codecName, a.codecName, n)
                }
                if a.sampleRate != ra.sampleRate {
                    return mismatch("audio sample rate", ra.sampleRate, a.sampleRate, n)
                }
                if a.channels != ra.channels {
                    return mismatch("audio channels", "\(ra.channels)", "\(a.channels)", n)
                }
                if a.channelLayout != ra.channelLayout {
                    return mismatch("audio channel layout",
                                    ra.channelLayout ?? "unset", a.channelLayout ?? "unset", n)
                }
            }
        }
        return .compatible
    }

    private static func mismatch(_ field: String, _ expected: String, _ got: String, _ segment: Int) -> Compatibility {
        .incompatible(reason: "segment \(segment) \(field) is \(got), expected \(expected) (from segment 1)")
    }

    // MARK: - ffprobe JSON decoding

    /// Decodes `ffprobe -print_format json -show_streams` output into `SegmentStreamInfo`.
    /// Throws `GuardError.noVideoStream` if there's no video stream.
    static func parse(ffprobeJSON data: Data, source: String = "input") throws -> SegmentStreamInfo {
        let probe: FFProbeStreams
        do {
            probe = try JSONDecoder().decode(FFProbeStreams.self, from: data)
        } catch {
            throw GuardError.malformedProbeOutput("\(source): \(error.localizedDescription)")
        }

        guard let v = probe.streams.first(where: { $0.codec_type == "video" }) else {
            throw GuardError.noVideoStream(source)
        }
        let video = VideoStreamParams(
            codecName: v.codec_name ?? "unknown",
            width: v.width ?? 0,
            height: v.height ?? 0,
            pixelFormat: v.pix_fmt ?? "unknown",
            avgFrameRate: v.avg_frame_rate ?? "0/0",
            timeBase: v.time_base ?? "0/0"
        )

        let audio = probe.streams.first(where: { $0.codec_type == "audio" }).map {
            AudioStreamParams(
                codecName: $0.codec_name ?? "unknown",
                sampleRate: $0.sample_rate ?? "0",
                channels: $0.channels ?? 0,
                channelLayout: $0.channel_layout
            )
        }
        return SegmentStreamInfo(video: video, audio: audio)
    }

    /// Codable mirror of the subset of ffprobe's `-show_streams` JSON we read.
    private struct FFProbeStreams: Decodable {
        let streams: [Stream]
        struct Stream: Decodable {
            let codec_type: String?
            let codec_name: String?
            let width: Int?
            let height: Int?
            let pix_fmt: String?
            let avg_frame_rate: String?
            let time_base: String?
            let sample_rate: String?
            let channels: Int?
            let channel_layout: String?
        }
    }
}

// MARK: - ffprobe-backed probing

extension FFmpegWrapper {

    /// Probes one segment's joinable stream parameters via ffprobe.
    func probeStreamInfo(_ url: URL) throws -> StreamParameterGuard.SegmentStreamInfo {
        guard let ffprobe = toolResolver.path(for: .ffprobe) else {
            throw StreamParameterGuard.GuardError.probeFailed("ffprobe binary not found")
        }

        let process = Process()
        process.executableURL = ffprobe
        process.arguments = ["-v", "quiet", "-print_format", "json", "-show_streams", url.path]

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
            throw StreamParameterGuard.GuardError.probeFailed("exit code \(process.terminationStatus) for \(url.lastPathComponent)")
        }
        return try StreamParameterGuard.parse(ffprobeJSON: data, source: url.lastPathComponent)
    }

    /// Probes every segment and throws `GuardError.incompatible` if they can't be `-c copy` joined.
    /// Logs the per-segment parameters and the verdict.
    func ensureJoinable(_ segments: [URL], logHandler: LogHandler = { _ in }) throws {
        let infos = try segments.map { try probeStreamInfo($0) }
        switch StreamParameterGuard.check(infos) {
        case .compatible:
            logHandler("Stream-parameter guard: \(segments.count) segments are join-compatible")
        case .incompatible(let reason):
            logHandler("Stream-parameter guard: REFUSED — \(reason)")
            throw StreamParameterGuard.GuardError.incompatible(reason)
        }
    }
}
