import Foundation

// MARK: - Batch Queue Models (Wave 1, task 1.2)

// Ported from P2toMXF (`Models/ConversionJob.swift`) with DJI renames: `cardName`→`folderName`,
// `cardPath`→`sourceFolderURL`, `cardBookmark`→`sourceBookmark`. **One job = one record group**
// (the concat join is one group → one output), so `clips` is the group's ordered segments. The
// custom `JobStatus`/`.failed(String)` Codable is kept verbatim. No shipped `queue.json` to stay
// compatible with, so the renames are free.

/// Status of a conversion job in the queue.
enum JobStatus: Equatable, Codable, Sendable {
    case pending       // Waiting in queue
    case preparing     // Gathering files / writing the concat list
    case active        // FFmpeg is processing
    case completed     // Successfully finished
    case failed(String) // Error encountered
    case cancelled     // User cancelled

    var displayName: String {
        switch self {
        case .pending: return "Queued"
        case .preparing: return "Preparing"
        case .active: return "Joining"
        case .completed: return "Completed"
        case .failed: return "Failed"
        case .cancelled: return "Cancelled"
        }
    }

    var iconName: String {
        switch self {
        case .pending: return "clock"
        case .preparing: return "gearshape.2"
        case .active: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        case .cancelled: return "stop.circle.fill"
        }
    }

    var isFinished: Bool {
        switch self {
        case .completed, .failed, .cancelled: return true
        default: return false
        }
    }

    // MARK: - Codable (custom for associated value)

    private enum CodingKeys: String, CodingKey {
        case type, errorMessage
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)

        switch type {
        case "pending": self = .pending
        case "preparing": self = .preparing
        case "active": self = .active
        case "completed": self = .completed
        case "failed":
            let message = try container.decode(String.self, forKey: .errorMessage)
            self = .failed(message)
        case "cancelled": self = .cancelled
        default: self = .pending
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        switch self {
        case .pending: try container.encode("pending", forKey: .type)
        case .preparing: try container.encode("preparing", forKey: .type)
        case .active: try container.encode("active", forKey: .type)
        case .completed: try container.encode("completed", forKey: .type)
        case .failed(let message):
            try container.encode("failed", forKey: .type)
            try container.encode(message, forKey: .errorMessage)
        case .cancelled: try container.encode("cancelled", forKey: .type)
        }
    }
}

/// A single conversion job in the queue — one DJI record group joined into one output file.
struct ConversionJob: Identifiable, Codable, Sendable {
    let id: UUID
    let folderName: String                  // Source DCIM folder name
    private var sourceFolderPathString: String  // For security-scoped access (stored as path)
    let clips: [DJIClip]                    // The record group's ordered segments
    let settings: ConversionSettings
    private var destinationPathString: String   // Final output file path (stored as path)
    let createdAt: Date

    var status: JobStatus = .pending
    var progress: Double = 0.0    // 0.0 to 1.0
    var startedAt: Date?          // When processing started (for elapsed time)

    // Security-scoped bookmark data for persisting file access across app launches.
    var sourceBookmarkData: Data?
    var outputBookmarkData: Data?

    // Manual timecode override — session-only, intentionally excluded from CodingKeys.
    var timecodeStringOverride: String? = nil

    /// The start timecode actually stamped onto the output `tmcd` track during the join — the exact
    /// string `resolveJoinMetadata` handed to ffmpeg's `-timecode`. `nil` when nothing was stamped
    /// (the `preserveTimecode` toggle was off, or no recording-start signal resolved). Persisted (in
    /// `CodingKeys`) so the write-back verification can re-read the output's `tmcd` and confirm it
    /// matches what was assigned — including on a manual thorough re-verify after relaunch.
    var appliedTimecode: String? = nil

    // Verification state.
    var verificationStatus: VerificationStatus = .unverified
    var verificationResult: VerificationResult?
    var sourceTargetResult: SourceTargetResult?
    var verificationProgress: Double = 0.0  // 0.0 to 1.0
    /// True while the *byte-exact* (Tier-2 hash) pass is running — set when the fast verify
    /// auto-escalates on an anomaly, or when "Thorough verify" is invoked manually. Transient
    /// (not in `CodingKeys`): drives the row's "Verifying (byte-exact)…" label so a job that
    /// suddenly takes minutes reads as "deep-checking", not stuck.
    var isDeepVerifying: Bool = false

