import Foundation

// MARK: - Queue Processing (Wave 1, task 1.7)

/// Sequential job execution, disk-space preflight, and slow-speed detection. Ported from P2toMXF
/// (`Services/QueueManager+Processing.swift`). DJI has a **single join mode**, so the
/// concatenate/individual switch and `processIndividualJob` are gone — every job runs the concat
/// demuxer via `ffmpeg.mergeClips`. Content duration sums each segment's exact `CMTime` directly
/// (no `totalDurationFrames / fps`), and there is no `ReportGenerator` step.
extension QueueManager {

    // MARK: - Queue Processing

    /// Main loop that processes jobs sequentially.
    func processQueue() async {
        guard !isProcessing else { return }
        isProcessing = true
        preventSleep()

        log("=== Queue processing started ===")

        while let nextJob = jobs.first(where: { $0.status == .pending }) {
            await processJob(nextJob)
            saveQueue()
        }

        allowSleep()
        isProcessing = false
        log("=== Queue processing complete ===")
        saveQueue()
    }

    /// Processes a single job: preflight, join, record speed.
    func processJob(_ job: ConversionJob) async {
        guard jobIndex(for: job.id) != nil else { return }
        let jobId = job.id

        currentJobId = jobId
        activeMetrics = nil
        updateJob(jobId) { j in
            j.status = .preparing
            j.progress = 0
            j.startedAt = Date()
        }

        // Calculate and store the estimate.
        currentJobEstimate = speedTracker.estimateJob(job)

        log("--- Starting job: \(job.displayName) ---")
        log("Folder: \(job.folderName)")
        log("Segments: \(job.clips.count)")
        log("Output: \(job.destinationURL.path)")
        if let estimate = currentJobEstimate {
            log("Estimated time: \(estimate.formattedEstimate) (\(estimate.formattedSpeed))")
        }

        // Resolve bookmarks and start security-scoped access.
        // IMPORTANT: only copy back the bookmark-related fields that `resolve*Bookmark()` may
        // mutate — never assign the whole struct, which would clobber `status`, `startedAt`, and
        // `progress` set by the preparing update above.
        var mutableJob = job
        let sourceURL: URL
        if let resolvedSourceURL = mutableJob.resolveSourceBookmark() {
            sourceURL = resolvedSourceURL
            updateJob(jobId) { j in
                j.sourceBookmarkData = mutableJob.sourceBookmarkData
                j.sourceFolderURL = mutableJob.sourceFolderURL
            }
        } else {
            sourceURL = job.sourceFolderURL
        }

        let outputDirURL: URL
        if let resolvedOutputURL = mutableJob.resolveOutputBookmark() {
            outputDirURL = resolvedOutputURL
            updateJob(jobId) { j in
                j.outputBookmarkData = mutableJob.outputBookmarkData
            }
        } else {
            outputDirURL = job.destinationURL.deletingLastPathComponent()
        }

        // Start security-scoped access with balanced tracking to prevent nested start/stop issues.
        let sourceAccess = startAccessingIfNeeded(sourceURL)
        let outputAccess = startAccessingIfNeeded(outputDirURL)

        // Fail fast with a clear error if access was denied.
        if sourceAccess == .denied {
            updateJob(jobId) { $0.status = .failed("Cannot access source folder - permission denied or bookmark expired") }
            log("FAILED: Cannot access source folder for \(job.displayName)")
            currentJobId = nil
            currentJobEstimate = nil
            return
        }

        if outputAccess == .denied {
            updateJob(jobId) { $0.status = .failed("Cannot access output folder - permission denied or bookmark expired") }
            log("FAILED: Cannot access output folder for \(job.displayName)")
            currentJobId = nil
            currentJobEstimate = nil
            return
        }

        // Only stop access we actually started (not access that was already active).
        defer {
            if sourceAccess == .newlyGranted {
                stopAccessingIfNeeded(sourceURL)
            }
            if outputAccess == .newlyGranted {
                stopAccessingIfNeeded(outputDirURL)
            }
        }

        // Preflight: fail fast if there isn't enough free space on the temp or output volume.
        let tempDir = TempDirectoryManager.shared.effectiveTempDirectory
        if let spaceError = preflightDiskSpaceError(for: job, tempDir: tempDir, outputDir: outputDirURL) {
            updateJob(jobId) { $0.status = .failed(spaceError) }
            log("FAILED preflight: \(spaceError)")
            currentJobId = nil
            currentJobEstimate = nil
            return
        }
        log("Preflight OK — \(preflightSummary(for: job, tempDir: tempDir, outputDir: outputDirURL))")

        let startTime = Date()
        let totalBytes = job.clips.reduce(Int64(0)) { $0 + $1.totalFileSize }
        let contentDuration = job.totalContentDurationSeconds

        do {
            updateJob(jobId) { $0.status = .active }

            let outputFiles = try await processConcatenateJob(job, jobId: jobId)

            // Store actual output URLs for verification (may differ due to conflict resolution).
            updateJob(jobId) { j in
                j.actualOutputURLs = outputFiles
                j.status = .completed
                j.progress = 1.0
            }

            // Auto source↔target verification (fast tier). This MUST run here — before the
            // enclosing scope exits — because the source security-scoped access opened above is
            // released by the `defer` at the top of `processJob` only once this function returns.
            // `await` suspends without unwinding the scope, so the `defer` has NOT fired yet and the
            // verifier inherits live source access (no re-resolve needed on the auto path). The fast
            // tier's ffprobe work runs inside the verifier's own off-main `Process`, so the main
            // actor isn't blocked; the `await` simply preserves strict job ordering.
            await autoVerifyJoin(jobId: jobId)

            // Record the join speed for future estimates.
            let elapsed = Date().timeIntervalSince(startTime)
            if elapsed > 0 {
                speedTracker.recordConversion(
                    bytesProcessed: totalBytes,
                    durationSeconds: elapsed,
                    contentDurationSeconds: contentDuration,
                    outputFormat: job.settings.outputContainer
                )

                let speedMultiplier = contentDuration / elapsed
                log("SUCCESS: \(job.displayName) - \(String(format: "%.1fx", speedMultiplier)) realtime")
            } else {
                log("SUCCESS: \(job.displayName)")
            }

        } catch {
            // Distinguish cancellation from an actual error.
            if let idx = jobIndex(for: jobId), jobs[idx].status == .cancelled {
                log("Job cancelled: \(job.displayName)")
            } else {
                updateJob(jobId) { $0.status = .failed(error.localizedDescription) }
                log("FAILED: \(job.displayName) - \(error.localizedDescription)")
            }
        }

        // Clear job-specific state.
        currentJobId = nil
        currentJobEstimate = nil
        slowSpeedWarning = nil
        activeMetrics = nil
    }

