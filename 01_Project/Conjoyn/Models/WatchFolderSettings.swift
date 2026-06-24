import Foundation

// MARK: - Watch-Folder Settings (Wave 5B, task 5.8)

/// User-tunable knobs for the watch-folder state machine. Stored as Codable JSON under a single
/// UserDefaults key so the whole blob evolves together (partial blobs from earlier app versions
/// decode cleanly via `decodeIfPresent` fallback in `init(from:)`).
///
/// The bookmark that points to the watched root is **not** stored here — it lives in
/// `WatchFolderBookmark` (task 5.7) in a separate UserDefaults key so the security-scoped data
/// and the tunable numbers can be updated independently.
struct WatchFolderSettings: Codable, Equatable, Sendable {

    // MARK: - Fields

    /// Whether the watch-folder is active. Off by default — the user must opt in by picking a root.
    var enabled: Bool

    /// How many consecutive identical `(size, mtime)` samples `FileStabilityGate` requires before
    /// treating a file as settled and safe to read. Default `3` ≈ 2.25 s at the default poll cadence.
    var requiredStablePolls: Int

    /// Seconds a record group must stay quiet (no new members or size changes) before
    /// `CompleteSetGate` treats it as finished. Default 45 s — long enough to survive a brief
    /// copy pause on a slow reader, short enough to not delay ingest noticeably.
    var quietWindow: TimeInterval

    /// Segment size at or above which `CompleteSetGate` expects a continuation segment to follow.
    /// Set to 3 900 000 000 bytes (~3.63 GiB) — just below the ~3.7 GiB real FAT32 ceiling that
    /// DJI cameras use for a full segment. A last segment that stopped a few MB short of that
    /// ceiling (e.g. recording ended mid-file) still reads as "final" rather than "still filling",
    /// which avoids a false-wait on groups that are already complete.
    var splitThreshold: Int64

    /// Sampler cadence in seconds — how often the stability gate collects a `(size, mtime)` snapshot
    /// for each candidate file. 0.75 s gives three samples in ~2.25 s, matching the default
    /// `requiredStablePolls`. Tune lower for faster response, higher to reduce I/O on large card
    /// mounts with many files.
    var pollInterval: TimeInterval

    /// Maximum seconds a single **discovery** pass (the per-clip ffprobe scan of the whole watched
    /// root) may run before the coordinator abandons it, reuses the last known groups, and retries on
    /// the next tick. This bounds a wedged ffprobe / stalled mount so it can't latch discovery forever
    /// and silently kill the watcher. Default 90 s — generous for a cold scan of a full card, while
    /// still recovering from a true hang. The cheap re-sample cadence runs on a separate latch, so a
    /// timed-out discovery never blocks in-flight groups from settling.
    var discoverTimeout: TimeInterval

    // MARK: - Defaults

    /// A settings instance with every field at its sane default.
    /// Use `WatchFolderSettings.defaults` at startup and as the fallback for any decode error.
    static let defaults = WatchFolderSettings(
        enabled: false,
        requiredStablePolls: 3,
        quietWindow: 45,
        splitThreshold: 3_900_000_000,
        pollInterval: 0.75,
        discoverTimeout: 90
    )

    // MARK: - Init

    init(
        enabled: Bool = false,
        requiredStablePolls: Int = 3,
        quietWindow: TimeInterval = 45,
        splitThreshold: Int64 = 3_900_000_000,
        pollInterval: TimeInterval = 0.75,
        discoverTimeout: TimeInterval = 90
    ) {
        self.enabled = enabled
        self.requiredStablePolls = requiredStablePolls
        self.quietWindow = quietWindow
        self.splitThreshold = splitThreshold
        self.pollInterval = pollInterval
        self.discoverTimeout = discoverTimeout
    }

    // MARK: - Codable: forward-compatible decode

    enum CodingKeys: String, CodingKey {
        case enabled
        case requiredStablePolls
        case quietWindow
        case splitThreshold
        case pollInterval
        case discoverTimeout
    }

    /// Decodes a partial blob by falling back to the field default for any missing key.
    /// This means blobs written by earlier app versions (before a new field existed) still
    /// produce a fully-populated value with no decode error.
    init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = WatchFolderSettings.defaults
        enabled             = try c.decodeIfPresent(Bool.self,          forKey: .enabled)             ?? d.enabled
        requiredStablePolls = try c.decodeIfPresent(Int.self,           forKey: .requiredStablePolls) ?? d.requiredStablePolls
        quietWindow         = try c.decodeIfPresent(TimeInterval.self,  forKey: .quietWindow)         ?? d.quietWindow
        splitThreshold      = try c.decodeIfPresent(Int64.self,         forKey: .splitThreshold)      ?? d.splitThreshold
        pollInterval        = try c.decodeIfPresent(TimeInterval.self,  forKey: .pollInterval)        ?? d.pollInterval
        discoverTimeout     = try c.decodeIfPresent(TimeInterval.self,  forKey: .discoverTimeout)     ?? d.discoverTimeout
    }

    // MARK: - Persistence

    /// UserDefaults key under which the JSON blob is stored.
    static let defaultsKey = "watchFolder.settings"

    /// Loads settings from `store`, falling back to `.defaults` on any error (missing key,
    /// corrupt JSON, type mismatch). Non-fatal: a broken blob is treated as "never written".
    static func load(from store: UserDefaults = .standard) -> WatchFolderSettings {
        guard let data = store.data(forKey: defaultsKey) else { return .defaults }
        return (try? JSONDecoder().decode(WatchFolderSettings.self, from: data)) ?? .defaults
    }

    /// Encodes the receiver and writes it to `store`. Silently no-ops on encode failure (should
    /// be impossible for a `Codable` struct with primitive fields).
    func save(to store: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        store.set(data, forKey: WatchFolderSettings.defaultsKey)
    }
}
