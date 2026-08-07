import Foundation
import CoreMedia

// MARK: - DJI Clip (Wave 1, task 1.3)

/// One DJI recording segment: a single video file, its optional `.SRT`/`.LRF` sidecars, and the
/// metadata used to group and join it. The Conjoyn analogue of P2toMXF's `P2Clip` — but a DJI
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
    /// Camera family that produced this clip, from `DJIFilenameParser.Parsed.family`. Defaults to
    /// `.dji` when absent from the JSON — every clip persisted before this field existed was DJI,
    /// so a 1.0.4 blob (which has no such key) restores as DJI, which is the whole point.
    let family: DJIFilenameParser.CameraFamily
    /// GoPro's four-digit file number (the recording identity), from `parsed.recordingNumber`;
    /// `nil` for DJI clips. Two chapters of the same recording share this — a later wave uses it
    /// to bucket chapters before grouping ever asks about temporal adjacency.
    let recordingNumber: Int?

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

    /// Seek time (in seconds) for the *last-frame* thumbnail — near the end, so the seek lands on a
    /// real frame instead of past EOF. Frame rate comes from the probed stream when available;
    /// absent that, assume 30 fps (a safe DJI default — a wrong guess only shifts the seek slightly).
    ///
    /// We back off a little more than a single frame (~2 frames / 50 ms). The container duration is
    /// an *upper bound* — it can sit a hair past the final frame's PTS — and the FFmpeg seek argument
    /// is rounded to milliseconds, so seeking to exactly `duration − 1 frame` can round *past* the
    /// last frame and decode nothing. The wider guard reliably grabs a frame near the end; the visual
    /// difference for a thumbnail is imperceptible. Mirrors P2toMXF's `P2Clip.lastFrameTimestamp`.
    var lastFrameSeekSeconds: Double {
        let fps = streamInfo?.video.framesPerSecond ?? 30.0
        return max(0, durationInSeconds - max(2.0 / fps, 0.05))
    }

    /// User-facing name for the clip.
    var displayName: String { stem }

    /// Size of the video file on disk in bytes (0 if it can't be read). The split-cap grouping
    /// signal (task 2.4) keys off this, so read it via `NSNumber.int64Value` — FileManager returns
    /// the `.size` attribute as an `NSNumber`, and a direct `as? Int64` bridge can fail and yield 0.
    var totalFileSize: Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: videoFilePath)
        return (attrs?[.size] as? NSNumber)?.int64Value ?? 0
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
        family: DJIFilenameParser.CameraFamily = .dji,
        recordingNumber: Int? = nil,
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
        self.family = family
        self.recordingNumber = recordingNumber
        self.creationDate = creationDate
        self.cameraModel = cameraModel
        self.durationValue = duration.value
        self.durationTimescale = duration.timescale
        self.streamInfo = streamInfo
    }
}

// MARK: - Codable (hand-written decoder — queue-compatibility critical)

extension DJIClip {
    /// Explicit keys for all 15 stored properties. Nothing is decoded that isn't listed here, so a
    /// property added *without* a key simply keeps its default instead of breaking old blobs.
    ///
    /// `CaseIterable` is load-bearing, not decoration: `QueuePersistenceCompatTests`
    /// enumerates these to prove `encode(to:)` below actually writes every one of them. Since
    /// that encoder is hand-written, a key added here but forgotten there would otherwise never
    /// reach disk — silently, with no test red.
    enum CodingKeys: String, CodingKey, CaseIterable {
        case id
        case videoFilePath, srtFilePath, lrfFilePath
        case index, variantSuffix, filenameTimestamp, stem
        case family, recordingNumber
        case creationDate, cameraModel
        case durationValue, durationTimescale
        case streamInfo
    }

    /// Decodes a clip from a `queue.json` that may predate any field added since it was written.
    ///
    /// **Why this is hand-written.** The queue persists `[ConversionJob]` — and therefore
    /// `[DJIClip]` — across app updates. The *synthesized* decoder calls `decode` (not
    /// `decodeIfPresent`) for every non-Optional property, so adding one `var` with a default value
    /// makes an older blob throw `keyNotFound`; `QueueManager.loadQueue` catches that at
    /// `QueueManager.swift:301` and the user's entire queue silently disappears on the first launch
    /// after updating. (A `let` with an inline default is exempt — Swift leaves it out of synthesis
    /// altogether — but that exemption is invisible at the call site and vanishes the moment the
    /// property becomes a `var`. Don't rely on it.)
    ///
    /// **Rule for every new field:** add its key above, decode it with `decodeIfPresent`, and give
    /// it a documented default for the blobs that predate it. Only fields that existed in the
    /// shipped 1.0.4 layout — and are meaningless without a value — use a plain `decode`.
    /// `ConjoynTests/QueuePersistenceCompatTests` pins this against a real 1.0.4 `queue.json`.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Required: present in every blob since 1.0.0, and a clip without them is unusable.
        id = try container.decode(UUID.self, forKey: .id)
        videoFilePath = try container.decode(String.self, forKey: .videoFilePath)
        index = try container.decode(Int.self, forKey: .index)
        stem = try container.decode(String.self, forKey: .stem)
        durationValue = try container.decode(Int64.self, forKey: .durationValue)
        durationTimescale = try container.decode(Int32.self, forKey: .durationTimescale)