    /// True during the post-join *finishing* tail — the staged cross-volume move of the joined file
    /// into its destination (and the SRT sidecar stitch). Transient (not in `CodingKeys`): drives the
    /// row's "Finishing…" label so the full progress bar during a multi-GB move reads as "finalizing
    /// the file", not a stuck "Joining…". The ffmpeg join is done by the time this is set.
    var isFinishing: Bool = false

    /// Fraction of the bar's track allocated to *producing* the file (join + optional cross-volume
    /// move). The remainder is the verification tail. Produce keeps its own internal byte-weighting
    /// inside `progress` (join/move = 50/50 when staged, 100/0 when not), so this only decides the
    /// produce-vs-verify split. Verify is normally an ffprobe check of seconds, so it gets a thin
    /// tail; a long byte-exact escalation is surfaced by the row's "Verifying (byte-exact)…" label
    /// and the expanded detail bar rather than by widening this slice.
    static let producePortion: Double = 0.85

    /// The unified 0…1 fill for the row's single progress bar, telling one story across the whole
    /// lifecycle: produce (join + move, via `progress`) fills `[0, producePortion]`, then verification
    /// (`verificationProgress`) fills `[producePortion, 1]` — so the bar reaches 100% (and the green of
    /// `barFill`) only once the bytes are verified, never merely written. Produce caps at
    /// `producePortion` while active so the hand-off into the verify slice is continuous, with no
    /// backward jump. Kept on the model (not the view) so the phase math is unit-testable.
    var lifecycleFraction: Double {
        let p = Self.producePortion
        switch status {
        case .pending: return 0
        case .failed:  return 1                       // full track, painted red by the bar's fill
        case .completed, .active, .preparing, .cancelled:
            if verificationStatus == .verifying {
                return p + verificationProgress * (1 - p)
            }
            // A finished job with verification in a terminal state (or none pending) shows full;
            // a still-producing/stopped job caps at the produce slice.
            return status == .completed ? 1 : progress * p
        }
    }

    // Actual output files created (may differ from expected due to conflict resolution).
    // Stored as path strings for Codable conformance.
    private var actualOutputPathStrings: [String] = []

    /// URLs of actual output files created during conversion. Use this for verification instead of
    /// re-deriving from clip names.
    var actualOutputURLs: [URL] {
        get { actualOutputPathStrings.map { URL(fileURLWithPath: $0) } }
        set { actualOutputPathStrings = newValue.map { $0.path } }
    }

    /// Records an output file that was actually created during conversion.
    mutating func recordOutputURL(_ url: URL) {
        actualOutputPathStrings.append(url.path)
    }

    // MARK: - URL accessors

    var sourceFolderURL: URL {
        get { URL(fileURLWithPath: sourceFolderPathString) }
        set { sourceFolderPathString = newValue.path }
    }
    var destinationURL: URL {
        get { URL(fileURLWithPath: destinationPathString) }
        set { destinationPathString = newValue.path }
    }

