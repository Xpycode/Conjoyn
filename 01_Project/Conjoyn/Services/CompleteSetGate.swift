import Foundation

// MARK: - Complete-Set Gate (Wave 5A, task 5.2)

/// Pure decision: **is a record group done growing — safe to join?**
///
/// DJI cameras split a long recording into fixed-size segments (~4 GB on FAT32, the classic
/// single-file ceiling). A watch-folder that joins too early would stitch only the first N of M
/// segments. We gate on two **independent** signals, and require **both**:
///
///  1. **Last segment below the split threshold.** A continuation segment is only created when the
///     previous one *fills*. So if the final segment is comfortably under the split size, the camera
///     stopped recording there and no further segment will chain on. A last segment *at* (or near)
///     the split size means another may still be coming.
///  2. **A quiet window has elapsed.** No new member has appeared for `quietWindow` seconds, so the
///     SD-card copy / camera write has paused or finished. This catches the case where segments are
///     still trickling in even though the last one we *currently* see looks small.
///
/// Pure (no I/O, no clock) — the caller measures `lastSegmentBytes` and `quietElapsed` and injects
/// them, so the rule is deterministic and unit-testable.
///
/// Suggested defaults (tune in `WatchFolderSettings`, task 5.8): `quietWindow` 30–60 s;
/// `splitThreshold` a little under the camera's real split size so a segment that stopped a hair
/// early still reads as "final".
struct CompleteSetGate {

    /// `true` when the group's last segment is below the split threshold **and** the quiet window
    /// has fully elapsed.
    ///
    /// - Parameters:
    ///   - lastSegmentBytes: Size of the highest-indexed segment currently in the group.
    ///   - splitThreshold: The size at/above which a continuation segment is expected.
    ///   - quietElapsed: Seconds since the most recent member appeared/changed.
    ///   - quietWindow: How long the group must stay quiet before it counts as complete.
    static func isComplete(lastSegmentBytes: Int64,
                           splitThreshold: Int64,
                           quietElapsed: TimeInterval,
                           quietWindow: TimeInterval) -> Bool {
        // ── Policy block — yours to tune ──────────────────────────────────────────────────
        // The "is the set finished" judgement lives here. Default = the strict AND of the two
        // signals described above. You might, for example, treat a *very* old quiet group as
        // complete even if the last segment looks large (camera yanked mid-fill), or add a
        // minimum-segment-count rule. The tests pin the documented contract.
        let lastSegmentIsFinal = lastSegmentBytes < splitThreshold
        let hasBeenQuietLongEnough = quietElapsed >= quietWindow
        return lastSegmentIsFinal && hasBeenQuietLongEnough
        // ──────────────────────────────────────────────────────────────────────────────────
    }
}
