import Foundation

// MARK: - Saved Rename Templates

/// The user's saved rename patterns — the persistent layer on top of the session-only
/// `RenamePatternEngine.Options`. A template is just a pattern string (counter start/digits stay
/// per-batch settings, same semantics as the built-in presets); the popover renders each one as a
/// chip labelled with the pattern itself, so no naming UI exists.
///
/// Stored as a Codable JSON blob under a single UserDefaults key, the `WatchFolderSettings` idiom:
/// `load` falls back to `.empty` on a missing or corrupt blob (treated as "never written").
struct RenameTemplates: Codable, Equatable, Sendable {

    /// Saved patterns in the order the user saved them. Unique — `add` no-ops on a duplicate.
    private(set) var patterns: [String]

    static let empty = RenameTemplates(patterns: [])

    // MARK: - Mutations

    /// Saves `pattern` (whitespace-trimmed). No-ops when the trimmed pattern is empty or already
    /// saved — the popover only offers saving when `canSave`, so this is belt-and-braces.
    mutating func add(_ pattern: String) {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !patterns.contains(trimmed) else { return }
        patterns.append(trimmed)
    }

    /// Removes a saved pattern (exact match). Unknown patterns no-op.
    mutating func remove(_ pattern: String) {
        patterns.removeAll { $0 == pattern }
    }

    /// Whether the save affordance has anything new to offer: the trimmed pattern is non-empty,
    /// not one of the built-in `RenamePatternEngine.presets`, and not already saved. The popover
    /// hides its ＋ chip when this is false, so a visible ＋ always does something.
    func canSave(_ pattern: String) -> Bool {
        let trimmed = pattern.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !patterns.contains(trimmed) else { return false }
        return !RenamePatternEngine.presets.contains { $0.pattern == trimmed }
    }

    // MARK: - Persistence

    /// UserDefaults key under which the JSON blob is stored.
    static let defaultsKey = "rename.templates"

    /// Loads templates from `store`, falling back to `.empty` on any error (missing key,
    /// corrupt JSON, type mismatch).
    static func load(from store: UserDefaults = .standard) -> RenameTemplates {
        guard let data = store.data(forKey: defaultsKey) else { return .empty }
        return (try? JSONDecoder().decode(RenameTemplates.self, from: data)) ?? .empty
    }

    /// Encodes the receiver and writes it to `store`. Silently no-ops on encode failure (should
    /// be impossible for a `Codable` struct with primitive fields).
    func save(to store: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        store.set(data, forKey: RenameTemplates.defaultsKey)
    }
}