    /// Runs the concat join for a job (multiple segments → one file).
    /// - Returns: An array containing the single output file URL.
    func processConcatenateJob(_ job: ConversionJob, jobId: UUID) async throws -> [URL] {
        let totalBytes = job.clips.reduce(Int64(0)) { $0 + $1.totalFileSize }
        let totalDuration = job.totalContentDurationSeconds
        let segments = job.clips.map(\.videoURL)

        // Task 2.8: resolve the recording-start wall-clock for the group and stamp it on the output.
        // One resolved value drives both the `creation_time` date atoms and the `tmcd` start
        // timecode (never read from DJI's usually-empty source `tmcd`). The lossless `-c copy` path
        // and the param guard are untouched — FFmpeg writes the metadata during the mux.
        let metadata = resolveJoinMetadata(for: job)

        try await ffmpeg.mergeClips(
            segments,
            to: job.destinationURL,
            metadata: metadata,
            totalFrames: job.estimatedFrameCount,
            progress: { [weak self] progress, _ in
                Task { @MainActor in
                    self?.updateJob(jobId) { $0.progress = progress }
                }
            },
            logHandler: { [weak self] message in
                Task { @MainActor in
                    self?.log(message)
                }
            },
            metricsHandler: { [weak self] metrics in
                Task { @MainActor in
                    // Surface ffmpeg's live metrics (speed=) to the active queue row, then run the
                    // slow-speed check off the same sample.
                    self?.activeMetrics = metrics
                    self?.checkForSlowSpeed(
                        metrics: metrics,
                        totalBytes: totalBytes,
                        totalDuration: totalDuration,
                        outputPath: job.destinationURL
                    )
                }
            }
        )

        // Task 3.3: stitch the per-segment `.SRT` sidecars into one continuous, re-timed sidecar
        // next to the joined video. **Non-fatal:** the lossless video join has already succeeded, so
        // a telemetry-stitch failure is logged but never fails the job. The stitch probes each
        // segment's duration via ffprobe (synchronous + blocking), so it runs off the main actor.
        await stitchSRTSidecar(for: job)

        return [job.destinationURL]
    }

