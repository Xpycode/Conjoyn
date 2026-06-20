import Foundation
import CryptoKit

// MARK: - Processed Group Ledger (Wave 5A, task 5.4)

/// Persists fingerprints of `RecordGroup`s that have already been joined, breaking the
/// re-join-forever loop that occurs when a watch-folder fires while joined source files are still
/// on disk. The queue's in-process dedup only covers *unfinished* jobs; this ledger covers the
/// completed ones.
///
/// Value type: the watch-folder coordinator owns serialization, so no actor wrapper is needed here.
/// The coordinator holds one instance and mutates it on its serial queue.
struct ProcessedGroupLedger: Sendable {

    // MARK: - Persistence constants

    private static let fileName = "processed_groups.json"

    // MARK: - Storage

    /// The set of fingerprints that have been durably recorded as processed.
    private var fingerprints: Set<String>

    /// Where `processed_groups.json` lives. `nil` only if the app-support directory could not be
    /// located (ledger then operates purely in-memory; the dedup benefit degrades to session-only).
    private let fileURL: URL?

    // MARK: - Init

    /// Loads any previously saved fingerprints from `storageDirectory`.
    ///
    /// - Parameter storageDirectory: Directory to read/write `processed_groups.json` in. `nil`
    ///   (the default, used by the production coordinator) resolves to
    ///   `~/Library/Application Support/Conjoyn`. Tests pass a temp dir.
    init(storageDirectory: URL? = nil) {
        let dir: URL?
        if let storageDirectory {
            dir = storageDirectory
        } else {
            dir = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Conjoyn", isDirectory: true)
        }

        if let dir {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            self.fileURL = dir.appendingPathComponent(Self.fileName)
        } else {
            self.fileURL = nil
        }

        self.fingerprints = Self.load(from: fileURL)
    }

    // MARK: - Public API

    /// Returns `true` when this group's fingerprint is already in the ledger.
    func contains(_ group: RecordGroup) -> Bool {
        fingerprints.contains(Self.fingerprint(for: group))
    }

    /// The full set of recorded fingerprints. Lets a caller (e.g. `WatchFolderCoordinator`) hand
    /// the durable, relaunch-restored processed set to the pure `WatchFolderReconciler` without the
    /// ledger having to expose its storage. Loaded from disk at `init`, so it survives relaunch —
    /// which is what keeps an already-joined group (whose source clips remain on the card) from
    /// being re-enqueued after a restart.
    var allFingerprints: Set<String> { fingerprints }

    /// Records the group's fingerprint and persists the updated ledger to disk.
    mutating func insert(_ group: RecordGroup) {
        fingerprints.insert(Self.fingerprint(for: group))
        save()
    }

    // MARK: - Fingerprinting

    /// A deterministic, process-stable fingerprint for `group`.
    ///
    /// Feeds each clip's **stable** identity fields — `stem`, `index`, and `variantSuffix` — into
    /// a pipe-delimited token per clip, then joins all tokens with `";"` and hashes the resulting
    /// UTF-8 string with SHA-256 (CryptoKit, available on macOS 14+).
    ///
    /// `DJIClip.id` (UUID) is intentionally excluded: it is freshly minted on every parse and
    /// would make the fingerprint non-repeatable across rescans and relaunches.
    ///
    /// Properties:
    ///   - Same ordered clip identities ⇒ same fingerprint, every process.
    ///   - Different clip order ⇒ different fingerprint.
    ///   - Same stems but different `variantSuffix` ⇒ different fingerprint.
    static func fingerprint(for group: RecordGroup) -> String {
        let token = group.clips.map { clip in
            "\(clip.stem)|\(clip.index)|\(clip.variantSuffix ?? "")"
        }.joined(separator: ";")

        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    /// Writes the current fingerprint set to disk as a JSON array of strings.
    /// Non-fatal: failures are silently discarded in production (logged in DEBUG) so a disk error
    /// does not crash the coordinator — the dedup benefit merely reverts to session-only for that run.
    func save() {
        guard let fileURL else { return }
        do {
            let sorted = fingerprints.sorted() // deterministic on-disk ordering for readability
            let data = try JSONEncoder().encode(sorted)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            #if DEBUG
            print("[ProcessedGroupLedger] save failed: \(error)")
            #endif
        }
    }

    // MARK: - Private helpers

    /// Reads fingerprints from `fileURL`. Returns an empty set on any error (missing file, decode
    /// failure) so the caller can always assign the result without guarding.
    private static func load(from fileURL: URL?) -> Set<String> {
        guard let fileURL,
              FileManager.default.fileExists(atPath: fileURL.path) else { return [] }
        do {
            let data = try Data(contentsOf: fileURL)
            let array = try JSONDecoder().decode([String].self, from: data)
            return Set(array)
        } catch {
            #if DEBUG
            print("[ProcessedGroupLedger] load failed: \(error)")
            #endif
            return []
        }
    }
}
