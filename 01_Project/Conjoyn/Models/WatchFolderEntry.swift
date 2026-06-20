import Foundation

// MARK: - Watch Folder Entry (Wave 5D)

/// One user-configured watch folder in the multi-folder manager. Each entry owns its own root,
/// optional output destination, enabled flag, and tunable settings — so the user can run several
/// independent ingest folders (e.g. one SD-card mount and one local drop folder) at once.
///
/// **Storage:** the whole list of entries is persisted by `WatchFolderManager` as a single Codable
/// JSON blob. The bookmarks are **plain** (non-security-scoped) — App Sandbox is disabled, so a
/// security-scoped bookmark would be a no-op (see `WatchFolderBookmark` for the full rationale).
/// Removable-volume (SD-card) access remains gated by TCC / `NSRemovableVolumesUsageDescription`,
/// which a bookmark cannot satisfy — only the user's consent prompt can.
struct WatchFolderEntry: Identifiable, Codable, Equatable, Sendable {

    /// Stable identity, also used to namespace this entry's per-folder persistence
    /// (bookmark UserDefaults key + ledger/group-state storage subdirectory).
    let id: UUID

    /// Plain bookmark to the watched root. Resolved on demand; survives Finder renames/moves.
    var rootBookmark: Data

    /// Last-known display path of the root, shown when the bookmark can't currently resolve
    /// (e.g. the SD card is ejected) so the row still reads meaningfully.
    var rootPath: String

    /// Plain bookmark to the user-chosen output folder. `nil` ⇒ joined files land next to the
    /// source inside the watched root (the v1 default).
    var outputBookmark: Data?

    /// Last-known display path of the output folder (mirrors `rootPath`).
    var outputPath: String?

    /// Whether this folder is actively monitored. The manager starts/stops a coordinator to match.
    var enabled: Bool

    /// Per-folder tunables (quiet window, stable polls, split threshold, poll cadence). Independent
    /// per entry so a fast local drop folder and a slow card reader can be tuned separately.
    var settings: WatchFolderSettings

    init(
        id: UUID,
        rootBookmark: Data,
        rootPath: String,
        outputBookmark: Data? = nil,
        outputPath: String? = nil,
        enabled: Bool = true,
        settings: WatchFolderSettings = .defaults
    ) {
        self.id = id
        self.rootBookmark = rootBookmark
        self.rootPath = rootPath
        self.outputBookmark = outputBookmark
        self.outputPath = outputPath
        self.enabled = enabled
        self.settings = settings
    }

    // MARK: - Resolution

    /// Resolves the root bookmark to a live URL, or `nil` if it can't be resolved this launch
    /// (volume erased/offline). Does **not** re-persist on staleness — the manager owns persistence.
    var resolvedRootURL: URL? { Self.resolve(rootBookmark) }

    /// Resolves the output bookmark, or `nil` when no dedicated output folder was chosen.
    var resolvedOutputURL: URL? { outputBookmark.flatMap(Self.resolve) }

    /// A short, human label for the root (the folder's own name).
    var rootDisplayName: String {
        resolvedRootURL?.lastPathComponent ?? (rootPath as NSString).lastPathComponent
    }

    /// A short, human label for the output ("Next to source" when none chosen).
    var outputDisplayName: String {
        if let url = resolvedOutputURL { return url.lastPathComponent }
        if let path = outputPath { return (path as NSString).lastPathComponent }
        return "Next to source"
    }

    // MARK: - Bookmark helpers

    /// Plain bookmark for `url` — no `.withSecurityScope` (sandbox is off → it would be inert).
    static func makeBookmark(for url: URL) throws -> Data {
        try url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
    }

    /// Resolves a plain bookmark to a URL, returning `nil` on failure. Staleness is tolerated:
    /// the kernel still follows the inode chain, so the URL is usable even when the blob is stale.
    static func resolve(_ data: Data) -> URL? {
        var isStale = false
        return try? URL(
            resolvingBookmarkData: data,
            options: [],
            relativeTo: nil,
            bookmarkDataIsStale: &isStale
        )
    }
}
