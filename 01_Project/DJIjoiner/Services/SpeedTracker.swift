import Foundation

// MARK: - Speed Tracker (Wave 1, task 1.8)

/// Tracks historical join speeds and turns them into pre-flight time estimates, persisting the
/// last 50 records to disk so predictions sharpen over repeated use.
///
/// Ported from P2toMXF (`Services/SpeedTracker.swift`) with three DJI adaptations:
///   1. `processingMode` is dropped everywhere — DJIjoiner has a single join mode (concat `-c copy`),
///      so records/estimates filter on `outputFormat` only (matches `ConversionSpeedRecord`).
///   2. `estimateConversion` takes `[DJIClip]` and sums `durationInSeconds` directly. A DJI segment's
///      duration is an exact `CMTime`, so there's no edit-unit/frame-rate conversion (the P2 reference
///      had to divide `durationFrames` by `frameRateDouble`).
///   3. The persistence directory is **injectable** (`init(storageDirectory:)`) so tests run against a
///      temp dir and never touch the real `~/Library/Application Support/DJIjoiner` file. `shared`
///      keeps the production app-support path. The app-support folder name is `DJIjoiner` (was `P2toMXF`).
@MainActor
final class SpeedTracker: ObservableObject {
    // MARK: - Shared Instance
    static let shared = SpeedTracker()

    // MARK: - Published State
    @Published private(set) var records: [ConversionSpeedRecord] = []
    @Published private(set) var currentSpeedWarning: SlowSpeedWarning?

    // MARK: - Constants
    private static let maxRecords = 50  // Keep last 50 conversions
    private static let recordsFileName = "speed_records.json"

    /// Default speed multiplier when no history exists (conservative estimate).
    /// Concat `-c copy` is I/O-bound and typically far faster than realtime; 15x is intentionally low.
    private static let defaultSpeedMultiplier = 15.0  // 15x realtime

    /// Threshold below which we warn about slow speed (as fraction of expected).
    private static let slowSpeedThreshold = 0.3  // Warn if < 30% of expected speed

    // MARK: - Persistence

    /// Where speed records are read from / written to. `nil` only if the app-support directory
    /// couldn't be located (records then stay in-memory and silently aren't persisted).
    private let recordsFileURL: URL?

    // MARK: - Init

    /// - Parameter storageDirectory: Directory to persist `speed_records.json` in. `nil` (the default,
    ///   used by `shared`) resolves to `~/Library/Application Support/DJIjoiner`. Tests pass a temp dir.
    init(storageDirectory: URL? = nil) {
        let dir: URL?
        if let storageDirectory {
            dir = storageDirectory
        } else {
            dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("DJIjoiner", isDirectory: true)
        }

        if let dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.recordsFileURL = dir.appendingPathComponent(Self.recordsFileName)
        } else {
            self.recordsFileURL = nil
        }

