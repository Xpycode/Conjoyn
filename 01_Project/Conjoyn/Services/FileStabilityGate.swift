import Foundation

// MARK: - File Stability Gate (Wave 5A, task 5.1)

/// Pure decision: **has a file stopped changing?**
///
/// A watch-folder must never enqueue a clip that the camera, Finder copy, or SD-card ingest is
/// still writing — a half-copied MP4 would join into a corrupt output. We decide "settled"
/// purely from a series of `(size, modificationDate)` snapshots taken by an *external* sampler.
/// **No I/O happens in this type** (the sampler injects the stats), so the rule is trivially
/// unit-testable and deterministic.
///
/// ## Contract (encoded by `FileStabilityGateTests`)
/// - A file whose size keeps growing is **never** settled.
/// - A file is settled only after `requiredStablePolls` **consecutive identical** snapshots —
///   identical means *both* size and `modificationDate` match (an in-place rewrite keeps the
///   size but bumps the mtime, and must reset the streak).
/// - **Atomic write** (write-to-temp → rename): the sampler watches the *final* path, which only
///   materialises at the rename, so the first snapshot we ever see is already the complete file.
///   It still needs `requiredStablePolls` confirmations like anything else — the gate doesn't
///   special-case it, the sampling cadence (~0.75 s) does.
///
/// Suggested default cautiousness: `requiredStablePolls = 3` at ~0.75 s ≈ a file must hold steady
/// for ~2.25 s before we touch it. Tune via `WatchFolderSettings` (task 5.8), not here.
struct FileStabilityGate {

    /// One observation of a file's mutable attributes, as read by the sampler.
    struct Sample: Equatable, Sendable {
        let size: Int64
        let modified: Date

        init(size: Int64, modified: Date) {
            self.size = size
            self.modified = modified
        }
    }

    /// `true` once the tail of `samples` shows `requiredStablePolls` consecutive identical
    /// `(size, modified)` pairs — i.e. the file has been quiet for long enough to be safe to read.
    ///
    /// - Parameters:
    ///   - samples: Snapshots in chronological order (oldest first). Fewer than
    ///     `requiredStablePolls` samples can never be settled.
    ///   - requiredStablePolls: How many trailing snapshots must match. Values < 1 are treated as
    ///     "never settle" (defensive — a zero-poll gate would pass an actively-growing file).
    static func isSettled(samples: [Sample], requiredStablePolls: Int) -> Bool {
        // ── Policy block — yours to tune ──────────────────────────────────────────────────
        // The cautiousness of the watch-folder lives here. The default below is the strict
        // reading of the contract above: the last `requiredStablePolls` snapshots must all be
        // byte-and-mtime identical. Make it more paranoid (e.g. also require a minimum age, or
        // demand the size be non-zero) or more eager as you see fit — the tests pin the contract.
        guard requiredStablePolls >= 1 else { return false }
        guard samples.count >= requiredStablePolls else { return false }

        let tail = samples.suffix(requiredStablePolls)
        guard let reference = tail.first else { return false }
        return tail.allSatisfy { $0 == reference }
        // ──────────────────────────────────────────────────────────────────────────────────
    }
}