    /// Builds the `JoinMetadata` (creation_time + start timecode) for a job by resolving the
    /// recording-start wall-clock from its first segment (task 2.8). Honours the per-job toggles:
    /// `fixCreationDate` gates the date stamp, `preserveTimecode` gates the timecode. Logs the chosen
    /// provenance and any SRT↔filename inconsistency. Returns an empty `JoinMetadata` (stamps nothing)
    /// when no signal resolves or both toggles are off — the lossless join is unaffected either way.
    func resolveJoinMetadata(for job: ConversionJob) -> FFmpegWrapper.JoinMetadata {
        let wantsDate = job.settings.fixCreationDate
        let wantsTimecode = job.settings.preserveTimecode
        guard wantsDate || wantsTimecode, let firstClip = job.clips.first else {
            return FFmpegWrapper.JoinMetadata()
        }

        let resolution = RecordingStartResolver.resolve(
            forFirstSegment: firstClip,
            manualOverride: job.settings.dateOverride
        )

        guard let date = resolution.date else {
            log("Date/timecode: no usable signal (SRT/filename/creation_time/filesystem all absent) — stamping nothing")
            return FFmpegWrapper.JoinMetadata()
        }

        if let mismatch = resolution.mismatch {
            log(String(format: "Date/timecode: ⚠︎ SRT and filename disagree by %.0f s — using %@",
                       mismatch.deltaSeconds, resolution.provenance.label))
        }

        var creationTime: String?
        if wantsDate {
            creationTime = ISO8601Z.format(date)
        }

        var timecode: String?
        if wantsTimecode {
            // DJI records non-drop-frame; the param guard already proved every segment shares one
            // rate, so segment 1's probed fps is the group's. Fall back to 30 when unprobed.
            let fps = firstClip.streamInfo?.video.framesPerSecond ?? 30.0
            timecode = try? TimecodeFormatter.wallClockTimecode(
                for: date, frameRate: fps, isDropFrame: false
            )
        }

        log("Date/timecode resolved from \(resolution.provenance.label): "
            + "creation_time=\(creationTime ?? "—"), timecode=\(timecode ?? "—")")
        return FFmpegWrapper.JoinMetadata(creationTime: creationTime, timecode: timecode)
    }

    /// Stitches the job's per-segment `.SRT` sidecars into a single sidecar alongside the joined
    /// output (`<output-stem>.SRT`). No-op when no segment carries a sidecar. Never throws — any
    /// failure is logged and swallowed so a telemetry hiccup can't fail an otherwise-good join.
    private func stitchSRTSidecar(for job: ConversionJob) async {
        let srtPairs: [(video: URL, srt: URL?)] = job.clips.map { ($0.videoURL, $0.srtURL) }
        guard srtPairs.contains(where: { $0.srt != nil }) else { return }

        let ffmpeg = self.ffmpeg
        let logSink: @Sendable (String) -> Void = { [weak self] message in
            Task { @MainActor in self?.log(message) }
        }

        log("Stitching telemetry (.SRT) for \(job.displayName)…")
        do {
            let stitched = try await Task.detached(priority: .utility) {
                try ffmpeg.stitchSRT(segments: srtPairs, logHandler: logSink)
            }.value

            guard let stitched else { return }   // no sidecars survived parsing → nothing to write
            let srtOutputURL = job.destinationURL.deletingPathExtension().appendingPathExtension("SRT")
            try stitched.write(to: srtOutputURL, atomically: true, encoding: .utf8)
            log("SRT sidecar written: \(srtOutputURL.lastPathComponent)")
        } catch {
            log("SRT stitch skipped (telemetry only, video unaffected): \(error.localizedDescription)")
        }
    }

