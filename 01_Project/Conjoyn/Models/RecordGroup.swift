import Foundation
import CoreMedia

// MARK: - Record Group (Wave 1, task 1.3)

/// A set of clips that form one continuous recording, detected by **metadata continuity**
/// (`creationDate` + duration + filename index) — never by filename alone, and never across
/// differing camera/lens variant suffixes. Transient: recomputed from the folder, never persisted.
/// **One `RecordGroup` becomes one `ConversionJob`**, matching the concat-demuxer join (one group →
/// one output). The watch-folder advances a group from discovery to a joined output via the
/// `WatchGroupState` machine, gated by `CompleteSetGate` ("join only once the set is complete").
struct RecordGroup: Identifiable {
    /// Derived from the first clip for stable identity across recomputes (so SwiftUI doesn't treat
    /// a group as a new item on every access).
    var id: UUID { clips.first?.id ?? UUID() }

    let clips: [DJIClip]
    let groupIndex: Int          // 1-based, for display
    let groupType: GroupType
    /// The camera/lens variant shared by every clip in the group (all clips share it by
    /// construction); `nil` for legacy un-suffixed names.
    let variantSuffix: String?
    /// GoPro incomplete-set signal (G3.4); always `.complete` for DJI groups. **Warns, never
    /// blocks**: a joined chapters-02..N (or gapped) output is a valid, playable, correct MP4 — just
    /// not the whole recording — so an incomplete group stays selectable and enqueueable exactly
    /// like a complete one. This deliberately diverges from the spec's "flagged incomplete and not
    /// joined": the real corpus holds a specimen where a hard block would matter (recording 6338's
    /// chapter 01 left the archive), and permanently locking that recording out is worse than
    /// letting the user join what's actually on the card. Do not add an enqueue/selection gate on
    /// this field. Non-persisted: `RecordGroup` is never `Codable` (see the header comment above),
    /// so this carries none of the queue's `CodingKeys`/`decodeIfPresent` hazard.
    let completeness: Completeness

    /// How the group was formed.
    enum GroupType {
        case split      // multiple segments of one split recording
        case single     // a lone clip, no join needed
    }

    /// Whether every chapter of a GoPro recording made it into this group. Display-only — computed
    /// by `DJIFolderReader.group(_:)` from the grouping result, never a join-time gate (see
    /// `completeness`'s doc above).
    enum Completeness: Equatable, Sendable {
        /// Every chapter present and bridged (always true for DJI groups).
        case complete
        /// The run's first chapter number is above 01 — a GoPro recording never starts above
        /// chapter 01 on camera (measured), so chapter 01 isn't in this folder.
        case missingFirstChapter
        /// The recording's chapters exist but couldn't all be bridged into one run — a chapter is
        /// missing from the middle, or something else broke the chain partway through.
        case chapterGap
    }

    init(
        clips: [DJIClip],
        groupIndex: Int,
        groupType: GroupType = .split,
        variantSuffix: String? = nil,
        completeness: Completeness = .complete
    ) {
        self.clips = clips
        self.groupIndex = groupIndex
        self.groupType = groupType
        self.variantSuffix = variantSuffix ?? clips.first?.variantSuffix
        self.completeness = completeness
    }

    var clipCount: Int { clips.count }

    /// Ordered video URLs feeding the join.
    var videoURLs: [URL] { clips.map(\.videoURL) }

    /// Combined duration across all segments (exact `CMTime` sum).
    var totalDuration: CMTime {
        clips.reduce(.zero) { CMTimeAdd($0, $1.duration) }
    }

    /// Combined duration in seconds.
    var totalDurationSeconds: Double {
        let total = totalDuration
        return total.timescale != 0 ? CMTimeGetSeconds(total) : 0
    }

    /// Description of how the group was formed.
    var groupTypeLabel: String {
        switch groupType {
        case .split: return "Split"
        case .single: return "Single"
        }
    }
}
