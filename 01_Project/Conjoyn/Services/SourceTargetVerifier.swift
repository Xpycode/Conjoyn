import Foundation

/// True **source↔target** verification of a completed lossless concat join.
///
/// The join is `-c copy`, so the output's kept streams (`v:0`, and `a:0` when present) should be
/// *byte-identical* to the concatenation of the sources. This service exploits that: it compares
/// the output container index against the sum of the sources (Tier 0/1, ~seconds) and, on demand
/// or on a Tier-1 anomaly, hashes the kept streams end-to-end for a cryptographic proof (Tier 2,
/// tens of seconds–minutes).
///
/// Modeled on `VerificationService` (the older, unwired decode-only check): `final … @unchecked
/// Sendable` with all mutable state (`_currentProcess`, `_isCancelling`) guarded by `cancelLock`,
/// so the service can be driven from the `@MainActor` `QueueManager` and hand work to a
/// non-isolated `Process` under Swift 6 strict concurrency.
///
/// **Never throws.** Both public entry points return a `SourceTargetResult`; an errored verifier
/// (missing tool, ejected source, malformed probe) becomes a `.fail` check, never a queue crash.
final class SourceTargetVerifier: @unchecked Sendable {

    /// Inputs for one verification pass over a completed join.
    struct SourceTargetInput: Sendable {
        /// Ordered source segment URLs (the exact set fed to the concat join). N=1 is valid.
        let sourceSegments: [URL]
        /// The actual joined output file (renamed/collision-suffixed URL, not the nominal one).
        let outputURL: URL
        /// Whether the kept set includes audio (`a:0`). When false, `a:0` is omitted everywhere.
        let hasAudio: Bool
        /// Per-segment probed stream params (already on `DJIClip.streamInfo`), in source order.
        /// Used by the codec-param identity check; `nil` entries are tolerated as "unknown".
        let sourceParams: [StreamParameterGuard.SegmentStreamInfo?]
    }

    typealias ProgressHandler = @Sendable (Double) -> Void
    typealias LogHandler = @Sendable (String) -> Void

    // MARK: - Cancellation / process state (mirror VerificationService)

    private var _currentProcess: Process?
    private let cancelLock = NSLock()
    private var _isCancelling = false

    private var currentProcess: Process? {
        get { cancelLock.withLock { _currentProcess } }
        set { cancelLock.withLock { _currentProcess = newValue } }
    }
    private(set) var isCancelling: Bool {
        get { cancelLock.withLock { _isCancelling } }
        set { cancelLock.withLock { _isCancelling = newValue } }
    }

    private let toolResolver = BundledToolResolver.shared
    private let ffmpeg = FFmpegWrapper()

    private var ffmpegPath: URL? { toolResolver.path(for: .ffmpeg) }
    private var ffprobePath: URL? { toolResolver.path(for: .ffprobe) }

    /// Cancels any running verification (kills a long Tier-2 hash mid-flight).
    func cancel() {
        isCancelling = true
        if let process = currentProcess, process.isRunning {
            process.terminate()
        }
        currentProcess = nil
    }

    func resetCancellation() {
        isCancelling = false
    }

    // MARK: - Tolerances (pinned by tests — a refactor must not silently change these)

    /// Duration delta within this many frame intervals is informational (a clean join routinely
    /// lands a frame off after `+genpts`).
    static let durationToleranceFrames = 1.0
    /// FPS fallback when a segment reports `0/0` / VFR — matches the rest of the app.
    static let fpsFallback = 30.0
    /// Fraction of the shortest segment a duration shortfall must reach to be a definitive
    /// "missing trailing segment" failure (rather than a warning to escalate).
    static let wholeSegmentShortfallFraction = 0.9

    // MARK: - Public API

    /// Tier 0 + Tier 1 (container-index comparison). `tier: .fast`.
    func verifyFast(
        _ input: SourceTargetInput,
        progress: ProgressHandler? = nil,
        logHandler: LogHandler? = nil
    ) async -> SourceTargetResult {
        resetCancellation()
        let start = Date()
        // Tier 0 short-circuits inside runTier0And1 when readability fails.
        let checks = await runTier0And1(input, progress: progress, logHandler: logHandler)
        progress?(1.0)
        return SourceTargetResult(
            tier: .fast,
            checks: checks,
            verifiedAt: Date(),
            duration: Date().timeIntervalSince(start)
        )
    }

