import Foundation

// MARK: - Progress Tracking

// Ported from P2toMXF (`Models/ProgressModels.swift`). Trimmed for the Wave-1 vertical slice
// to the types FFmpegWrapper needs: ProgressMetrics + ConversionStatus. The estimation models
// (ConversionEstimate, ConversionSpeedRecord, SlowSpeedWarning) come back with SpeedTracker.

/// Metrics for tracking conversion progress with detailed statistics
struct ProgressMetrics {
    /// Overall progress from 0.0 to 1.0
    var progress: Double = 0.0

    /// Current phase description (e.g., "Joining segment 3/10...")
    var phase: String = ""

    /// Current clip index being processed (1-based for display)
    var currentClipIndex: Int = 0

    /// Total number of clips to process
    var totalClips: Int = 0

    /// When the conversion started
    var startTime: Date?

    /// Elapsed time in seconds since startTime, measured at the given reference date.
    func elapsedSeconds(at referenceDate: Date) -> TimeInterval {
        guard let start = startTime else { return 0 }
        return referenceDate.timeIntervalSince(start)
    }

    /// Estimated time remaining in seconds, measured at the given reference date.
    /// Requires at least 5% progress before producing an estimate.
    func estimatedRemainingSeconds(at referenceDate: Date) -> TimeInterval? {
        guard progress > 0.05 else { return nil }
        let elapsed = elapsedSeconds(at: referenceDate)
        guard elapsed > 0 else { return nil }
        let totalEstimated = elapsed / progress
        return max(0, totalEstimated - elapsed)
    }

    /// Format elapsed time as MM:SS or HH:MM:SS at the given reference date.
    func formattedElapsed(at referenceDate: Date) -> String {
        formatTimeInterval(elapsedSeconds(at: referenceDate))
    }

    /// Format estimated remaining at the given reference date, if available.
    func formattedRemaining(at referenceDate: Date) -> String? {
        guard let remaining = estimatedRemainingSeconds(at: referenceDate) else { return nil }
        return formatTimeInterval(remaining)
    }

    /// FFmpeg-reported speed (e.g., "12.5x")
    var speed: String?

    /// FFmpeg-reported fps
    var fps: Double?

    /// FFmpeg-reported processed time (e.g., "00:01:23.45")
    var processedTime: String?

    /// FFmpeg-reported current frame number
    var currentFrame: Int?

    /// Total expected frames (if known)
    var totalFrames: Int?

    /// Format speed and fps for display
    var formattedSpeed: String? {
        if let speed = speed {
            return speed
        } else if let fps = fps {
            return String(format: "%.1f fps", fps)
        }
        return nil
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let totalSeconds = Int(interval)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let seconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// Status of a clip during conversion
enum ConversionStatus: Equatable {
    case pending
    case inProgress(progress: Double)
    case finalizing  // File move/cleanup phase after processing
    case completed
    case failed(error: String)

    var description: String {
        switch self {
        case .pending: return "Pending"
        case .inProgress(let progress): return "Joining \(Int(progress * 100))%"
        case .finalizing: return "Finalizing..."
        case .completed: return "Completed"
        case .failed(let error): return "Failed: \(error)"
        }
    }
}

/// Coarse "~N min" / "~Nh Nm" / "< 1 min" formatting for an estimated duration. Shared by the
/// pre-job `ConversionEstimate.formattedEstimate` and the live queue-total ETA in the footer, so
/// both read identically. Sub-minute collapses to "< 1 min" (a precise countdown is the row's job).
func formattedCoarseDuration(_ seconds: TimeInterval) -> String {
    if seconds < 60 {
        return "< 1 min"
    } else if seconds < 3600 {
        return "~\(Int(seconds / 60)) min"
    } else {
        let hours = Int(seconds / 3600)
        let mins = Int((seconds.truncatingRemainder(dividingBy: 3600)) / 60)
        return "~\(hours)h \(mins)m"
    }
}

// MARK: - Time Estimation Models (Wave 1, task 1.2)

// Appended for the SpeedTracker port (task 1.8). Ported from P2toMXF (`Models/ProgressModels.swift`)
// with one change: `ConversionSpeedRecord` drops `processingMode` (Conjoyn has a single join mode)
// and keeps `outputFormat` as `ConversionSettings.OutputContainer`.

/// Estimated time for a conversion job.
struct ConversionEstimate {
    let totalBytes: Int64
    let totalDurationSeconds: Double
    let clipCount: Int
    let estimatedSeconds: TimeInterval
    let speedMultiplier: Double       // e.g., 30.0 means 30x realtime
    let confidence: EstimateConfidence

    /// Formatted total size (e.g., "42.3 GB").
    var formattedSize: String {
        ByteCountFormatter.string(fromByteCount: totalBytes, countStyle: .file)
    }

    /// Formatted duration of source content (e.g., "1:23:45").
    var formattedSourceDuration: String {
        formatTimeInterval(totalDurationSeconds)
    }

    /// Formatted estimated time (e.g., "~3 min").
    var formattedEstimate: String {
        formattedCoarseDuration(estimatedSeconds)
    }

    /// Formatted speed (e.g., "30x realtime").
    var formattedSpeed: String {
        String(format: "%.0fx realtime", speedMultiplier)
    }

    private func formatTimeInterval(_ interval: TimeInterval) -> String {
        let hours = Int(interval) / 3600
        let minutes = (Int(interval) % 3600) / 60
        let seconds = Int(interval) % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
    }
}

/// Confidence level in the time estimate.
enum EstimateConfidence: String {
    case high = "Based on recent conversions"
    case medium = "Based on historical average"
    case low = "Using default estimate"

    var icon: String {
        switch self {
        case .high: return "checkmark.circle.fill"
        case .medium: return "circle.fill"
        case .low: return "questionmark.circle"
        }
    }
}

/// Record of a completed conversion for speed tracking.
struct ConversionSpeedRecord: Codable, Sendable {
    let date: Date
    let bytesProcessed: Int64
    let durationSeconds: TimeInterval
    let speedMultiplier: Double        // Realtime multiplier (e.g., 30.0 for 30x)
    let outputFormat: ConversionSettings.OutputContainer

    /// Throughput in bytes per second.
    var bytesPerSecond: Double {
        guard durationSeconds > 0 else { return 0 }
        return Double(bytesProcessed) / durationSeconds
    }
}

/// Slow speed warning threshold and data.
struct SlowSpeedWarning {
    let currentSpeed: Double          // Current realtime multiplier
    let expectedSpeed: Double         // Expected based on history
    let estimatedRemaining: TimeInterval
    let reason: SlowSpeedReason

    var message: String {
        switch reason {
        case .slowDisk:        return "Slow disk speed detected"
        case .externalDrive:   return "External drive may be slow"
        case .networkStorage:  return "Network storage latency"
        case .systemLoad:      return "High system activity"
        case .unknown:         return "Slower than expected"
        }
    }

    var formattedRemaining: String {
        if estimatedRemaining < 60 {
            return "< 1 min remaining"
        } else if estimatedRemaining < 3600 {
            let mins = Int(estimatedRemaining / 60)
            return "~\(mins) min remaining"
        } else {
            let hours = Int(estimatedRemaining / 3600)
            let mins = Int((estimatedRemaining.truncatingRemainder(dividingBy: 3600)) / 60)
            return "~\(hours)h \(mins)m remaining"
        }
    }
}

enum SlowSpeedReason {
    case slowDisk
    case externalDrive
    case networkStorage
    case systemLoad
    case unknown
}
