import Foundation

// MARK: - Queue Operations (Wave 1, task 1.7)

/// Add / remove / retry / cancel queue management. Ported from P2toMXF
/// (`Services/QueueManager+Operations.swift`) with DJI renames (`cardName`→`folderName`,
/// `cardPath`→`sourceFolderURL`) and using `DJIClip` segments.
extension QueueManager {

    // MARK: - Queue Management

    /// Adds a job to the queue (does NOT auto-start unless requested).
    /// - Parameters:
    ///   - job: The conversion job to add.
    ///   - autoStart: If true, immediately starts processing (for a "Join Now" button).
    func addJob(_ job: ConversionJob, autoStart: Bool = false) {
        var finalJob = job

        // A DJI job's destination is always a file. Only resolve conflicts if a file already
        // exists there (skip if absent, or if something at that path is a directory).
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: job.destinationURL.path, isDirectory: &isDirectory)
        let shouldResolveConflict = exists && !isDirectory.boolValue

        if shouldResolveConflict {
            let resolvedURL = resolveFilenameConflict(for: job.destinationURL)

            if resolvedURL != job.destinationURL {
                // Rebuild the job with the resolved URL, preserving bookmark data.
                finalJob = ConversionJob(
                    folderName: job.folderName,
                    sourceFolderURL: job.sourceFolderURL,
                    clips: job.clips,
                    settings: job.settings,
                    destinationURL: resolvedURL,
                    sourceBookmarkData: job.sourceBookmarkData,
                    outputBookmarkData: job.outputBookmarkData
                )
                log("Renamed output to avoid conflict: \(resolvedURL.lastPathComponent)")
            }
        }

        jobs.append(finalJob)
        log("Added job: \(finalJob.displayName)")
        saveQueue()

        if autoStart && !isProcessing {
            Task {
                await processQueue()
            }
        }
    }

    /// Creates and adds a job from parameters with security-scoped bookmarks for queue persistence.
    func addJob(
        folderName: String,
        sourceFolderURL: URL,
        clips: [DJIClip],
        settings: ConversionSettings,
        destinationURL: URL,
        autoStart: Bool = false
    ) {
        let job = ConversionJob.withBookmarks(
            folderName: folderName,
            sourceFolderURL: sourceFolderURL,
            clips: clips,
            settings: settings,
            destinationURL: destinationURL
        )
        addJob(job, autoStart: autoStart)
    }

    /// Removes a job from the queue (only if not active/preparing).
    func removeJob(_ jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }),
              jobs[index].status != .active && jobs[index].status != .preparing else {
            return
        }
        let removed = jobs.remove(at: index)
        log("Removed job: \(removed.displayName)")
        saveQueue()
    }

    /// Removes all pending jobs. Used by the restore banner to discard jobs the user doesn't want
    /// to resume from the previous session. In-flight jobs are untouched.
    func clearPendingJobs() {
        jobs.removeAll { $0.status == .pending }
        saveQueue()
    }

    /// Clears all completed and failed jobs.
    func clearFinishedJobs() {
        jobs.removeAll { $0.status.isFinished }
        log("Cleared finished jobs")
        saveQueue()
    }

    /// Empties the queue, keeping only a job that is mid-write (`active`/`preparing`) so an in-flight
    /// ffmpeg run isn't yanked out from under the processor. The processing loop re-queries pending
    /// jobs each iteration, so removing the pending ones simply lets it finish the current job (if
    /// any) and stop. Pair with **Stop** first to abandon a running queue entirely.
    func clearAllJobs() {
        let kept = jobs.filter { $0.status == .active || $0.status == .preparing }
        let removed = jobs.count - kept.count
        guard removed > 0 else { return }
        jobs = kept
        log("Cleared \(removed) job\(removed == 1 ? "" : "s") from the queue")
        saveQueue()
    }

    /// Retries a failed or cancelled job by resetting its status to pending.
    func retryJob(_ jobId: UUID) {
        guard let index = jobs.firstIndex(where: { $0.id == jobId }) else { return }

        let status = jobs[index].status
        guard case .failed = status else {
            guard status == .cancelled else { return }
            // Allow retry for cancelled jobs too.
            jobs[index].status = .pending
            jobs[index].progress = 0
            log("Retrying job: \(jobs[index].displayName)")
            saveQueue()
            return
        }

        jobs[index].status = .pending
        jobs[index].progress = 0
        log("Retrying job: \(jobs[index].displayName)")
        saveQueue()
    }

    /// Cancels the currently active job.
    func cancelCurrentJob() {
        guard let jobId = currentJobId,
              let index = jobs.firstIndex(where: { $0.id == jobId }) else {
            return
        }

        ffmpeg.cancelConversion()
        jobs[index].status = .cancelled
        jobs[index].progress = 0
        log("Cancelled job: \(jobs[index].displayName)")
        saveQueue()
    }

    /// Cancels all pending jobs (marks as cancelled; doesn't remove).
    func cancelAllPending() {
        for index in jobs.indices where jobs[index].status == .pending {
            jobs[index].status = .cancelled
        }
        log("Cancelled all pending jobs")
        saveQueue()
    }

    /// Stops all queue processing — cancels the current job and all pending jobs.
    func stopAllProcessing() {
        if let jobId = currentJobId,
           let index = jobs.firstIndex(where: { $0.id == jobId }) {
            ffmpeg.cancelConversion()
            jobs[index].status = .cancelled
            jobs[index].progress = 0
            log("Cancelled active job: \(jobs[index].displayName)")
        }

        var pendingCount = 0
        for index in jobs.indices where jobs[index].status == .pending {
            jobs[index].status = .cancelled
            pendingCount += 1
        }
        if pendingCount > 0 {
            log("Cancelled \(pendingCount) pending job\(pendingCount == 1 ? "" : "s")")
        }

        saveQueue()
        log("=== All queue processing stopped ===")
    }

    /// Starts processing the queue (manual trigger).
    func startQueue() {
        guard !isProcessing, hasPendingJobs else { return }
        Task {
            await processQueue()
        }
    }

    /// Sets (or clears) the manual timecode override for a queued job.
    /// Session-only — intentionally does NOT call `saveQueue()` so the override is never
    /// persisted to `queue.json` and is lost when the app restarts (matching the model intent).
    func updateTimecodeOverride(for jobID: UUID, timecode: String?) {
        guard let idx = jobs.firstIndex(where: { $0.id == jobID }) else { return }
        jobs[idx].timecodeStringOverride = timecode
    }
}