    /// Resolves the source-folder bookmark to a security-scoped URL.
    /// - Returns: URL with security scope, or nil if the bookmark is invalid/stale.
    mutating func resolveSourceBookmark() -> URL? {
        guard let data = sourceBookmarkData else {
            return URL(fileURLWithPath: sourceFolderPathString)
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            if let newData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                sourceBookmarkData = newData
            }
        }
        sourceFolderPathString = url.path
        return url
    }

    /// Resolves the output bookmark to a security-scoped URL for the **output directory**.
    /// - Note: Returns the directory URL for security-scoped write access; it does **not** modify
    ///   `destinationPathString`, which must preserve the full output **file** path (with filename).
    mutating func resolveOutputBookmark() -> URL? {
        guard let data = outputBookmarkData else {
            return URL(fileURLWithPath: destinationPathString).deletingLastPathComponent()
        }
        var isStale = false
        guard let url = try? URL(
            resolvingBookmarkData: data,
            options: .withSecurityScope,
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        ) else {
            return nil
        }
        if isStale {
            if let newData = try? url.bookmarkData(
                options: .withSecurityScope,
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                outputBookmarkData = newData
            }
        }
        // Do NOT update destinationPathString here — the bookmark is for the directory, not the file.
        return url
    }

    /// Display name for the job (the output filename).
    var displayName: String {
        let ext = settings.outputContainer.fileExtension
        let lastComponent = destinationURL.lastPathComponent
        // If the destination already names a file with the right extension, use it verbatim.
        if lastComponent.lowercased().hasSuffix(".\(ext)") {
            return lastComponent
        }
        // Otherwise construct one from the filename setting / folder name.
        let baseName = settings.outputFilename.isEmpty ? folderName : settings.outputFilename
        return "\(baseName).\(ext)"
    }

    /// Expected output format string.
    var outputFormat: String { settings.outputContainer.rawValue }

    // MARK: - Job-level aggregates

    /// Total source content duration in seconds (sum of the group's segment durations). DJI
    /// segments carry an exact `CMTime`, so this sums `durationInSeconds` directly — no edit-unit
    /// or frame-rate conversion (P2toMXF's `ConversionJob` had to divide `totalDurationFrames`).
    var totalContentDurationSeconds: Double {
        clips.reduce(0) { $0 + $1.durationInSeconds }
    }

    /// Total on-disk size of all source segments in bytes (sum of `DJIClip.totalFileSize`).
    /// Used for the static queue-row sub-line so the user can see how large the source material is
    /// without opening the recording list.
    var totalSourceBytes: Int64 {
        clips.reduce(0) { $0 + $1.totalFileSize }
    }

    /// Best-effort total frame count across all segments, for progress display and verification's
    /// expected-frame check. `nil` if any segment lacks a probed frame rate — callers treat a `nil`
    /// expected-frame count as "no estimate" rather than a failure.
    var estimatedFrameCount: Int? {
        guard !clips.isEmpty else { return nil }
        var total = 0
        for clip in clips {
            guard let fps = clip.streamInfo?.video.framesPerSecond, fps > 0 else { return nil }
            total += Int((clip.durationInSeconds * fps).rounded())
        }
        return total
    }

    init(
        folderName: String,
        sourceFolderURL: URL,
        clips: [DJIClip],
        settings: ConversionSettings,
        destinationURL: URL,
        sourceBookmarkData: Data? = nil,
        outputBookmarkData: Data? = nil
    ) {
        self.id = UUID()
        self.folderName = folderName
        self.sourceFolderPathString = sourceFolderURL.path
        self.clips = clips
        self.settings = settings
        self.destinationPathString = destinationURL.path
        self.createdAt = Date()
        self.sourceBookmarkData = sourceBookmarkData
        self.outputBookmarkData = outputBookmarkData
    }

    /// Creates a job with security-scoped bookmarks from the provided URLs.
    /// - Note: Call this while the URLs have active security scope (e.g. from NSOpenPanel). The join
    ///   is always concat (one group → one file), so the output bookmark is the destination's parent.
    static func withBookmarks(
        folderName: String,
        sourceFolderURL: URL,
        clips: [DJIClip],
        settings: ConversionSettings,
        destinationURL: URL
    ) -> ConversionJob {
        let sourceBookmark = try? sourceFolderURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        let outputBookmark = try? destinationURL.deletingLastPathComponent().bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )

        return ConversionJob(
            folderName: folderName,
            sourceFolderURL: sourceFolderURL,
            clips: clips,
            settings: settings,
            destinationURL: destinationURL,
            sourceBookmarkData: sourceBookmark,
            outputBookmarkData: outputBookmark
        )
    }

    // Codable keys
    enum CodingKeys: String, CodingKey {
        case id, folderName, sourceFolderPathString, clips, settings
        case destinationPathString, createdAt, status, progress, startedAt
        case sourceBookmarkData, outputBookmarkData
        case verificationStatus, verificationResult, sourceTargetResult, verificationProgress
        case actualOutputPathStrings, appliedTimecode
    }
}
