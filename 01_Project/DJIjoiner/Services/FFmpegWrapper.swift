import Foundation
import AppKit

// MARK: - FFmpeg Wrapper

/// Wrapper for FFmpeg operations. For DJI, joins self-contained MP4 segments with the
/// concat demuxer (`-c copy`) — no BMX rewrap stage (that was P2-only).
///
/// Ported from P2toMXF (`Services/FFmpegWrapper.swift`). This is the process core: launching
/// FFmpeg, streaming/parsing its stderr progress, and cancellation. The join argument-building
/// (`mergeClips`) lands later in `FFmpegWrapper+Conversion` (Wave 2, task 2.5).
///
/// Marked `final ... @unchecked Sendable`: all mutable state (`_currentProcess`, `_isCancelling`)
/// is guarded by `cancelLock`, so instances are safe to capture in the `@Sendable` pipe handlers.
final class FFmpegWrapper: @unchecked Sendable {

    // MARK: - Error Types

    enum FFmpegError: LocalizedError {
        case ffmpegNotFound
        case conversionFailed(String)
        case invalidInput(String)
        case cancelled  // User-initiated cancellation

        var errorDescription: String? {
            switch self {
            case .ffmpegNotFound:
                return "FFmpeg binary not found in app bundle. Please add ffmpeg to Resources/Helpers."
            case .conversionFailed(let msg):
                return "Conversion failed: \(msg)"
            case .invalidInput(let msg):
                return "Invalid input: \(msg)"
            case .cancelled:
                return "Conversion was cancelled"
            }
        }
    }

    // MARK: - Types

    /// Progress callback: (progress 0.0-1.0, current status message)
    typealias ProgressHandler = @Sendable (Double, String) -> Void
    /// Log callback for console output
    typealias LogHandler = @Sendable (String) -> Void
    /// Metrics callback for detailed progress info
    typealias MetricsHandler = @Sendable (ProgressMetrics) -> Void

    /// Parsed metrics from FFmpeg output
    struct FFmpegOutputMetrics {
        var frame: Int?
        var fps: Double?
        var speed: String?
        var time: String?
        var bitrate: String?
        var size: String?
    }

    // MARK: - Properties

    private var _currentProcess: Process?
    private let cancelLock = NSLock()
    private var _isCancelling = false

    /// Thread-safe access to the current process (read/written from multiple threads)
    private var currentProcess: Process? {
        get { cancelLock.withLock { _currentProcess } }
        set { cancelLock.withLock { _currentProcess = newValue } }
    }
    /// Thread-safe cancellation flag (accessed from main thread and process termination handler)
    var isCancelling: Bool {
        get { cancelLock.withLock { _isCancelling } }
        set { cancelLock.withLock { _isCancelling = newValue } }
    }
    let toolResolver = BundledToolResolver.shared

    /// Path to the bundled FFmpeg binary
    var ffmpegPath: URL? {
        toolResolver.path(for: .ffmpeg)
    }

    /// Checks if FFmpeg is available
    var isFFmpegAvailable: Bool {
        toolResolver.isAvailable(.ffmpeg)
    }

    // MARK: - Process Execution

    /// Thread-safe container for collecting FFmpeg stderr output with throttled progress updates.
    ///
    /// # Threading Contract
    /// This class is marked `@unchecked Sendable` because it manually implements
    /// thread-safety using `NSLock`:
    /// - `append(_:)` and `output` are synchronized via the internal lock
    /// - Safe to call from any thread or dispatch queue
    /// - All mutable state (`_outputParts`, `lastProgressUpdate`) is protected by the lock
    ///
    /// # Memory Efficiency
    /// Uses an array of string parts instead of repeated string concatenation.
    /// This avoids O(n²) memory allocation behavior during long conversions.
    ///
    /// **Warning:** Do not add properties without updating lock usage.
    final class OutputCollector: @unchecked Sendable {
        private let lock = NSLock()
        private var _outputParts: [String] = []
        private var _lastProgressUpdate = Date.distantPast

        /// Minimum interval between progress updates (10 updates/second = 0.1s)
        private let progressThrottleInterval: TimeInterval = 0.1

        init() {
            // Pre-allocate capacity to reduce reallocations
            _outputParts.reserveCapacity(1000)
        }