    // MARK: - Time Estimation

    /// Gets an estimate for a potential set of clips.
    func getEstimate(
        clips: [DJIClip],
        outputFormat: ConversionSettings.OutputContainer
    ) -> ConversionEstimate {
        speedTracker.estimateConversion(clips: clips, outputFormat: outputFormat)
    }

    /// Gets an estimate for a job.
    func getEstimate(for job: ConversionJob) -> ConversionEstimate {
        speedTracker.estimateJob(job)
    }

    /// Gets a total estimate for all pending jobs.
    func getTotalQueueEstimate() -> ConversionEstimate? {
        let pendingJobs = jobs.filter { $0.status == .pending }
        guard let firstJob = pendingJobs.first else { return nil }

        return speedTracker.estimateConversion(
            clips: pendingJobs.flatMap(\.clips),
            outputFormat: firstJob.settings.outputContainer
        )
    }

    /// Estimated seconds remaining for the **whole queue** at the given reference date: the active
    /// job's live time-remaining plus the historical estimate for every still-pending job. Returns
    /// `nil` when nothing is running so the footer readout stays hidden between batches.
    ///
    /// The active job uses the live `elapsed / progress` extrapolation (`ProgressMetrics`) once it's
    /// past 5%; before that it falls back to the historical `currentJobEstimate`. Pending jobs always
    /// use `getTotalQueueEstimate()` (SpeedTracker history). The split keeps the live countdown
    /// history-independent while still giving a whole-batch number on a fresh install.
    func remainingQueueSeconds(at referenceDate: Date) -> TimeInterval? {
        guard isProcessing else { return nil }

        var total: TimeInterval = 0

        if let active = jobs.first(where: { $0.id == currentJobId }) {
            let metrics = ProgressMetrics(progress: active.progress, startTime: active.startedAt)
            if let live = metrics.estimatedRemainingSeconds(at: referenceDate) {
                total += live
            } else if let estimate = currentJobEstimate {
                total += estimate.estimatedSeconds
            }
        }

        if let pending = getTotalQueueEstimate() {
            total += pending.estimatedSeconds
        }

        return total > 0 ? total : nil
    }

    /// Dismisses the slow-speed warning.
    func dismissSlowSpeedWarning() {
        slowSpeedWarning = nil
        speedTracker.clearSpeedWarning()
    }

    // MARK: - Preflight Disk Space Check

