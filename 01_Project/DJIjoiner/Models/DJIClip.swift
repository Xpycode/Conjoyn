import Foundation
import CoreMedia

// MARK: - DJI Clip (Wave 1, task 1.3)

/// One DJI recording segment: a single video file, its optional `.SRT`/`.LRF` sidecars, and the
/// metadata used to group and join it. The DJIjoiner analogue of P2toMXF's `P2Clip` — but a DJI
/// MP4 is self-contained (one video file, no separate audio MXFs, no span-relation IDs), so the
/// model is much smaller and grouping leans on **metadata continuity** (`creationDate` + duration
/// + filename index) rather than embedded span pointers.
///
/// File URLs are stored as `String` paths and exposed via computed `URL` accessors so the whole
/// value stays trivially `Codable` (the queue persists `[DJIClip]` to disk). Duration is stored as
/// an `Int64` value + `Int32` timescale backing and rebuilt into an exact `CMTime` only at the
/// boundary — preserving frame-exact timing while remaining `Codable`/`Sendable`.
struct DJIClip: Identifiable, Hashable, Codable, Sendable {
    let id: UUID

    // MARK: Stored paths (Codable-friendly; exposed as URLs below)

    private let videoFilePath: String
    private let srtFilePath: String?
    private let lrfFilePath: String?

    // MARK: Filename-derived fields (corroborating grouping signals only)

    /// Sequential capture index (the `NNNN` field), from `DJIFilenameParser`.
    let index: Int
    /// Trailing camera/lens variant suffix (`"D"`, `"W"`, `"T"`, …); `nil` for legacy names.
    /// The grouping engine must **never** merge clips across differing suffixes.
    let variantSuffix: String?
    /// Capture date-time from the timestamped naming scheme; `nil` for legacy names. Carries no
    /// time zone — interpret against the segment's metadata, don't assume UTC/local.
    let filenameTimestamp: DateComponents?
    /// Filename minus extension (e.g. `DJI_0001`). A video and its sidecars share this.
    let stem: String

    // MARK: Metadata-read fields (authoritative grouping signals)

    /// Embedded `creation_time` read from the container; the primary continuity key.
    let creationDate: Date?
    /// Camera model from QuickTime tags, when present (varies by DJI model).
    let cameraModel: String?

    // MARK: Duration (exact CMTime via Codable backing)

    private let durationValue: Int64
    private let durationTimescale: Int32

    // MARK: Copy-relevant stream parameters

    /// The probed stream parameters used by both the join's param guard (task 2.6) and the
    /// grouping engine (task 2.4) — one source of truth, no duplicated codec/res/fps fields.
    let streamInfo: StreamParameterGuard.SegmentStreamInfo?

    // MARK: - URL accessors

    var videoURL: URL { URL(fileURLWithPath: videoFilePath) }
    var srtURL: URL? { srtFilePath.map { URL(fileURLWithPath: $0) } }
    var lrfURL: URL? { lrfFilePath.map { URL(fileURLWithPath: $0) } }

    var hasSRT: Bool { srtFilePath != nil }
    var hasProxy: Bool { lrfFilePath != nil }

    // MARK: - Derived values

    /// Exact segment duration, rebuilt from the Codable backing.
    var duration: CMTime { CMTime(value: durationValue, timescale: durationTimescale) }

    /// Duration in seconds (0 if the backing timescale is invalid).
    var durationInSeconds: Double {
        durationTimescale != 0 ? CMTimeGetSeconds(duration) : 0
    }

    /// User-facing name for the clip.
    var displayName: String { stem }

    /// Size of the video file on disk in bytes (0 if it can't be read).
    var totalFileSize: Int64 {
        (try? FileManager.default.attributesOfItem(atPath: videoFilePath)[.size] as? Int64) ?? 0
    }

    // MARK: - Initializer

    init(
        id: UUID = UUID(),
        videoURL: URL,
        srtURL: URL? = nil,
        lrfURL: URL? = nil,
        index: Int,
        variantSuffix: String? = nil,
        filenameTimestamp: DateComponents? = nil,
        stem: String,
        creationDate: Date? = nil,
        cameraModel: String? = nil,
        duration: CMTime,
        streamInfo: StreamParameterGuard.SegmentStreamInfo? = nil
    ) {
        self.id = id
        self.videoFilePath = videoURL.path
        self.srtFilePath = srtURL?.path
        self.lrfFilePath = lrfURL?.path
        self.index = index
        self.variantSuffix = variantSuffix
        self.filenameTimestamp = filenameTimestamp
        self.stem = stem
        self.creationDate = creationDate
        self.cameraModel = cameraModel
        self.durationValue = duration.value
        self.durationTimescale = duration.timescale
        self.streamInfo = streamInfo
    }
}

// MARK: - Factory

extension DJIClip {
    /// Builds a clip from a parsed filename plus probed/optional metadata, pairing the given
    /// sidecars. `parsed` supplies the index/variant/timestamp/stem; `duration`, `creationDate`,
    /// `cameraModel`, and `streamInfo` come from the metadata reader / param probe (tasks 2.2/2.6).
    static func from(
        parsed: DJIFilenameParser.Parsed,
        videoURL: URL,
        srtURL: URL? = nil,
        lrfURL: URL? = nil,
        duration: CMTime,
        creationDate: Date? = nil,
        cameraModel: String? = nil,
        streamInfo: StreamParameterGuard.SegmentStreamInfo? = nil
    ) -> DJIClip {
        DJIClip(
            videoURL: videoURL,
            srtURL: srtURL,
            lrfURL: lrfURL,
            index: parsed.index,
            variantSuffix: parsed.variantSuffix,
            filenameTimestamp: parsed.timestamp,
            stem: parsed.stem,
            creationDate: creationDate,
            cameraModel: cameraModel,
            duration: duration,
            streamInfo: streamInfo
        )
    }
}

// MARK: - Clip parse error

/// A media file that failed to parse or probe during folder discovery. Ported from P2toMXF.
struct ClipParseError: Identifiable, Codable, Sendable {
    let id: UUID
    private let filePathString: String
    let errorMessage: String

    /// Full URL of the file that failed.
    var filePath: URL { URL(fileURLWithPath: filePathString) }
    /// Just the filename, for display.
    var fileName: String { filePath.lastPathComponent }

    init(file: URL, error: Error) {
        self.id = UUID()
        self.filePathString = file.path
        self.errorMessage = error.localizedDescription
    }

    /// For Codable / explicit-message construction.
    init(file: URL, message: String) {
        self.id = UUID()
        self.filePathString = file.path
        self.errorMessage = message
    }
}
