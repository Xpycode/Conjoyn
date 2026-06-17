import Foundation
import SwiftUI
import IOKit
import IOKit.pwr_mgt

// MARK: - Queue Manager (Wave 1, task 1.7)

/// Manages a queue of DJI join jobs, executing them sequentially. Ported from P2toMXF
/// (`Services/QueueManager.swift` + `+Operations`/`+Processing`/`+Verification`) with these
/// DJI adaptations:
///
///   1. **Single join mode.** P2toMXF's `processingMode` (concatenate vs. individual) is gone —
///      every DJI job is one record group joined into one file — so the individual-mode paths
///      (`processIndividualJob`, `verifyIndividualJobOutputs`, the mode switch) are dropped.
///   2. **`mergeClips` drives the concat demuxer**, taking `[URL]` segments + `JoinMetadata`
///      (not P2's `(clips, settings)`); there is no BMX rewrap stage.
///   3. **Synchronous, injectable persistence.** The app-support folder is `Conjoyn` (was
///      `P2toMXF`), the save is synchronous (the file is tiny and only written at job boundaries,
///      which removes the detached-write lifetime race — same call made for `SpeedTracker`), and
///      the storage directory is injectable so tests round-trip against a temp dir instead of the
///      real `~/Library/Application Support/Conjoyn`.
///   4. **No `ReportGenerator`.** P2toMXF's report/checksum generation isn't part of v1.
@MainActor
final class QueueManager: ObservableObject {
    // MARK: - Static Formatters
    /// Cached DateFormatter for log timestamps (creating formatters is expensive).
    static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }()

    // MARK: - Shared Instance
    @MainActor static let shared = QueueManager()

    // MARK: - Published State
    @Published var jobs: [ConversionJob] = []
    @Published var isProcessing = false
    @Published var restoredJobCount: Int = 0

    /// Effective join throughput observed during the **current** batch — Σ(source bytes) ÷ Σ(wall-clock
    /// spanning join + staged move + verify) of jobs completed this run. Drives the whole-queue ETA so a
    /// run that starts slow (e.g. a cold external drive) honestly raises its estimate and converges as the
    /// drive warms up, instead of trusting the persisted steady-state `SpeedTracker` average. Both reset
    /// to zero at the start of each batch (`processQueue`).
    var sessionBytesDone: Int64 = 0
    var sessionSecondsDone: TimeInterval = 0

    /// Console log lines — stored as an array to enable efficient trimming.
    /// Use `consoleLog` for display (joins lines).
    private var consoleLines: [String] = []

    /// Maximum number of console lines to retain (prevents unbounded memory growth).
    private let maxConsoleLines = 5000

    /// Console log as a single string for display.
    var consoleLog: String {
        consoleLines.joined(separator: "\n")
    }

    // MARK: - Services
    let ffmpeg = FFmpegWrapper()
    let verificationService = VerificationService()
    let sourceTargetVerifier = SourceTargetVerifier()
    let speedTracker = SpeedTracker.shared
    var currentJobId: UUID?
    var currentVerificationJobId: UUID?
    var sleepAssertionID: IOPMAssertionID = 0
    var isSleepPrevented = false
    /// Tracks URLs that currently have active security-scoped access.
    var accessedSecurityScopedResources: Set<URL> = []
    /// Task handle for batch verification (supports structured cancellation).
    var verificationTask: Task<Void, Error>?
    @Published var isVerifying = false
    @Published var slowSpeedWarning: SlowSpeedWarning?
    @Published var currentJobEstimate: ConversionEstimate?
    /// Latest live progress metrics from FFmpeg for the active job (ffmpeg's `speed=` etc.). Fed by
    /// the `metricsHandler` during a join, cleared when no job is running. Drives the live speed
    /// readout in the queue row; `nil` between jobs and before the first metrics callback arrives.
    @Published var activeMetrics: ProgressMetrics?
    /// Error message when queue persistence fails (nil if no error). Displayed in the UI to warn
    /// users their queue may not survive app restarts.
    @Published var persistenceError: String?

    // MARK: - Persistence
    private static let queueFileName = "queue.json"

    /// URL for the queue persistence file (nil if persistence is unavailable). Gracefully degrades
    /// to an in-memory queue if the storage directory is inaccessible.
    var queueFileURL: URL?

    // MARK: - Init

    /// - Parameter storageDirectory: Directory to persist `queue.json` in. `nil` (the default, used
    ///   by `shared`) resolves to `~/Library/Application Support/Conjoyn`. Tests pass a temp dir so
    ///   the enqueue→persist→reload round-trip never touches the real app-support file.
    init(storageDirectory: URL? = nil) {
        setupPersistence(storageDirectory: storageDirectory)
        loadQueue()
    }

    /// Sets up the persistence file URL if possible.
    private func setupPersistence(storageDirectory: URL?) {
        let appFolder: URL
        if let storageDirectory {
            appFolder = storageDirectory
        } else {
            guard let appSupport = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
                log("Warning: Application Support unavailable - queue will not persist")
                return
            }
            appFolder = appSupport.appendingPathComponent("Conjoyn", isDirectory: true)
        }

        do {
            try FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
            queueFileURL = appFolder.appendingPathComponent(Self.queueFileName)
        } catch {
            log("Warning: Cannot create app folder - queue will not persist: \(error.localizedDescription)")
        }
    }

    // MARK: - Computed Properties

    /// Number of jobs waiting to be processed.
    var pendingCount: Int {
        jobs.filter { $0.status == .pending }.count
    }

    /// Number of completed jobs.
    var completedCount: Int {
        jobs.filter { $0.status == .completed }.count
    }

    /// Number of failed jobs.
    var failedCount: Int {
        jobs.filter { if case .failed = $0.status { return true } else { return false } }.count
    }

    /// Number of jobs cancelled by **Stop** (distinct from `failed` — stopping is not an error).
    /// Used by the footer outcome bar to render a stopped-early queue as part-done / part-stopped
    /// rather than a full green "done".
    var cancelledCount: Int {
        jobs.filter { $0.status == .cancelled }.count
    }

    /// Of the **completed** (joined) jobs, how many fall into each verification tier. The footer
    /// outcome bar paints by tier so a joined-but-still-verifying file reads amber, not a premature
    /// green — `green = verified`, matching the per-job bar. `completedCount` (= "joined") is the sum
    /// of all three.
    var verifiedCount: Int { completedCount(inTier: .verified) }
    var awaitingVerificationCount: Int { completedCount(inTier: .working) }
    var verifyFailedCount: Int { completedCount(inTier: .failed) }

    private func completedCount(inTier tier: VerificationStatus.OutcomeTier) -> Int {
        jobs.filter { $0.status == .completed && $0.verificationStatus.outcomeTier == tier }.count
    }

    /// The currently active job (if any).
    var activeJob: ConversionJob? {
        jobs.first { $0.status == .active || $0.status == .preparing }
    }

    /// Overall progress (0.0 to 1.0) across all jobs.
    var overallProgress: Double {
        guard !jobs.isEmpty else { return 0 }
        let finishedJobs = jobs.filter { $0.status.isFinished }.count
        let activeProgress = activeJob?.progress ?? 0
        return (Double(finishedJobs) + activeProgress) / Double(jobs.count)
    }

    /// Summary text for the queue status.
    var statusSummary: String {
        if jobs.isEmpty {
            return "Queue empty"
        }
        if isProcessing, let active = activeJob {
            return "Processing: \(active.displayName)"
        }
        let pending = pendingCount
        if pending > 0 {
            return "\(pending) job\(pending == 1 ? "" : "s") waiting"
        }
        return "\(completedCount) completed, \(failedCount) failed"
    }

    /// Whether there are pending jobs that can be started.
    var hasPendingJobs: Bool {
        pendingCount > 0
    }

    // MARK: - Logging

    func log(_ message: String) {
        // Mirror every console message to the persistent diagnostic log so a bug report filed after
        // a quit/relaunch still has the events on disk (the console buffer below is in-memory only).
        DiagnosticLogger.shared.log(message)

        let timestamp = Self.timestampFormatter.string(from: Date())
        let line = "[\(timestamp)] \(message)"
        consoleLines.append(line)

        // Trim old lines if over limit (keep the last `maxConsoleLines`).
        if consoleLines.count > maxConsoleLines {
            let excess = consoleLines.count - maxConsoleLines
            consoleLines.removeFirst(excess)
        }

        // Trigger UI update.
        objectWillChange.send()
    }

    func clearConsole() {
        consoleLines.removeAll()
        objectWillChange.send()
    }

    // MARK: - Persistence

    /// Saves the current queue to disk. Synchronous: `queue.json` is small and this only runs at
    /// job boundaries, so a blocking atomic write costs nothing and — unlike P2toMXF's detached
    /// background write — can't outlive its caller and race app exit (or, in tests, temp-dir
    /// cleanup). No-op if persistence is unavailable.
    func saveQueue() {
        guard let fileURL = queueFileURL else { return }

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601

            let data = try encoder.encode(jobs)
            try data.write(to: fileURL, options: .atomic)
            persistenceError = nil
        } catch {
            // Surface the error to the UI (only the first occurrence, to avoid spam).
            if persistenceError == nil {
                persistenceError = "Queue may not persist: \(error.localizedDescription)"
                log("Warning: Failed to save queue - \(error.localizedDescription)")
            }
        }
    }

    /// Loads the queue from disk (only pending and failed jobs). No-op if persistence is unavailable.
    private func loadQueue() {
        guard let fileURL = queueFileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601

            var loadedJobs = try decoder.decode([ConversionJob].self, from: data)

            // Restore unfinished jobs (pending/active/preparing) plus failed; drop completed and
            // cancelled. **Divergence from P2toMXF:** its filter kept only pending/failed, which ran
            // *before* the "reset active→pending" loop below — making that loop dead code and
            // silently dropping a job interrupted mid-join. Keeping active/preparing here lets the
            // reset actually fire, so a crash-interrupted job comes back as a retryable pending job
            // (the documented intent).
            loadedJobs = loadedJobs.filter { job in
                switch job.status {
                case .pending, .active, .preparing, .failed: return true
                case .completed, .cancelled: return false
                }
            }

            // Reset any "active"/"preparing" states to pending, and resolve bookmarks.
            for index in loadedJobs.indices {
                if loadedJobs[index].status == .active || loadedJobs[index].status == .preparing {
                    loadedJobs[index].status = .pending
                    loadedJobs[index].progress = 0
                }

                // Try to resolve security-scoped bookmarks (nil data resolves to the stored path).
                if loadedJobs[index].sourceBookmarkData != nil {
                    if loadedJobs[index].resolveSourceBookmark() == nil {
                        loadedJobs[index].status = .failed("Cannot access source folder (permission lost)")
                        log("Job '\(loadedJobs[index].displayName)' failed: Cannot access source folder")
                    }
                }
                if loadedJobs[index].outputBookmarkData != nil {
                    if loadedJobs[index].resolveOutputBookmark() == nil {
                        loadedJobs[index].status = .failed("Cannot access output folder (permission lost)")
                        log("Job '\(loadedJobs[index].displayName)' failed: Cannot access output folder")
                    }
                }
            }

            jobs = loadedJobs
            restoredJobCount = jobs.filter { $0.status == .pending }.count

            if !jobs.isEmpty {
                let pending = jobs.filter { $0.status == .pending }.count
                let failed = jobs.filter { if case .failed = $0.status { return true } else { return false } }.count
                if failed > 0 {
                    log("Restored \(pending) job(s), \(failed) failed (permission issues)")
                } else {
                    log("Restored \(jobs.count) job(s) from previous session")
                }
            }
        } catch {
            #if DEBUG
            print("Failed to load queue: \(error)")
            #endif
        }
    }

    // MARK: - Sleep Prevention

    /// Prevents the system from idle-sleeping while processing.
    func preventSleep() {
        guard !isSleepPrevented else { return }

        let reason = "conjoyn is joining video files" as CFString
        let result = IOPMAssertionCreateWithName(
            kIOPMAssertionTypeNoIdleSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &sleepAssertionID
        )

        if result == kIOReturnSuccess {
            isSleepPrevented = true
            log("Sleep prevention enabled")
        }
    }

    /// Allows the system to sleep again.
    func allowSleep() {
        guard isSleepPrevented else { return }

        IOPMAssertionRelease(sleepAssertionID)
        isSleepPrevented = false
        sleepAssertionID = 0
        log("Sleep prevention disabled")
    }

    // MARK: - Security-Scoped Resource Management

    /// Result of attempting to start security-scoped access.
    enum AccessResult {
        case newlyGranted    // We started access — caller SHOULD stop it.
        case alreadyActive   // Someone else started it — caller should NOT stop.
        case denied          // Access failed.

        var wasGranted: Bool {
            self != .denied
        }
    }

    /// Starts accessing a security-scoped resource if not already accessed.
    /// - Returns: An `AccessResult` indicating whether the caller should stop access later.
    func startAccessingIfNeeded(_ url: URL) -> AccessResult {
        // Normalize the URL to avoid duplicates with different representations.
        let standardizedURL = url.standardizedFileURL

        // Already accessing (someone else started it)?
        if accessedSecurityScopedResources.contains(standardizedURL) {
            return .alreadyActive
        }

        // Try to start new access.
        if standardizedURL.startAccessingSecurityScopedResource() {
            accessedSecurityScopedResources.insert(standardizedURL)
            return .newlyGranted
        }

        return .denied
    }

    /// Stops accessing a specific security-scoped resource.
    func stopAccessingIfNeeded(_ url: URL) {
        let standardizedURL = url.standardizedFileURL
        if accessedSecurityScopedResources.contains(standardizedURL) {
            standardizedURL.stopAccessingSecurityScopedResource()
            accessedSecurityScopedResources.remove(standardizedURL)
        }
    }

    /// Stops accessing all currently accessed security-scoped resources.
    func stopAccessingAllResources() {
        for url in accessedSecurityScopedResources {
            url.stopAccessingSecurityScopedResource()
        }
        accessedSecurityScopedResources.removeAll()
    }

    // MARK: - Filename Conflict Resolution

    /// Checks whether a filename conflicts with any existing or queued outputs.
    private func isFilenameConflicting(_ url: URL) -> Bool {
        let path = url.path

        // Check all job destinations (any state).
        for job in jobs {
            if job.destinationURL.path == path {
                return true
            }
            // Also check actual output files (may have been renamed during conversion).
            if job.actualOutputURLs.contains(where: { $0.path == path }) {
                return true
            }
        }

        // Check the filesystem.
        return FileManager.default.fileExists(atPath: path)
    }

    /// Resolves filename conflicts by appending a counter (`Output.mp4` → `Output (1).mp4`).
    func resolveFilenameConflict(for url: URL) -> URL {
        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var finalURL = url
        var counter = 1

        while isFilenameConflicting(finalURL) {
            let newFilename = "\(filename) (\(counter)).\(ext)"
            finalURL = directory.appendingPathComponent(newFilename)
            counter += 1
        }

        return finalURL
    }

    // MARK: - Output-folder ↔ queue clarity

    /// Robust directory comparison for the output-folder-vs-queue feature. Returns `false` when
    /// either URL is `nil`; otherwise compares fully-resolved, standardized paths
    /// **case-insensitively** (macOS's default filesystem is case-insensitive — matching
    /// `RenamePatternEngine.uniqueStem`). Folded into one helper so the Part A per-row ⚠ badge and
    /// the Part B change-detection can't drift apart (URL directory equality is finicky — cookbook
    /// #52).
    static func directoriesDiffer(_ a: URL?, _ b: URL?) -> Bool {
        guard let a, let b else { return false }
        let pa = a.resolvingSymlinksInPath().standardizedFileURL.path
        let pb = b.resolvingSymlinksInPath().standardizedFileURL.path
        return pa.caseInsensitiveCompare(pb) != .orderedSame
    }

    /// Re-points every `.pending` job's output into `newFolder`, **preserving each job's filename
    /// stem** and re-resolving collisions. Only `.pending` jobs move — `.active`/`.preparing` are in
    /// flight and finished jobs are immutable, so their destinations are seeded as already-taken and
    /// never clobbered. The `.SRT` sidecar follows automatically (its path is derived from
    /// `destinationURL` at process time). Each moved job's `outputBookmarkData` is refreshed for the
    /// new directory so a stale security-scoped bookmark can't keep pointing at the old folder.
    func reassignPendingDestinations(to newFolder: URL) {
        // Seed "taken" with destinations that are NOT up for grabs — non-pending jobs' planned and
        // actual outputs — so a re-pointed job can never collide with a path already committed to.
        var taken = Set<String>()
        for job in jobs where job.status != .pending {
            taken.insert(job.destinationURL.path.lowercased())
            for url in job.actualOutputURLs { taken.insert(url.path.lowercased()) }
        }

        // One fresh directory bookmark for the new folder, reused across all moved jobs.
        let refreshedBookmark = try? newFolder.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil
        )

        var moved = 0
        for index in jobs.indices where jobs[index].status == .pending {
            let stem = jobs[index].destinationURL.lastPathComponent
            let resolved = uniqueDestination(
                newFolder.appendingPathComponent(stem), taken: &taken
            )
            jobs[index].destinationURL = resolved
            jobs[index].outputBookmarkData = refreshedBookmark
            moved += 1
        }

        guard moved > 0 else { return }
        saveQueue()
        log("Re-pointed \(moved) pending job\(moved == 1 ? "" : "s") to \(newFolder.path)")
    }

    /// Picks a non-colliding URL for `url`, appending ` (n)` before the extension until the path is
    /// free of both `taken` (lowercased full paths) and any on-disk file. Records the chosen path in
    /// `taken`. Mirrors `resolveFilenameConflict`'s `Output (1).mp4` style for batch reassignment.
    private func uniqueDestination(_ url: URL, taken: inout Set<String>) -> URL {
        let directory = url.deletingLastPathComponent()
        let filename = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension

        var finalURL = url
        var counter = 1
        while taken.contains(finalURL.path.lowercased())
                || FileManager.default.fileExists(atPath: finalURL.path) {
            finalURL = directory.appendingPathComponent("\(filename) (\(counter)).\(ext)")
            counter += 1
        }
        taken.insert(finalURL.path.lowercased())
        return finalURL
    }

    // MARK: - Safe Job Lookup

    /// Safely updates a job property by looking up the current index by ID.
    /// - Returns: `false` if the job is no longer in the array.
    @discardableResult
    func updateJob(_ jobId: UUID, _ update: (inout ConversionJob) -> Void) -> Bool {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return false }
        update(&jobs[index])
        return true
    }

    /// Returns the current index for a job ID, or `nil` if removed.
    func jobIndex(for jobId: UUID) -> Int? {
        jobs.firstIndex(where: { $0.id == jobId })
    }
}
