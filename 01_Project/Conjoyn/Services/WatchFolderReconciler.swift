import Foundation

// MARK: - Watch Folder Reconciler (Wave 5C, task 5.9)

/// Pure, stateless decision engine for the watch-folder pipeline.
///
/// All logic lives here; nothing lives in the coordinator shell. This separation makes the
/// enqueue policy unit-testable without FSEvents, FFmpeg, MainActor, or any real filesystem —
/// tests supply synthetic `GroupObservation`s and assert on the returned `[RecordGroup]`.
///
/// **No I/O, no clock, no MainActor.** Every non-deterministic input (file sizes, timestamps,
/// current time) is injected by the caller.
enum WatchFolderReconciler {

    // MARK: - GroupObservation

    /// Everything the coordinator observed about one discovered group during a single poll cycle.
    /// The shell builds these; the reconciler is only allowed to read them.
    struct GroupObservation {
        /// The group as discovered by `DJIFolderReader`.
        let group: RecordGroup

        /// Per-clip sample history, in group clip order. Each inner array is chronologically ordered
        /// (oldest first) and capped by the shell to a multiple of `requiredStablePolls`.
        let clipSamples: [[FileStabilityGate.Sample]]

        /// Size in bytes of the highest-index segment currently in the group.
        /// Used by `CompleteSetGate` to decide whether a continuation segment is still expected.
        let lastSegmentBytes: Int64

        /// Seconds since any member of the group last changed size or mtime.
        /// Computed by the shell from a per-group "last changed" wall-clock timestamp.
        let quietElapsed: TimeInterval
    }

    // MARK: - groupsToEnqueue

    /// Returns the subset of observed groups that are ready to enqueue right now.
    ///
    /// A group qualifies when ALL three gates pass:
    ///  1. **Settled** — every clip's sample history ends with `requiredStablePolls` consecutive
    ///     identical `(size, mtime)` snapshots (via `FileStabilityGate.isSettled`).
    ///  2. **Complete** — the last segment is below the split threshold AND the group has been
    ///     quiet long enough (via `CompleteSetGate.isComplete`).
    ///  3. **Fresh** — the group's stable fingerprint is not yet in `processedFingerprints`,
    ///     ensuring a finished group is never re-enqueued even if the source files stay on disk.
    ///
    /// Empty groups (no clips) are never ready — the gates would trivially pass on empty inputs,
    /// so we guard against that explicitly.
    ///
    /// - Parameters:
    ///   - observations:           One entry per discovered group, built by the coordinator.
    ///   - settings:               User-tunable thresholds (stablePolls, quietWindow, splitThreshold).
    ///   - processedFingerprints:  Set of SHA-256 fingerprints already in `ProcessedGroupLedger`.
    /// - Returns: Groups that should be enqueued immediately, in the order they appear in `observations`.
    static func groupsToEnqueue(
        observations: [GroupObservation],
        settings: WatchFolderSettings,
        processedFingerprints: Set<String>
    ) -> [RecordGroup] {
        observations.compactMap { obs in
            // Empty group — guard before passing to gates that trivially pass on empty sequences.
            guard !obs.group.clips.isEmpty else { return nil }

            // Gate 1: every clip must be stable.
            let settled = obs.clipSamples.allSatisfy { samples in
                FileStabilityGate.isSettled(samples: samples,
                                            requiredStablePolls: settings.requiredStablePolls)
            }
            guard settled else { return nil }

            // Gate 2: the set must be complete (last segment final + quiet window elapsed).
            let complete = CompleteSetGate.isComplete(
                lastSegmentBytes: obs.lastSegmentBytes,
                splitThreshold: settings.splitThreshold,
                quietElapsed: obs.quietElapsed,
                quietWindow: settings.quietWindow
            )
            guard complete else { return nil }

            // Gate 3: not already processed.
            let fingerprint = ProcessedGroupLedger.fingerprint(for: obs.group)
            guard !processedFingerprints.contains(fingerprint) else { return nil }

            return obs.group
        }
    }

    // MARK: - shouldReenqueue

    /// Relaunch idempotency check (task 5.10): determines whether a persisted group should be
    /// re-enqueued on app relaunch.
    ///
    /// Returns `true` only when the fingerprint is absent from BOTH the ledger (completed groups)
    /// AND the live queue (in-progress groups). This prevents a group that was mid-flight at quit
    /// from being double-enqueued: the `QueueManager` already persisted the job across the quit,
    /// so `liveQueueFingerprints` contains it and this returns `false`.
    ///
    /// - Parameters:
    ///   - fingerprint:             Stable SHA-256 fingerprint for the group (from `ProcessedGroupLedger.fingerprint`).
    ///   - processedFingerprints:   Fingerprints of groups already completed (from the ledger).
    ///   - liveQueueFingerprints:   Fingerprints of groups currently represented by unfinished queue jobs.
    static func shouldReenqueue(
        fingerprint: String,
        processedFingerprints: Set<String>,
        liveQueueFingerprints: Set<String>
    ) -> Bool {
        !processedFingerprints.contains(fingerprint) && !liveQueueFingerprints.contains(fingerprint)
    }
}
