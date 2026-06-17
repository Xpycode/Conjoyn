import Foundation

// MARK: - Queue Verification (Wave 1, task 1.7)

/// Output verification for completed jobs. Ported from P2toMXF
/// (`Services/QueueManager+Verification.swift`). A DJI job always produces exactly **one** output
/// file (single join mode), so P2toMXF's per-clip `verifyIndividualJobOutputs` and the
/// directory-search fallback (`findMatchingOutputFile`) are dropped — verification targets the one
/// joined file directly.
extension QueueManager {

    // MARK: - Verification

    /// Number of completed jobs still pending verification.
    var unverifiedCompletedCount: Int {
        jobs.filter { $0.status == .completed && $0.verificationStatus == .unverified }.count
    }

    /// Verifies a completed job.
    /// - Parameters:
    ///   - jobId: The job to verify.
    ///   - mode: Quick or Full verification.
    func verifyJob(_ jobId: UUID, mode: VerificationMode) {
        guard let idx = jobIndex(for: jobId),
              jobs[idx].status == .completed else {
            return
        }

        Task {
            await performVerification(jobId: jobId, mode: mode)
        }
    }

    /// Verifies all completed-but-unverified jobs.
    func verifyAllCompleted(mode: VerificationMode) {
        let unverifiedJobIds = jobs.filter {
            $0.status == .completed && $0.verificationStatus == .unverified
        }.map(\.id)

        guard !unverifiedJobIds.isEmpty else { return }

        verificationTask = Task {
            for jobId in unverifiedJobIds {
                // Structured cancellation instead of a manual flag.
                try Task.checkCancellation()
                await performVerification(jobId: jobId, mode: mode)
            }
        }
    }

    /// Performs verification on a single job's output file.
    func performVerification(jobId: UUID, mode: VerificationMode) async {
        guard let idx = jobIndex(for: jobId) else { return }

        let job = jobs[idx]
        currentVerificationJobId = job.id
        isVerifying = true
        updateJob(jobId) { j in
            j.verificationStatus = .verifying
            j.verificationProgress = 0
        }

        log("--- Verifying: \(job.displayName) (\(mode.rawValue)) ---")

        do {
            // A DJI job has exactly one output file. Prefer the recorded actual URL (handles
            // conflict-resolution renames); fall back to the planned destination.
            let fileURL = job.actualOutputURLs.first ?? job.destinationURL

            let result = try await verificationService.verify(
                fileURL: fileURL,
                mode: mode,
                expectedFrames: job.estimatedFrameCount,
                progress: { [weak self] progress, _ in
                    Task { @MainActor in
                        self?.updateJob(jobId) { $0.verificationProgress = progress }
                    }
                },
                logHandler: { [weak self] message in
                    Task { @MainActor in
                        self?.log(message)
                    }
                }
            )

            updateJob(jobId) { j in
                j.verificationResult = result
                j.verificationStatus = result.passed ? .verified : .failed(result.errorMessage ?? "Unknown error")
            }

        } catch VerificationService.VerificationError.cancelled {
            updateJob(jobId) { j in
                j.verificationStatus = .unverified
                j.verificationProgress = 0
            }
            log("Verification cancelled")
        } catch {
            updateJob(jobId) { $0.verificationStatus = .failed(error.localizedDescription) }
            log("Verification failed: \(error.localizedDescription)")
        }

        currentVerificationJobId = nil
        isVerifying = jobs.contains { $0.verificationStatus == .verifying }
        saveQueue()
    }

    /// Cancels the current verification.
    func cancelVerification() {
        // Cancel the batch verification task (structured cancellation).
        verificationTask?.cancel()
        verificationTask = nil
        // Cancel the active source↔target subprocess (kills a long Tier-2 hash mid-flight). The
        // old decode-only `verificationService` is now unwired, but cancelling it is harmless and
        // keeps any stray decode-only run from outliving this call.
        sourceTargetVerifier.cancel()
        verificationService.cancel()
        if let jobId = currentVerificationJobId {
            updateJob(jobId) { j in
                j.verificationStatus = .unverified
                j.verificationProgress = 0
            }
        }
        isVerifying = false
    }

    // MARK: - Source↔Target Verification (true source-vs-output comparison)

    /// Auto fast-verify, called from `processJob` immediately after a join completes — while the
    /// source's security-scoped access is still live (see `QueueManager+Processing`). Runs Tier 0+1
    /// (container-index comparison); if anything is worse than informational (`hasWarning ||
    /// !passed`) it auto-escalates to the byte-exact Tier-2 hash.
    ///
    /// Runs **awaited inline** so jobs verify in strict completion order. The heavy ffprobe work
    /// happens inside the verifier's own off-main `Process`, so the main actor isn't blocked during
    /// the `await`. If concurrent verification (verify job N+1 while still hashing job N) is ever
    /// wanted, swap the `await` for an unstructured `Task { await … }` — but that loses ordering and
    /// would need the manual re-resolve path (the auto path relies on inherited live access).
    func autoVerifyJoin(jobId: UUID) async {
        guard let idx = jobIndex(for: jobId) else { return }
        let job = jobs[idx]
        let input = makeVerifierInput(for: job)

        currentVerificationJobId = jobId
        isVerifying = true
        updateJob(jobId) { j in
            j.verificationStatus = .verifying
            j.verificationProgress = 0
            j.isDeepVerifying = false
        }
        sourceTargetVerifier.resetCancellation()

        log("--- Auto-verify (fast): \(job.displayName) ---")

        let result = await sourceTargetVerifier.verifyFast(
            input,
            progress: { [weak self] fraction in
                Task { @MainActor in
                    self?.updateJob(jobId) { $0.verificationProgress = fraction }
                }
            },
            logHandler: { [weak self] message in
                Task { @MainActor in self?.log(message) }
            }
        )

        updateJob(jobId) { j in
            j.sourceTargetResult = result
            j.verificationStatus = mapStatus(result)
            j.isDeepVerifying = false
        }
        logVerdict(result, jobName: job.displayName)

        currentVerificationJobId = nil
        isVerifying = jobs.contains { $0.verificationStatus == .verifying }
        saveQueue()

        // Auto-escalate to byte-exact hashing on any anomaly. The source scope is still live here
        // (we're awaited inside `processJob`), so `runThoroughVerify` re-resolving is a harmless
        // no-op on this path.
        if result.hasWarning || !result.passed {
            log("Auto-escalating to byte-exact hash (fast verify flagged an anomaly)…")
            await runThoroughVerify(jobId: jobId, reason: "auto-escalation")
        }
    }