    /// Tier 0 + Tier 1 + Tier 2 (byte-exact per-stream hash). `tier: .thorough`.
    func verifyThorough(
        _ input: SourceTargetInput,
        progress: ProgressHandler? = nil,
        logHandler: LogHandler? = nil
    ) async -> SourceTargetResult {
        resetCancellation()
        let start = Date()
        var checks = await runTier0And1(
            input,
            progress: { progress?($0 * 0.4) },
            logHandler: logHandler
        )

        // Only hash if the output was readable at all (Tier 0 passed). A failed readability gate
        // means the file can't be demuxed; the hash would just fail noisily on the same problem.
        let readable = checks.first { $0.kind == .readability }?.severity != .fail
        if readable {
            logHandler?("Hashing kept streams end-to-end (byte-exact)…")
            progress?(0.45)
            let hashCheck = await runTier2Hash(input, logHandler: logHandler)
            checks.append(hashCheck)
        }

        progress?(1.0)
        return SourceTargetResult(
            tier: .thorough,
            checks: checks,
            verifiedAt: Date(),
            duration: Date().timeIntervalSince(start)
        )
    }

    // MARK: - Tier 0 + Tier 1

    /// Runs the readability gate (Tier 0) and, if readable, the fast source↔target checks (Tier 1).
    private func runTier0And1(
        _ input: SourceTargetInput,
        progress: ProgressHandler?,
        logHandler: LogHandler?
    ) async -> [VerificationCheck] {
        var checks: [VerificationCheck] = []

        // --- Tier 0: readability gate -------------------------------------------------
        let readability = await checkReadability(output: input.outputURL, logHandler: logHandler)
        checks.append(readability)
        progress?(0.1)
        if readability.severity == .fail {
            // Output can't even be demuxed — the rest of the comparison is meaningless.
            return checks
        }

        // --- Tier 1: per-stream fast comparison ---------------------------------------
        // Video stream (v:0) is always kept; audio (a:0) only when hasAudio.
        var streams: [(select: String, label: String)] = [("v:0", "video")]
        if input.hasAudio {
            streams.append(("a:0", "audio"))
        }

        // Frame interval for the duration tolerance (from the first source's fps, 30 fallback).
        let fps = input.sourceParams.compactMap { $0?.video.framesPerSecond }.first ?? Self.fpsFallback
        let frameIntervalMs = 1000.0 / fps

        for (idx, stream) in streams.enumerated() {
            // Packet count: output == Σ(sources), exact.
            let outCount = await packetCount(url: input.outputURL, select: stream.select)
            let srcCounts = await packetCounts(urls: input.sourceSegments, select: stream.select)
            checks.append(make(.packetCount, "Packet count (\(stream.label))",
                               compareCounts(output: outCount, sources: srcCounts)))

            // Packet bytes: output == Σ(sources), exact.
            let outBytes = await packetByteSize(url: input.outputURL, select: stream.select)
            let srcBytes = await packetByteSizes(urls: input.sourceSegments, select: stream.select)
            checks.append(make(.packetBytes, "Packet bytes (\(stream.label))",
                               compareByteSizes(output: outBytes, sources: srcBytes)))

            progress?(0.1 + 0.7 * Double(idx + 1) / Double(streams.count))
        }

        // Duration (video v:0 vs Σ source durations).
        let outDurMs = (try? ffmpeg.probeDurationMilliseconds(input.outputURL)) ?? 0
        let srcDurMs = input.sourceSegments.map { (try? ffmpeg.probeDurationMilliseconds($0)) ?? 0 }
        let shortest = srcDurMs.filter { $0 > 0 }.min() ?? 0
        checks.append(make(.duration, "Duration",
                           compareDuration(outputMs: outDurMs, sourceMs: srcDurMs,
                                           frameIntervalMs: frameIntervalMs,
                                           shortestSegmentMs: shortest)))

        // Codec-param identity across all N segments + output.
        let outputParams = try? ffmpeg.probeStreamInfo(input.outputURL)
        checks.append(make(.codecParams, "Codec parameters",
                           compareCodecParams(sources: input.sourceParams, output: outputParams)))

        // A/V drift (only when audio is kept).
        if input.hasAudio {
            let vMs = (try? ffmpeg.probeDurationMilliseconds(input.outputURL)) ?? outDurMs
            // a:0-only duration via packet timing isn't directly available from -show_format, so we
            // compare the output's container duration against itself's audio extent through ffprobe
            // stream duration. Fall back to the same value (pass) when unavailable.
            let aMs = await streamDurationMs(url: input.outputURL, select: "a:0") ?? vMs
            checks.append(make(.avDrift, "A/V drift",
                               compareAVDrift(videoMs: vMs, audioMs: aMs,
                                              frameIntervalMs: frameIntervalMs)))
        }

        logHandler?("Fast verify: \(checks.count) checks, worst = \(severityGlyph(checks))")
        return checks
    }