        // Optional in the model — and absent from the JSON entirely when nil, since the synthesized
        // encoder writes Optionals with `encodeIfPresent`.
        srtFilePath = try container.decodeIfPresent(String.self, forKey: .srtFilePath)
        lrfFilePath = try container.decodeIfPresent(String.self, forKey: .lrfFilePath)
        variantSuffix = try container.decodeIfPresent(String.self, forKey: .variantSuffix)
        filenameTimestamp = try container.decodeIfPresent(DateComponents.self, forKey: .filenameTimestamp)
        creationDate = try container.decodeIfPresent(Date.self, forKey: .creationDate)
        cameraModel = try container.decodeIfPresent(String.self, forKey: .cameraModel)
        streamInfo = try container.decodeIfPresent(
            StreamParameterGuard.SegmentStreamInfo.self, forKey: .streamInfo
        )

        // `family` predates GoPro support only in the sense that no blob before this field existed
        // ever carried anything else — absent key ⇒ `.dji`. (An unrecognised-but-present raw value
        // is handled by `CameraFamily.init(from:)` itself, which the `decodeIfPresent` below defers
        // to — see that type for the tolerant-decode rationale.)
        family = try container.decodeIfPresent(
            DJIFilenameParser.CameraFamily.self, forKey: .family
        ) ?? .dji
        recordingNumber = try container.decodeIfPresent(Int.self, forKey: .recordingNumber)
    }

    /// Hand-written for the same reason `init(from:)` is: `family` is non-Optional (every clip has
    /// one), but a *fully* synthesized encoder would write `"family": "dji"` into every DJI clip's
    /// JSON — the overwhelming majority of clips on disk today — changing the shape 1.0.4 wrote and
    /// breaking `QueuePersistenceCompatTests`' pinned key set. Omitting the default `.dji` keeps a
    /// DJI clip's on-disk shape byte-identical to 1.0.4; a GoPro clip's non-default family is written
    /// explicitly, and `init(from:)` above maps an absent key back to `.dji` either way. Every other
    /// field keeps the same shape the synthesized encoder produced (`encodeIfPresent` for Optionals).
    ///
    /// **Rule for every new field, encoder half:** write it here too. Hand-writing this trades the
    /// decoder's `keyNotFound` hazard for its mirror image — a field added to `CodingKeys` and to
    /// `init(from:)` but forgotten *here* is simply never persisted, and reloads as its default
    /// every launch with nothing going red. `QueuePersistenceCompatTests` pins that by walking
    /// `CodingKeys.allCases`.
    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(videoFilePath, forKey: .videoFilePath)
        try container.encodeIfPresent(srtFilePath, forKey: .srtFilePath)
        try container.encodeIfPresent(lrfFilePath, forKey: .lrfFilePath)
        try container.encode(index, forKey: .index)
        try container.encodeIfPresent(variantSuffix, forKey: .variantSuffix)
        try container.encodeIfPresent(filenameTimestamp, forKey: .filenameTimestamp)
        try container.encode(stem, forKey: .stem)
        if family != .dji {
            try container.encode(family, forKey: .family)
        }
        try container.encodeIfPresent(recordingNumber, forKey: .recordingNumber)
        try container.encodeIfPresent(creationDate, forKey: .creationDate)
        try container.encodeIfPresent(cameraModel, forKey: .cameraModel)
        try container.encode(durationValue, forKey: .durationValue)
        try container.encode(durationTimescale, forKey: .durationTimescale)
        try container.encodeIfPresent(streamInfo, forKey: .streamInfo)
    }
}

// MARK: - Factory

extension DJIClip {
    /// Builds a clip from a parsed filename plus probed/optional metadata, pairing the given
    /// sidecars. `parsed` supplies the index/variant/timestamp/stem/family/recordingNumber;
    /// `duration`, `creationDate`, `cameraModel`, and `streamInfo` come from the metadata reader /
    /// param probe (tasks 2.2/2.6).
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
            family: parsed.family,
            recordingNumber: parsed.recordingNumber,
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