        loadRecords()
    }

    // MARK: - Persistence Methods

    private func loadRecords() {
        guard let fileURL = recordsFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([ConversionSpeedRecord].self, from: data)
        } catch {
            #if DEBUG
            print("Failed to load speed records: \(error)")
            #endif
        }
    }

    /// Persists records synchronously. The file is tiny (≤50 records) and this runs only at job
    /// boundaries, so a blocking write costs nothing and — unlike a detached background write —
    /// can't outlive its caller and race app exit (or, in tests, the temp-dir cleanup).
    private func saveRecords() {
        guard let fileURL = recordsFileURL else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("Failed to save speed records: \(error)")
            #endif
        }
    }

    // MARK: - Record Tracking

    /// Records a completed join for future estimates.
    func recordConversion(
        bytesProcessed: Int64,
        durationSeconds: TimeInterval,
        contentDurationSeconds: Double,
        outputFormat: ConversionSettings.OutputContainer
    ) {
        guard durationSeconds > 0, contentDurationSeconds > 0 else { return }

        let speedMultiplier = contentDurationSeconds / durationSeconds

        let record = ConversionSpeedRecord(
            date: Date(),
            bytesProcessed: bytesProcessed,
            durationSeconds: durationSeconds,
            speedMultiplier: speedMultiplier,
            outputFormat: outputFormat
        )

        records.append(record)

        // Keep only recent records.
        if records.count > Self.maxRecords {
            records.removeFirst(records.count - Self.maxRecords)
        }

        saveRecords()
    }

    // MARK: - Estimation

    /// Generates a time estimate for a set of clips.
    func estimateConversion(
        clips: [DJIClip],
        outputFormat: ConversionSettings.OutputContainer
    ) -> ConversionEstimate {
        // Calculate totals. DJIClip duration is an exact CMTime → sum seconds directly.
        let totalBytes = clips.reduce(Int64(0)) { $0 + $1.totalFileSize }
        let totalDurationSeconds = clips.reduce(0.0) { $0 + $1.durationInSeconds }

        // Get speed estimate based on history.
        let (speedMultiplier, confidence) = getSpeedEstimate(outputFormat: outputFormat)

        // Calculate estimated time (guard against a zero/garbage multiplier).
        let safeMultiplier = speedMultiplier > 0 ? speedMultiplier : Self.defaultSpeedMultiplier
        let estimatedSeconds = totalDurationSeconds / safeMultiplier

        return ConversionEstimate(
            totalBytes: totalBytes,
            totalDurationSeconds: totalDurationSeconds,
            clipCount: clips.count,
            estimatedSeconds: estimatedSeconds,
            speedMultiplier: safeMultiplier,
            confidence: confidence
        )
    }

    /// Generates a time estimate for a job.
    func estimateJob(_ job: ConversionJob) -> ConversionEstimate {
        estimateConversion(
            clips: job.clips,
            outputFormat: job.settings.outputContainer
        )
    }

    /// Gets the expected speed multiplier based on history.
    private func getSpeedEstimate(
        outputFormat: ConversionSettings.OutputContainer
    ) -> (speed: Double, confidence: EstimateConfidence) {
        // Filter records by matching format from the last 7 days.
        let recentCutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        let matchingRecent = records.filter { record in
            record.date > recentCutoff &&
            record.outputFormat == outputFormat
        }

        if matchingRecent.count >= 3 {
            // High confidence: recent matching records.
            let avgSpeed = matchingRecent.map(\.speedMultiplier).reduce(0, +) / Double(matchingRecent.count)
            return (avgSpeed, .high)
        }

        // Fall back to all records with the same format.
        let matchingAll = records.filter { $0.outputFormat == outputFormat }

        if !matchingAll.isEmpty {
            // Medium confidence: historical matching records.
            let avgSpeed = matchingAll.map(\.speedMultiplier).reduce(0, +) / Double(matchingAll.count)
            return (avgSpeed, .medium)
        }

        // Fall back to any records.
        if !records.isEmpty {
            let avgSpeed = records.map(\.speedMultiplier).reduce(0, +) / Double(records.count)
            return (avgSpeed, .medium)
        }

        // No history: use default.
        return (Self.defaultSpeedMultiplier, .low)
    }

    // MARK: - Slow Speed Detection

    /// Checks if the current speed is below expected and generates a warning.
    func checkSpeed(
        currentSpeedMultiplier: Double,
        bytesRemaining: Int64,
        contentDurationRemaining: Double,
        outputPath: URL
    ) -> SlowSpeedWarning? {
        let expectedSpeed = getAverageSpeed()

        // Only warn if significantly slower than expected.
        guard currentSpeedMultiplier < expectedSpeed * Self.slowSpeedThreshold else {
            currentSpeedWarning = nil
            return nil
        }

        // Estimate remaining time at current speed (guard against divide-by-zero).
        let estimatedRemaining = currentSpeedMultiplier > 0
            ? contentDurationRemaining / currentSpeedMultiplier
            : 0

        // Try to determine the reason.
        let reason = detectSlowSpeedReason(outputPath: outputPath)

        let warning = SlowSpeedWarning(
            currentSpeed: currentSpeedMultiplier,
            expectedSpeed: expectedSpeed,
            estimatedRemaining: estimatedRemaining,
            reason: reason
        )

        currentSpeedWarning = warning
        return warning
    }

    /// Clears any active slow speed warning.
    func clearSpeedWarning() {
        currentSpeedWarning = nil
    }

    /// Gets the average speed from all records.
    private func getAverageSpeed() -> Double {
        guard !records.isEmpty else { return Self.defaultSpeedMultiplier }
        return records.map(\.speedMultiplier).reduce(0, +) / Double(records.count)
    }

    /// Attempts to determine why speed is slow using volume APIs.
    private func detectSlowSpeedReason(outputPath: URL) -> SlowSpeedReason {
        // Use URL resource values for reliable volume detection.
        do {
            let resourceValues = try outputPath.resourceValues(forKeys: [
                .volumeIsLocalKey,
                .volumeIsRemovableKey,
                .volumeIsInternalKey
            ])

            // Network storage: volume is not local.
            if resourceValues.volumeIsLocal == false {
                return .networkStorage
            }

            // External drive: removable or not internal.
            if resourceValues.volumeIsRemovable == true ||
               resourceValues.volumeIsInternal == false {
                return .externalDrive
            }
        } catch {
            // Fall back to path-based heuristics if resource values are unavailable.
            let path = outputPath.path

            if path.hasPrefix("/Volumes/") {
                let volumeName = outputPath.pathComponents.dropFirst(2).first ?? ""
                if isNetworkVolume(named: volumeName) {
                    return .networkStorage
                }
                return .externalDrive
            }
        }

        return .unknown
    }

    /// Checks if a volume appears to be network storage.
    private func isNetworkVolume(named volumeName: String) -> Bool {
        // Common network volume indicators.
        let networkPatterns = ["smb", "nfs", "afp", "server", "nas", "share"]
        let lowercaseName = volumeName.lowercased()

        for pattern in networkPatterns where lowercaseName.contains(pattern) {
            return true
        }

        // Check mount type using statfs.
        let volumePath = "/Volumes/\(volumeName)"
        var statInfo = statfs()
        if statfs(volumePath, &statInfo) == 0 {
            let fsType = withUnsafePointer(to: &statInfo.f_fstypename) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MFSTYPENAMELEN)) {
                    String(cString: $0)
                }
            }
            let networkTypes = ["smbfs", "nfs", "afpfs", "webdav"]
            if networkTypes.contains(fsType.lowercased()) {
                return true
            }
        }

        return false
    }

    // MARK: - Statistics

    /// Average throughput in MB/s from all records.
    var averageThroughputMBps: Double? {
        guard !records.isEmpty else { return nil }
        let totalBytes = records.reduce(Int64(0)) { $0 + $1.bytesProcessed }
        let totalSeconds = records.reduce(0.0) { $0 + $1.durationSeconds }
        guard totalSeconds > 0 else { return nil }
        return Double(totalBytes) / totalSeconds / (1024 * 1024)
    }

    /// Clears all historical records.
    func clearHistory() {
        records.removeAll()
        saveRecords()
    }
}
