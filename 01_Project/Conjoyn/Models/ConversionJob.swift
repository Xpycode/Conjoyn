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

    // Verification state.
    var verificationStatus: VerificationStatus = .unverified
    var verificationResult: VerificationResult?
    var sourceTargetResult: SourceTargetResult?
    var verificationProgress: Double = 0.0  // 0.0 to 1.0

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
        case actualOutputPathStrings
    }
}