    /// Returns a human-readable error string if there isn't enough free space to run the job, or
    /// `nil` if it can safely start. Applies a 10% safety margin on top of the source size, and
    /// doubles the requirement when temp and output share one volume.
    func preflightDiskSpaceError(
        for job: ConversionJob,
        tempDir: URL,
        outputDir: URL
    ) -> String? {
        let requiredBase = job.clips.reduce(Int64(0)) { $0 + $1.totalFileSize }
        let requiredWithMargin = Int64(Double(requiredBase) * 1.10)

        let shareVolume = DiskSpace.sameVolume(tempDir, outputDir)

        if shareVolume {
            // Temp and output on the same volume — need 2× the required amount on that one disk.
            let combined = requiredWithMargin * 2
            guard let free = DiskSpace.availableCapacity(for: tempDir) else { return nil }
            if free < combined {
                let name = DiskSpace.volumeName(for: tempDir) ?? "the selected volume"
                return "Not enough space on \(name): \(DiskSpace.formatBytes(free)) free, " +
                    "~\(DiskSpace.formatBytes(combined)) required (temp + output on same volume). " +
                    "Choose a different temp folder in File → Temp Folder… to split the load."
            }
            return nil
        }

        // Separate volumes — check each independently.
        if let freeTemp = DiskSpace.availableCapacity(for: tempDir), freeTemp < requiredWithMargin {
            let name = DiskSpace.volumeName(for: tempDir) ?? "temp volume"
            return "Not enough space on \(name) (temp): \(DiskSpace.formatBytes(freeTemp)) free, " +
                "~\(DiskSpace.formatBytes(requiredWithMargin)) required. " +
                "Choose a different temp folder in File → Temp Folder…"
        }
        if let freeOut = DiskSpace.availableCapacity(for: outputDir), freeOut < requiredWithMargin {
            let name = DiskSpace.volumeName(for: outputDir) ?? "output volume"
            return "Not enough space on \(name) (output): \(DiskSpace.formatBytes(freeOut)) free, " +
                "~\(DiskSpace.formatBytes(requiredWithMargin)) required."
        }
        return nil
    }

    /// Human-readable summary of a preflight check's findings, logged on success. Includes volume
    /// names, free capacity, and the required-byte estimate (source size + 10% margin).
    func preflightSummary(
        for job: ConversionJob,
        tempDir: URL,
        outputDir: URL
    ) -> String {
        let requiredBase = job.clips.reduce(Int64(0)) { $0 + $1.totalFileSize }
        let requiredWithMargin = Int64(Double(requiredBase) * 1.10)
        let needStr = DiskSpace.formatBytes(requiredWithMargin)

        let tempName = DiskSpace.volumeName(for: tempDir) ?? "temp volume"
        let outName = DiskSpace.volumeName(for: outputDir) ?? "output volume"
        let tempFreeStr = DiskSpace.availableCapacity(for: tempDir).map(DiskSpace.formatBytes) ?? "unknown"
        let outFreeStr = DiskSpace.availableCapacity(for: outputDir).map(DiskSpace.formatBytes) ?? "unknown"

        if DiskSpace.sameVolume(tempDir, outputDir) {
            return "Temp: \(tempName) (\(tempFreeStr) free), Output: same volume; need ~\(needStr)"
        }
        return "Temp: \(tempName) (\(tempFreeStr) free), Output: \(outName) (\(outFreeStr) free); need ~\(needStr)"
    }

    // MARK: - Slow Speed Detection

    /// Checks the current join speed and sets a warning if it's significantly slow.
    /// - Parameters:
    ///   - metrics: Current progress metrics from FFmpeg.
    ///   - totalBytes: Total bytes being processed.
    ///   - totalDuration: Total content duration in seconds.
    ///   - outputPath: Output file path (for slow-speed reason detection).
    func checkForSlowSpeed(
        metrics: ProgressMetrics,
        totalBytes: Int64,
        totalDuration: Double,
        outputPath: URL
    ) {
        // Parse the speed multiplier from a string like "12.5x".
        guard let speedStr = metrics.speed,
              let speedValue = Double(speedStr.replacingOccurrences(of: "x", with: "")) else {
            return
        }

        // Calculate remaining content based on progress.
        let remainingProgress = 1.0 - metrics.progress
        let bytesRemaining = Int64(Double(totalBytes) * remainingProgress)
        let durationRemaining = totalDuration * remainingProgress

        // Only check after the initial 10% to avoid false positives during startup.
        guard metrics.progress > 0.1 else { return }

        if let warning = speedTracker.checkSpeed(
            currentSpeedMultiplier: speedValue,
            bytesRemaining: bytesRemaining,
            contentDurationRemaining: durationRemaining,
            outputPath: outputPath
        ) {
            slowSpeedWarning = warning
        } else {
            // Clear the warning if speed has recovered.
            slowSpeedWarning = nil
        }
    }
}