        func append(_ string: String) {
            lock.lock()
            _outputParts.append(string)
            lock.unlock()
        }

        var output: String {
            lock.lock()
            defer { lock.unlock() }
            return _outputParts.joined()
        }

        /// Returns true if enough time has passed since last progress update
        func shouldUpdateProgress() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            let now = Date()
            if now.timeIntervalSince(_lastProgressUpdate) >= progressThrottleInterval {
                _lastProgressUpdate = now
                return true
            }
            return false
        }
    }

    /// Runs FFmpeg with the given arguments
    /// - Parameters:
    ///   - ffmpegURL: Path to FFmpeg binary
    ///   - arguments: Command line arguments
    ///   - totalFrames: Optional total frame count for accurate progress (if known)
    ///   - progress: Progress callback (0.0-1.0, status message)
    ///   - logHandler: Log output callback
    ///   - metricsHandler: Optional callback for detailed metrics (speed, fps, etc.)
    func runFFmpeg(
        at ffmpegURL: URL,
        arguments: [String],
        totalFrames: Int? = nil,
        progress: @escaping ProgressHandler,
        logHandler: @escaping LogHandler,
        metricsHandler: MetricsHandler? = nil
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            let process = Process()
            process.executableURL = ffmpegURL
            process.arguments = arguments

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            let errorCollector = OutputCollector()

            // FFmpeg outputs progress info to stderr
            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if let str = String(data: data, encoding: .utf8), !str.isEmpty {
                    errorCollector.append(str)

                    // Log FFmpeg output (but not the repetitive progress lines)
                    let trimmed = str.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !trimmed.starts(with: "frame=") {
                        DispatchQueue.main.async {
                            logHandler("FFmpeg: \(trimmed)")
                        }
                    }

                    // Parse metrics from FFmpeg output
                    guard let self = self else { return }
                    let metrics = self.parseFFmpegOutput(str)

                    if let frame = metrics.frame {
                        // Throttle UI updates to 10/second to reduce main thread overhead
                        guard errorCollector.shouldUpdateProgress() else { return }

                        // Calculate progress based on frame count
                        let estimatedProgress: Double
                        if let total = totalFrames, total > 0 {
                            estimatedProgress = min(0.99, Double(frame) / Double(total))
                        } else {
                            // Fallback: estimate based on 1000 frames
                            estimatedProgress = min(0.9, Double(frame) / 1000.0)
                        }

                        // Build status message with metrics
                        var statusParts: [String] = []
                        if let total = totalFrames {
                            statusParts.append("Frame \(frame)/\(total)")
                        } else {
                            statusParts.append("Frame \(frame)")
                        }
                        if let speed = metrics.speed {
                            statusParts.append(speed)
                        } else if let fps = metrics.fps, fps > 0 {
                            statusParts.append(String(format: "%.0f fps", fps))
                        }

                        let statusMsg = statusParts.joined(separator: " • ")

                        DispatchQueue.main.async {
                            progress(estimatedProgress, statusMsg)

                            // Report detailed metrics if handler provided
                            if let handler = metricsHandler {
                                var progressMetrics = ProgressMetrics()
                                progressMetrics.progress = estimatedProgress
                                progressMetrics.phase = statusMsg
                                progressMetrics.currentFrame = frame
                                progressMetrics.totalFrames = totalFrames
                                progressMetrics.fps = metrics.fps
                                progressMetrics.speed = metrics.speed
                                progressMetrics.processedTime = metrics.time
                                handler(progressMetrics)
                            }
                        }
                    }
                }
            }

            process.terminationHandler = { [weak self] proc in
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil

                let wasCancelled = self?.isCancelling ?? false

                DispatchQueue.main.async {
                    logHandler("FFmpeg exit code: \(proc.terminationStatus)\(wasCancelled ? " (cancelled)" : "")")
                }

                if proc.terminationStatus == 0 {
                    continuation.resume()
                } else if wasCancelled {
                    // Process was terminated by user cancellation
                    continuation.resume(throwing: FFmpegError.cancelled)
                } else {
                    let errorOutput = errorCollector.output
                    DispatchQueue.main.async {
                        logHandler("FFmpeg error output: \(errorOutput)")
                    }
                    continuation.resume(throwing: FFmpegError.conversionFailed(errorOutput))
                }
            }

            self.currentProcess = process

            DispatchQueue.main.async {
                logHandler("Starting process: \(ffmpegURL.path)")
            }

            do {
                try process.run()
                DispatchQueue.main.async {
                    logHandler("Process started with PID: \(process.processIdentifier)")
                }
            } catch {
                // Clean up file handle handlers if process fails to start
                outputPipe.fileHandleForReading.readabilityHandler = nil
                errorPipe.fileHandleForReading.readabilityHandler = nil
                DispatchQueue.main.async {
                    logHandler("Failed to start process: \(error.localizedDescription)")
                }
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Cancellation

    /// Cancels any running conversion.
    /// Uses Process.terminate() for safe, targeted process termination.
    func cancelConversion() {
        isCancelling = true

        if let process = currentProcess, process.isRunning {
            // Use terminate() which safely sends SIGTERM to just this process.
            // Note: We avoid kill(-pgid, SIGTERM) because FFmpeg inherits our process group,
            // and killing the group would terminate the app itself!
            process.terminate()
        }

        currentProcess = nil
    }

    /// Resets cancellation state - call before starting new conversion
    func resetCancellation() {
        isCancelling = false
    }

    // MARK: - Output Parsing

    /// Parses FFmpeg progress output to extract metrics.
    /// FFmpeg outputs lines like:
    /// "frame=  123 fps= 24.5 q=28.0 size=   1234kB time=00:01:23.45 bitrate= 123.4kbits/s speed=12.3x"
    func parseFFmpegOutput(_ output: String) -> FFmpegOutputMetrics {
        var metrics = FFmpegOutputMetrics()

        // Parse frame=
        if let match = output.range(of: #"frame=\s*(\d+)"#, options: .regularExpression) {
            let frameStr = output[match].replacingOccurrences(of: "frame=", with: "").trimmingCharacters(in: .whitespaces)
            metrics.frame = Int(frameStr)
        }

        // Parse fps=
        if let match = output.range(of: #"fps=\s*([\d.]+)"#, options: .regularExpression) {
            let fpsStr = output[match].replacingOccurrences(of: "fps=", with: "").trimmingCharacters(in: .whitespaces)
            metrics.fps = Double(fpsStr)
        }

        // Parse speed= (e.g., "12.5x" or "N/A")
        if let match = output.range(of: #"speed=\s*([\d.]+x|N/A)"#, options: .regularExpression) {
            let speedStr = output[match].replacingOccurrences(of: "speed=", with: "").trimmingCharacters(in: .whitespaces)
            if speedStr != "N/A" {
                metrics.speed = speedStr
            }
        }

        // Parse time= (e.g., "00:01:23.45")
        if let match = output.range(of: #"time=\s*([\d:.]+)"#, options: .regularExpression) {
            let timeStr = output[match].replacingOccurrences(of: "time=", with: "").trimmingCharacters(in: .whitespaces)
            if !timeStr.starts(with: "-") {  // Ignore negative times
                metrics.time = timeStr
            }
        }

        // Parse bitrate=
        if let match = output.range(of: #"bitrate=\s*([\d.]+\s*\w+/s)"#, options: .regularExpression) {
            let bitrateStr = output[match].replacingOccurrences(of: "bitrate=", with: "").trimmingCharacters(in: .whitespaces)
            metrics.bitrate = bitrateStr
        }

        // Parse size=
        if let match = output.range(of: #"size=\s*([\d.]+\s*\w+)"#, options: .regularExpression) {
            let sizeStr = output[match].replacingOccurrences(of: "size=", with: "").trimmingCharacters(in: .whitespaces)
            metrics.size = sizeStr
        }

        return metrics
    }

    // MARK: - Diagnostics

    /// Gets FFmpeg version info for display
    func getVersionInfo() async -> String? {
        guard let ffmpeg = ffmpegPath else { return nil }

        let process = Process()
        process.executableURL = ffmpeg
        process.arguments = ["-version"]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: data, encoding: .utf8) {
                // Extract first line (version info)
                return output.components(separatedBy: .newlines).first
            }
        } catch {
            return nil
        }

        return nil
    }
}