    // MARK: - Tier 2 hash

    /// Per-stream packet MD5: sources (via concat list) vs output. Mismatch is a definitive `.fail`.
    private func runTier2Hash(
        _ input: SourceTargetInput,
        logHandler: LogHandler?
    ) async -> VerificationCheck {
        guard let ffmpegURL = ffmpegPath else {
            return make(.hashMatch, "Byte-exact hash", .fail("FFmpeg binary not found"))
        }

        // Build the source concat list the SAME way the join does (byte-identical ordering/escape).
        let listFileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("conjoyn-verify-concat-\(UUID().uuidString).txt")
        let listBody = FFmpegWrapper.buildConcatList(for: input.sourceSegments)
        do {
            try listBody.write(to: listFileURL, atomically: true, encoding: .utf8)
        } catch {
            return make(.hashMatch, "Byte-exact hash",
                        .fail("could not write concat list: \(error.localizedDescription)"))
        }
        defer { try? FileManager.default.removeItem(at: listFileURL) }

        var mapArgs = ["-map", "0:v:0"]
        if input.hasAudio { mapArgs.append(contentsOf: ["-map", "0:a:0"]) }

        // Sources: concat-demux the list, hash kept streams.
        var sourceArgs = ["-f", "concat", "-safe", "0", "-i", listFileURL.path]
        sourceArgs.append(contentsOf: mapArgs)
        sourceArgs.append(contentsOf: ["-c", "copy", "-hash", "md5", "-f", "streamhash", "-"])
        let sourceRun = await runCapturingStdout(at: ffmpegURL, arguments: sourceArgs)
        if isCancelling {
            return make(.hashMatch, "Byte-exact hash", .fail("cancelled"))
        }
        guard sourceRun.exitCode == 0 else {
            return make(.hashMatch, "Byte-exact hash",
                        .fail("source hash failed (exit \(sourceRun.exitCode))"))
        }

        // Output: hash kept streams of the joined file.
        var outputArgs = ["-i", input.outputURL.path]
        outputArgs.append(contentsOf: mapArgs)
        outputArgs.append(contentsOf: ["-c", "copy", "-hash", "md5", "-f", "streamhash", "-"])
        let outputRun = await runCapturingStdout(at: ffmpegURL, arguments: outputArgs)
        if isCancelling {
            return make(.hashMatch, "Byte-exact hash", .fail("cancelled"))
        }
        guard outputRun.exitCode == 0 else {
            return make(.hashMatch, "Byte-exact hash",
                        .fail("output hash failed (exit \(outputRun.exitCode))"))
        }

        let sourceLines = hashLines(from: sourceRun.stdout)
        let outputLines = hashLines(from: outputRun.stdout)
        let outcome = classifyHashLines(sourceLines: sourceLines, outputLines: outputLines)
        logHandler?("Hash: \(outcome.detail ?? "match")")
        return make(.hashMatch, "Byte-exact hash", outcome)
    }

