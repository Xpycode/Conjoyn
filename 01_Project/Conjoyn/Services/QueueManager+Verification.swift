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
        // Also cancel the active subprocess.
        verificationService.cancel()
        if let jobId = currentVerificationJobId {
            updateJob(jobId) { j in
                j.verificationStatus = .unverified
                j.verificationProgress = 0
            }
        }
        isVerifying = false
    }
}
