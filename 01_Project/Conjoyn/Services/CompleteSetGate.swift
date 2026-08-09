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

    // MARK: - Family-aware overload (Wave G6.1)

    /// `true` when the group's last **chapter** is final for its camera family **and** the quiet
    /// window has fully elapsed. DJI keeps the absolute-threshold rule above unchanged — this
    /// overload exists to add a *different* rule for GoPro, whose per-chapter cap varies with fps
    /// and has no single constant analogous to DJI's ~4 GB FAT32 ceiling.
    ///
    /// For `.dji`, this delegates verbatim to the 4-argument `isComplete` above, ignoring every
    /// GoPro-only parameter — the DJI decision is provably unchanged by this overload's existence.
    ///
    /// For `.goPro`, the last chapter is "final" when:
    ///  - **A preceding chapter is visible and usable:** `lastSegmentBytes < min(precedingSegmentBytes)
    ///    * finalChapterRatio`. Measured against the real 71-file Hero 11 corpus: final-chapter ratios
    ///    (last chapter's size / the smallest preceding chapter's size) range 0.0762–0.8850 (tightest:
    ///    recording 6348 chapter 03); non-final ratios range 0.99989–1.00015 — and can exceed 1.0,
    ///    since a later chapter can be marginally larger than the smallest earlier one. `finalChapterRatio`
    ///    defaults to 0.94, sitting in the empty band between those two clusters, and the comparison is
    ///    a strict `<` so a non-final ratio just above 1.0 still reads as "expect continuation".
    ///  - **No usable reference** (no preceding chapters, or every preceding size is `<= 0`):
    ///    `lastSegmentBytes < goProSplitFloor`. Measured against the same corpus: the largest genuine
    ///    single-chapter recording is 7.66 GB (GX016350); the smallest cap-filled chapter is 11.4976 GB
    ///    (recording 6338 chapter 01). `goProSplitFloor` defaults to 9.5 GB, in the empty band between
    ///    them — this is what stops a still-copying card holding only chapter 01 (a one-member group
    ///    with no reference) from being joined alone. Non-positive sizes are **filtered out** before
    ///    taking the minimum rather than poisoning it: a missing size sample reads as `0`, and a bare
    ///    `min()` would both make the ratio comparison `x < 0` (never true, stalling the group
    ///    forever) and discard any genuine reference sitting alongside it. Filtering keeps the real
    ///    reference when one exists — which errs toward "expect continuation", the safe direction —
    ///    and reaches the floor only when no preceding size is usable at all. Defensive only:
    ///    `FileStabilityGate.isSettled` requires `samples.count >= requiredStablePolls`, so an
    ///    unsampled clip fails Gate 1 in `WatchFolderReconciler` before this gate ever runs.
    ///
    /// Then, exactly as the DJI rule: complete = `lastIsFinal && quietElapsed >= quietWindow`.
    ///
    /// - Parameters:
    ///   - family: Camera family shared by every clip in the group (grouping guarantees this).
    ///   - lastSegmentBytes: Size of the highest-indexed chapter currently in the group.
    ///   - precedingSegmentBytes: Sizes of every chapter below the highest-index one — the GoPro
    ///     relative reference. Ignored on the `.dji` path.
    ///   - splitThreshold: DJI's absolute split-size threshold (passed through to the 4-arg rule).
    ///   - goProSplitFloor: GoPro's no-reference absolute floor.
    ///   - finalChapterRatio: GoPro's relative final-chapter ratio.
    ///   - quietElapsed: Seconds since the most recent member appeared/changed.
    ///   - quietWindow: How long the group must stay quiet before it counts as complete.
    static func isComplete(family: DJIFilenameParser.CameraFamily,
                           lastSegmentBytes: Int64,
                           precedingSegmentBytes: [Int64],
                           splitThreshold: Int64,
                           goProSplitFloor: Int64,
                           finalChapterRatio: Double,
                           quietElapsed: TimeInterval,
                           quietWindow: TimeInterval) -> Bool {
        switch family {
        case .dji:
            return isComplete(lastSegmentBytes: lastSegmentBytes,
                              splitThreshold: splitThreshold,
                              quietElapsed: quietElapsed,
                              quietWindow: quietWindow)
        case .goPro:
            let minPreceding = precedingSegmentBytes.filter { $0 > 0 }.min()
            let lastSegmentIsFinal: Bool
            if let minPreceding {
                lastSegmentIsFinal = Double(lastSegmentBytes) < Double(minPreceding) * finalChapterRatio
            } else {
                lastSegmentIsFinal = lastSegmentBytes < goProSplitFloor
            }
            let hasBeenQuietLongEnough = quietElapsed >= quietWindow
            return lastSegmentIsFinal && hasBeenQuietLongEnough
        }
    }
}