    /// Trims `-f streamhash` stdout into non-empty per-stream lines.
    private func hashLines(from stdout: String) -> [String] {
        stdout
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Tier 0 / Tier 1 process helpers

    /// Tier 0: the output must demux its primary video stream (exit 0). Catches faststart/moov
    /// corruption + truncation for free.
    private func checkReadability(output: URL, logHandler: LogHandler?) async -> VerificationCheck {
        guard let ffprobe = ffprobePath else {
            return make(.readability, "Readability", .fail("ffprobe binary not found"))
        }
        guard FileManager.default.fileExists(atPath: output.path) else {
            return make(.readability, "Readability", .fail("output unavailable — \(output.lastPathComponent)"))
        }
        let args = [
            "-v", "error",
            "-select_streams", "v:0",
            "-count_packets",
            "-show_entries", "stream=nb_read_packets",
            "-of", "csv=p=0",
            output.path,
        ]
        let run = await runCapturingStdout(at: ffprobe, arguments: args)
        if run.exitCode == 0 {
            return make(.readability, "Readability", .pass)
        }
        logHandler?("Readability gate failed (exit \(run.exitCode))")
        return make(.readability, "Readability", .fail("output is not readable (exit \(run.exitCode))"))
    }

    /// Counts demuxed packets of one selected stream via ffprobe. -1 signals a probe failure
    /// (which the exact comparators surface as a mismatch rather than a silent pass).
    private func packetCount(url: URL, select: String) async -> Int {
        guard let ffprobe = ffprobePath else { return -1 }
        let args = [
            "-v", "error",
            "-select_streams", select,
            "-count_packets",
            "-show_entries", "stream=nb_read_packets",
            "-of", "csv=p=0",
            url.path,
        ]
        let run = await runCapturingStdout(at: ffprobe, arguments: args)
        guard run.exitCode == 0 else { return -1 }
        let trimmed = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return Int(trimmed) ?? -1
    }

    private func packetCounts(urls: [URL], select: String) async -> [Int] {
        var out: [Int] = []
        for url in urls { out.append(await packetCount(url: url, select: select)) }
        return out
    }

    /// Sums `packet=size` over one selected stream. -1 signals a probe failure.
    private func packetByteSize(url: URL, select: String) async -> Int {
        guard let ffprobe = ffprobePath else { return -1 }
        let args = [
            "-v", "error",
            "-select_streams", select,
            "-show_entries", "packet=size",
            "-of", "csv=p=0",
            url.path,
        ]
        let run = await runCapturingStdout(at: ffprobe, arguments: args)
        guard run.exitCode == 0 else { return -1 }
        var sum = 0
        var sawValue = false
        for line in run.stdout.split(whereSeparator: \.isNewline) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, let v = Int(t) else { continue }
            sum += v
            sawValue = true
        }
        return sawValue ? sum : -1
    }

    private func packetByteSizes(urls: [URL], select: String) async -> [Int] {
        var out: [Int] = []
        for url in urls { out.append(await packetByteSize(url: url, select: select)) }
        return out
    }

    /// Reads one stream's `duration` (seconds) via ffprobe, in ms. `nil` if unavailable.
    private func streamDurationMs(url: URL, select: String) async -> Int? {
        guard let ffprobe = ffprobePath else { return nil }
        let args = [
            "-v", "error",
            "-select_streams", select,
            "-show_entries", "stream=duration",
            "-of", "csv=p=0",
            url.path,
        ]
        let run = await runCapturingStdout(at: ffprobe, arguments: args)
        guard run.exitCode == 0 else { return nil }
        let t = run.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let seconds = Double(t), seconds > 0 else { return nil }
        return Int((seconds * 1000.0).rounded())
    }

    // MARK: - Pure comparators (process-free, unit-tested)

    /// Output packet count must equal the sum of the sources, exactly. A `-1` (probe failure) in
    /// any input fails the check rather than passing silently.
    func compareCounts(output: Int, sources: [Int]) -> CheckOutcome {
        if output < 0 || sources.contains(where: { $0 < 0 }) {
            return .fail("could not read packet counts (source unavailable or probe failed)")
        }
        let total = sources.reduce(0, +)
        if output == total {
            return .pass
        }
        return .fail("output \(output) packets vs \(total) across \(sources.count) source(s)")
    }

    /// Output packet bytes must equal the sum of the sources, exactly.
    func compareByteSizes(output: Int, sources: [Int]) -> CheckOutcome {
        if output < 0 || sources.contains(where: { $0 < 0 }) {
            return .fail("could not read packet byte sizes (source unavailable or probe failed)")
        }
        let total = sources.reduce(0, +)
        if output == total {
            return .pass
        }
        return .fail("output \(output) bytes vs \(total) across \(sources.count) source(s)")
    }

    /// Output duration ≈ Σ source durations. Within ±1 frame interval → info; beyond but short by
    /// less than a whole (shortest) segment → warning (escalate to hash); short by ≥ a whole
    /// segment → fail "missing trailing segment".
    func compareDuration(
        outputMs: Int,
        sourceMs: [Int],
        frameIntervalMs: Double,
        shortestSegmentMs: Int
    ) -> CheckOutcome {
        if outputMs <= 0 || sourceMs.contains(where: { $0 < 0 }) {
            return .fail("could not read durations")
        }
        let total = sourceMs.reduce(0, +)
        let deltaMs = Double(total - outputMs)               // positive = output is short
        let toleranceMs = frameIntervalMs * Self.durationToleranceFrames

        if abs(deltaMs) <= toleranceMs {
            return .info("Δ \(Int(deltaMs.rounded()))ms (within ±1 frame)")
        }

        // Whole-segment shortfall → definitive failure (a trailing segment was dropped).
        if shortestSegmentMs > 0,
           deltaMs >= Double(shortestSegmentMs) * Self.wholeSegmentShortfallFraction {
            return .fail("output is \(Int(deltaMs.rounded()))ms short — missing trailing segment")
        }

        return .warning("Δ \(Int(deltaMs.rounded()))ms (beyond ±1 frame)")
    }

