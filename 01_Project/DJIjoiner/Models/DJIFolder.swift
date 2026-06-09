import Foundation

// MARK: - DJI Folder (Wave 1, task 1.3)

/// A discovered DCIM media folder and the clips parsed from it — the DJIjoiner analogue of
/// P2toMXF's `P2Card`. The folder reader (task 2.3) validates a `DCIM/100MEDIA`-style directory,
/// parses each media file, and returns this shape; the grouping engine (task 2.4) then partitions
/// `clips` into `RecordGroup`s. Stored root path as a `String` (exposed as `URL`) to stay `Codable`.
struct DJIFolder: Identifiable, Codable, Sendable {
    let id: UUID
    private let rootPathString: String
    let clips: [DJIClip]
    let parseErrors: [ClipParseError]

    /// URL to the media folder root.
    var rootURL: URL { URL(fileURLWithPath: rootPathString) }

    /// Folder name derived from the path (e.g. `100MEDIA`).
    var name: String { rootURL.lastPathComponent }

    /// Number of successfully parsed clips.
    var clipCount: Int { clips.count }

    /// Whether any media file failed to parse.
    var hasParseErrors: Bool { !parseErrors.isEmpty }

    init(rootURL: URL, clips: [DJIClip], parseErrors: [ClipParseError] = []) {
        self.id = UUID()
        self.rootPathString = rootURL.path
        self.clips = clips
        self.parseErrors = parseErrors
    }

    enum CodingKeys: String, CodingKey {
        case id, rootPathString, clips, parseErrors
    }
}
