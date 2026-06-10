import Foundation

// MARK: - Conversion Settings (Wave 1, task 1.3)

/// User-tunable settings for one join. Kept deliberately **lean** — only the knobs Conjoyn
/// actually has today; P2toMXF's `processingMode`/`audioMapping`/`generateReport`/`includeChecksum`
/// are dropped and new knobs are added as features land. `outputDirectory` is stored as a `String`
/// path (exposed as `URL`) so the whole value stays `Codable` for queue persistence.
struct ConversionSettings: Codable, Sendable {
    private var outputDirectoryPath: String?

    /// Explicit output filename (without extension). Empty → derived from the folder name.
    var outputFilename: String = ""
    /// When true, use the source DCIM folder name as the output filename.
    var useFolderNameAsFilename: Bool = false
    /// Output container for the joined file.
    var outputContainer: OutputContainer = .mp4
    /// Stamp the source start timecode onto the output `tmcd` track.
    var preserveTimecode: Bool = true
    /// Repair the timecode↔creation-date metadata on the joined file (task 2.8).
    var fixCreationDate: Bool = true
    /// Manual recording-start override (task 2.8). When set, it wins over every auto-detected signal
    /// in `RecordingStartResolver` and supplies both the stamped `creation_time` and start timecode.
    /// `nil` → fall back to the resolver's SRT→filename→creation_time→filesystem chain. (Override UI
    /// lands in Wave 6; the model + plumbing exist now so the resolver has a place to read it.)
    var dateOverride: Date?
    /// Stitch the per-segment `.SRT` telemetry into one offset-corrected sidecar (Wave 3).
    var stitchSRT: Bool = true
    /// Re-encode instead of refusing when segments fail the `-c copy` parameter guard.
    /// Off by default — lossless copy is the whole point; re-encode is an explicit opt-in.
    var reEncodeOnMismatch: Bool = false
    /// Delete the source segments only after the output verifies successfully.
    var deleteOriginalsAfterVerify: Bool = false

    /// Output directory URL (derived from the stored path).
    var outputDirectory: URL? {
        get { outputDirectoryPath.map { URL(fileURLWithPath: $0) } }
        set { outputDirectoryPath = newValue?.path }
    }

    /// Container format for the joined output.
    enum OutputContainer: String, CaseIterable, Codable, Sendable {
        case mp4 = "MP4"
        case mov = "MOV"

        /// Lowercase file extension for use in filenames.
        var fileExtension: String { rawValue.lowercased() }
    }

    init() {}

    // Custom keys so the computed `outputDirectory` isn't encoded directly.
    enum CodingKeys: String, CodingKey {
        case outputDirectoryPath
        case outputFilename
        case useFolderNameAsFilename
        case outputContainer
        case preserveTimecode
        case fixCreationDate
        case dateOverride
        case stitchSRT
        case reEncodeOnMismatch
        case deleteOriginalsAfterVerify
    }
}