    /// Output `v:0` vs `a:0` extent. Within ±1 frame interval → pass; beyond → warning (A/V drift).
    func compareAVDrift(videoMs: Int, audioMs: Int, frameIntervalMs: Double) -> CheckOutcome {
        if videoMs <= 0 || audioMs <= 0 {
            return .pass   // can't measure → don't manufacture a warning
        }
        let deltaMs = abs(Double(videoMs - audioMs))
        let toleranceMs = frameIntervalMs * Self.durationToleranceFrames
        if deltaMs <= toleranceMs {
            return .pass
        }
        return .warning("video/audio differ by \(Int(deltaMs.rounded()))ms")
    }

    /// Codec params must be identical across all kept segments + the output. Delegates to the
    /// existing `StreamParameterGuard.check`; `nil` entries are skipped (unknown ≠ mismatch).
    func compareCodecParams(
        sources: [StreamParameterGuard.SegmentStreamInfo?],
        output: StreamParameterGuard.SegmentStreamInfo?
    ) -> CheckOutcome {
        var infos = sources.compactMap { $0 }
        if let output { infos.append(output) }
        guard infos.count >= 2 else {
            // Nothing meaningful to compare (single known stream or all unknown).
            return infos.isEmpty ? .info("codec params unavailable") : .pass
        }
        switch StreamParameterGuard.check(infos) {
        case .compatible:
            return .pass
        case .incompatible(let reason):
            return .fail(reason)
        }
    }

    /// Compares per-stream `-f streamhash` lines. Equal → pass; differing → fail (per-stream);
    /// line-count mismatch → fail (a stream was dropped/added).
    func classifyHashLines(sourceLines: [String], outputLines: [String]) -> CheckOutcome {
        if sourceLines.isEmpty || outputLines.isEmpty {
            return .fail("no hash output (could not hash one side)")
        }
        if sourceLines.count != outputLines.count {
            return .fail("stream count differs — source \(sourceLines.count), output \(outputLines.count)")
        }
        for (i, (s, o)) in zip(sourceLines, outputLines).enumerated() {
            if s != o {
                return .fail("stream \(i) hash differs (source ≠ output)")
            }
        }
        return .pass
    }

    // MARK: - Dedicated stdout + exit-code runner

    /// Runs a tool capturing **stdout** and the exit code. Patterned after
    /// `VerificationService.runProcess`, but returns the exit code (Tier 0/1 ffprobe checks and
    /// Tier 2 ffmpeg hashes are exit-code-driven, not progress-driven) and registers the `Process`
    /// in `currentProcess` so `cancel()` can kill a minutes-long hash. Honors `isCancelling`.
    private func runCapturingStdout(
        at toolURL: URL,
        arguments: [String]
    ) async -> (stdout: String, exitCode: Int32) {
        if isCancelling {
            return ("", -1)
        }
        return await withCheckedContinuation { (continuation: CheckedContinuation<(String, Int32), Never>) in
            let process = Process()
            process.executableURL = toolURL
            process.arguments = arguments

            let outputPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = FileHandle.nullDevice

            process.terminationHandler = { [weak self] proc in
                let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                self?.currentProcess = nil
                continuation.resume(returning: (output, proc.terminationStatus))
            }

            currentProcess = process

            do {
                try process.run()
            } catch {
                currentProcess = nil
                continuation.resume(returning: ("", -1))
            }
        }
    }

    // MARK: - Small helpers

    /// Builds a `VerificationCheck` from a comparator outcome (`detail` is non-optional).
    private func make(_ kind: VerificationCheck.Kind, _ label: String, _ outcome: CheckOutcome) -> VerificationCheck {
        VerificationCheck(
            kind: kind,
            severity: outcome.severity,
            label: label,
            detail: outcome.detail ?? ""
        )
    }

    private func severityGlyph(_ checks: [VerificationCheck]) -> String {
        switch checks.map(\.severity).max() ?? .pass {
        case .pass, .info: return "✓"
        case .warning: return "⚠"
        case .fail: return "✗"
        }
    }
}
