import Foundation
import CoreMedia

// MARK: - Record Group (Wave 1, task 1.3)

/// A set of clips that form one continuous recording, detected by **metadata continuity**
/// (`creationDate` + duration + filename index) — never by filename alone, and never across
/// differing camera/lens variant suffixes. Transient: recomputed from the folder, never persisted.
/// **One `RecordGroup` becomes one `ConversionJob`**, matching the concat-demuxer join (one group →
/// one output) and the watch-folder "join when the group is complete" state machine.
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

    /// How the group was formed.
    enum GroupType {
        case split      // multiple segments of one split recording
        case single     // a lone clip, no join needed
    }

    init(clips: [DJIClip], groupIndex: Int, groupType: GroupType = .split, variantSuffix: String? = nil) {
        self.clips = clips
        self.groupIndex = groupIndex
        self.groupType = groupType
        self.variantSuffix = variantSuffix ?? clips.first?.variantSuffix
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
