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
    @discardableResult
    func addJob(_ job: ConversionJob, autoStart: Bool = false) -> Bool {
        var finalJob = job

        // Pending jobs reserve names even before their files exist. This synchronous MainActor
        // funnel resolves against the queue and disk before appending, for GUI and watch jobs alike.
        let resolvedURL = resolveFilenameConflict(for: job.destinationURL)
        if resolvedURL != job.destinationURL {
            // Only the filename changes; retain job identity, overrides and directory bookmarks.
            finalJob.destinationURL = resolvedURL
            log("Renamed output to avoid conflict: \(resolvedURL.lastPathComponent)")
        }

        // Snapshot each source segment's filesystem identity (device, inode) now, while these are the
        // files the user / watch-folder actually selected. The join (`processConcatenateJob`) re-checks
        // it before running ffmpeg, so a card swap or file rotation in the gap between queueing and
        // joining fails loudly instead of silently joining the wrong bytes (cookbook #127). Captured
        // in this shared funnel so both the manual queue and the watch-folder feed are guarded.
        finalJob.captureSourceIdentities()

        jobs.append(finalJob)
        log("Added job: \(finalJob.displayName)")
        let persisted = saveQueue()

        if autoStart && !isProcessing {
            Task {
                await processQueue()
            }
        }
        return persisted
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

        switch jobs[index].status {
        case .failed, .cancelled: break
        case .pending where jobs[index].watchAdmissionRequiresStart == true:
            releaseWatchHolds(jobID: jobId)
            return
        default: return
        }

        // A prior attempt may have published its video before a late sidecar conflict. Keep that
        // complete file and its recorded URL; reserve another pair for this explicit retry.
        jobs[index].destinationURL = resolveFilenameConflict(
            for: jobs[index].destinationURL,
            includingSidecar: jobs[index].clips.contains { $0.srtURL != nil },
            excludingPlannedJobID: jobId)
        jobs[index].status = .pending
        if jobs[index].watchAdmissionPending != true { jobs[index].watchAdmissionRequiresStart = nil }
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
    func startQueue(automatic: Bool = false) {
        if !automatic { releaseWatchHolds() }
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

// All admission writes are synchronous on MainActor. There is no suspended retry that can
// survive Cancel/Remove/Clear: recovery obtains and rechecks the current job on every attempt.
extension QueueManager {
    func holdWatchAdmissions(entryID: UUID) {
        var changed = false
        for index in jobs.indices where jobs[index].watchIdentitySnapshot?.watchEntryID == entryID
            && jobs[index].watchAdmissionPending == true && jobs[index].status != .cancelled {
            jobs[index].watchAdmissionRequiresStart = true
            changed = true
        }
        if changed { saveQueue() }
    }

    func releaseWatchHolds(jobID: UUID? = nil) {
        let held = jobs.filter { (jobID == nil || $0.id == jobID)
            && $0.status == .pending && $0.watchAdmissionPending != true
            && $0.watchAdmissionRequiresStart == true }.map(\.id)
        for id in held { updateJob(id) { $0.watchAdmissionRequiresStart = nil } }
        if !held.isEmpty && !saveQueue() {
            for id in held { updateJob(id) { $0.watchAdmissionRequiresStart = true } }
        }
    }

    /// Queue first, ledger second, runnable marker last. A failed final save restores the
    /// in-memory gate; restart retries the idempotent ledger commit from its saved pending marker.
    @discardableResult
    func recoverWatchAdmission(_ id: UUID,
        commit: (WatchIdentitySnapshot) throws -> Void) -> Bool {
        guard let job = jobs.first(where: { $0.id == id }), job.watchAdmissionPending == true,
              job.status == .pending, let snapshot = job.watchIdentitySnapshot else { return false }
        guard saveQueue() else {
            updateJob(id) { $0.watchAdmissionError = "Queue save failed. Admission is waiting for storage recovery." }
            return false
        }
        guard jobs.contains(where: { $0.id == id && $0.status == .pending && $0.watchAdmissionPending == true }) else { return false }
        do { try commit(snapshot) }
        catch {
            updateJob(id) { $0.watchAdmissionError = "History save failed. Admission is waiting for storage recovery: \(error.localizedDescription)" }
            return false
        }
        guard let index = jobs.firstIndex(where: { $0.id == id && $0.status == .pending
            && $0.watchAdmissionPending == true }) else { return false }
        jobs[index].watchAdmissionPending = nil
        jobs[index].watchAdmissionError = nil
        guard saveQueue() else {
            jobs[index].watchAdmissionPending = true
            jobs[index].watchAdmissionError = "History saved; queue confirmation is waiting for storage recovery."
            return false
        }
        return true
    }
}