    /// Runs the thorough (Tier 0+1+2, byte-exact hash) verification on a completed job.
    ///
    /// For the **manual** path (the queue button) the join's source security-scoped access has
    /// lapsed, so this re-resolves the source bookmark and re-opens access for the duration of the
    /// pass. On the **auto-escalation** path the access is still live, so the re-open is an
    /// `.alreadyActive` no-op and the `defer` correctly leaves it untouched.
    func runThoroughVerify(jobId: UUID, reason: String) async {
        guard let idx = jobIndex(for: jobId) else { return }
        var job = jobs[idx]
        let input = makeVerifierInput(for: job)

        // Re-resolve source access (manual path: scope has lapsed since the join).
        let sourceURL: URL
        if let resolved = job.resolveSourceBookmark() {
            sourceURL = resolved
            updateJob(jobId) { j in
                j.sourceBookmarkData = job.sourceBookmarkData
                j.sourceFolderURL = job.sourceFolderURL
            }
        } else {
            sourceURL = job.sourceFolderURL
        }
        let sourceAccess = startAccessingIfNeeded(sourceURL)
        defer {
            if sourceAccess == .newlyGranted {
                stopAccessingIfNeeded(sourceURL)
            }
        }

        currentVerificationJobId = jobId
        isVerifying = true
        updateJob(jobId) { j in
            j.verificationStatus = .verifying
            j.verificationProgress = 0
            j.isDeepVerifying = true
        }
        sourceTargetVerifier.resetCancellation()

        log("--- Thorough verify (\(reason)): \(job.displayName) ---")

        let result = await sourceTargetVerifier.verifyThorough(
            input,
            progress: { [weak self] fraction in
                Task { @MainActor in
                    self?.updateJob(jobId) { $0.verificationProgress = fraction }
                }
            },
            logHandler: { [weak self] message in
                Task { @MainActor in self?.log(message) }
            }
        )

        updateJob(jobId) { j in
            j.sourceTargetResult = result
            j.verificationStatus = mapStatus(result)
            j.isDeepVerifying = false
        }
        logVerdict(result, jobName: job.displayName)

        currentVerificationJobId = nil
        isVerifying = jobs.contains { $0.verificationStatus == .verifying }
        saveQueue()
    }

    /// Non-async entry point for the queue's "Thorough verify (byte-exact)" button.
    func verifyJobThorough(jobId: UUID) {
        Task { await runThoroughVerify(jobId: jobId, reason: "manual") }
    }

    // MARK: - Source↔Target helpers

    /// Builds the verifier input from a completed job's clips + actual output. `sourceSegments` are
    /// the ordered source segment URLs; `outputURL` prefers the recorded actual URL (handles
    /// conflict-resolution renames); `hasAudio` is keyed off the first clip's probed audio stream;
    /// `sourceParams` is the per-segment probed stream info in source order.
    func makeVerifierInput(for job: ConversionJob) -> SourceTargetVerifier.SourceTargetInput {
        SourceTargetVerifier.SourceTargetInput(
            sourceSegments: job.clips.map(\.videoURL),
            outputURL: job.actualOutputURLs.first ?? job.destinationURL,
            hasAudio: job.clips.first?.streamInfo?.audio != nil,
            sourceParams: job.clips.map(\.streamInfo)
        )
    }

    /// Maps a `SourceTargetResult` onto the queue row's `VerificationStatus` seal.
    /// `.passed` → `.verified`; passed-but-flagged → `.warning`; otherwise → `.failed`.
    func mapStatus(_ result: SourceTargetResult) -> VerificationStatus {
        // Tier 2 byte-exact hash: if the hash check exists and passed,
        // the join is lossless regardless of Tier 1 container-metadata discrepancies.
        if result.tier == .thorough {
            let hashPassed = result.checks.first { $0.kind == .hashMatch }?.severity == .pass
            if hashPassed { return .verified }
        }
        if result.passed { return .verified }
        if result.hasWarning { return .warning(result.summary) }
        return .failed(result.firstFailureReason ?? result.summary)
    }

    /// Logs a one-line ✓/⚠/✗ verdict (the console already tints `✓` green, `✗` red).
    private func logVerdict(_ result: SourceTargetResult, jobName: String) {
        let glyph: String
        switch result.overall {
        case .pass, .info: glyph = "✓"
        case .warning: glyph = "⚠"
        case .fail: glyph = "✗"
        }
        log("\(glyph) \(jobName): \(result.summary)")
    }
}
