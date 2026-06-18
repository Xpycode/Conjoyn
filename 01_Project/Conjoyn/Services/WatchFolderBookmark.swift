import Foundation

// MARK: - Watch Folder Bookmark (Wave 5B, task 5.7)

/// Persists a single watch-root URL across app launches by storing a plain (non-security-scoped)
/// `bookmarkData()` blob in `UserDefaults`.
///
/// **Why plain bookmarks, not security-scoped ones:**
/// App Sandbox is **disabled** for Conjoyn (direct-distribution, notarized, GPL FFmpeg). The
/// `.withSecurityScope` option is meaningful only inside the App Sandbox — calling it on a
/// sandboxless process is a no-op and wastes a few bytes of bookmark overhead. We use
/// `url.bookmarkData()` (no options) to record the inode/volume identity so the Finder can
/// rename or move the folder and we still re-resolve it correctly.
///
/// **TCC / removable-volume access:**
/// Resolving the bookmark does not grant access to a removable SD card; that is handled by
/// `NSRemovableVolumesUsageDescription` and the system TCC prompt, which fires when the app
/// first tries to enumerate files inside the resolved URL. This type is responsible only for
/// *remembering which folder* was chosen; TCC is handled separately by the watch-folder engine.
///
/// **Injectable defaults (testability):**
/// Pass a `UserDefaults(suiteName:)` instance in tests so the suite is fully isolated from
/// the real `UserDefaults.standard` domain — mirrors the injectable `storageDirectory` pattern
/// used by `SpeedTracker`.
/// `@unchecked Sendable`: the only stored reference type is `UserDefaults`, which Apple documents
/// as thread-safe, so sharing this value across concurrency domains is safe even though the
/// compiler can't prove it (UserDefaults is not itself `Sendable`).
struct WatchFolderBookmark: @unchecked Sendable {

    // MARK: - Defaults

    private let defaults: UserDefaults
    private let key: String

    // MARK: - Init

    /// - Parameters:
    ///   - defaults: The `UserDefaults` suite to persist into. Production code uses `.standard`;
    ///     tests pass an isolated `UserDefaults(suiteName:)` instance.
    ///   - key: The `UserDefaults` key under which the bookmark `Data` is stored.
    init(defaults: UserDefaults = .standard, key: String = "watchFolder.rootBookmark") {
        self.defaults = defaults
        self.key = key
    }

    // MARK: - Public API

    /// Creates a plain (non-security-scoped) bookmark for `url`.
    ///
    /// Separated from `save(url:)` so callers can create a bookmark without immediately
    /// persisting it (e.g. in a preview or migration path).
    ///
    /// - Throws: Whatever `URL.bookmarkData()` throws (typically `NSError` from the kernel
    ///   if the URL does not exist or the process lacks read permission at the moment of creation).
    static func makeBookmark(for url: URL) throws -> Data {
        // Plain bookmarkData — no .withSecurityScope because App Sandbox is disabled.
        try url.bookmarkData(
            options: [],
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
    }

    /// Persists a bookmark for `url` into `UserDefaults` under the configured key.
    ///
    /// - Throws: If `URL.bookmarkData()` fails (e.g. the directory no longer exists).
    func save(url: URL) throws {
        let data = try Self.makeBookmark(for: url)
        defaults.set(data, forKey: key)
    }

    /// Resolves the stored bookmark and returns the remembered URL, or `nil` if nothing
    /// is stored or resolution fails.
    ///
    /// **Stale bookmark:** macOS marks a bookmark stale when the target has been moved or
    /// renamed through Finder. When `isStale == true`, the resolved URL is still correct —
    /// the kernel followed the inode chain — but the stored blob is out-of-date. We
    /// immediately re-create and re-persist a fresh bookmark from the resolved URL so the
    /// next launch skips this repair step.
    ///
    /// - Returns: The resolved `URL` (a file-URL pointing at the original folder), or `nil`.
    func resolve() -> URL? {
        guard let data = defaults.data(forKey: key) else { return nil }

        var isStale = false
        do {
            // options: [] — no .withSecurityScope; sandbox is off so it would be a no-op.
            let resolved = try URL(
                resolvingBookmarkData: data,
                options: [],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )

            if isStale {
                // Re-persist so subsequent launches get a fresh bookmark.
                // Failure is non-fatal: the resolved URL is still usable this session.
                try? save(url: resolved)
            }

            return resolved
        } catch {
            // Bookmark is unresolvable (e.g. volume was erased). Clear it so the UI
            // doesn't keep attempting fruitless resolutions on every launch.
            clear()
            return nil
        }
    }

    /// Removes the stored bookmark, reverting to "no watch folder selected" state.
    func clear() {
        defaults.removeObject(forKey: key)
    }
}
