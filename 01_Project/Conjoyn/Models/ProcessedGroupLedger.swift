import Foundation
import CryptoKit

/// Enqueue-time admission history (not proof of completed exports). One serial owner per namespace.
/// V1 bytes remain at their original URL. V2 decisions live in a separate versioned file; legacy
/// hashes are evidence of ambiguity only in the v2 API, never a permanent dedup fallback.
struct ProcessedGroupLedger: Sendable {
    enum Classification: Equatable, Sendable {
        case knownV2, newRecording, legacyAmbiguous
        case weak([WatchRecordingIdentity.WeakReason])
        case storageUnavailable(String)
    }

    enum Resolution: String, Codable, Sendable {
        /// Authorization only: readiness, live-job dedup and both durability gates still apply.
        case processOnce
        case alreadyProcessed
        /// Queue persistence must succeed before this is committed; processing must wait for it.
        case admitted
    }

    enum LedgerError: Error, LocalizedError {
        case unavailable(String), unsupportedIdentity, weakIdentity, invalidFormat
        var errorDescription: String? {
            switch self {
            case .unavailable(let reason): return reason
            case .unsupportedIdentity: return "Unsupported recording identity."
            case .weakIdentity: return "Weak recording identity requires an explicit process-once decision before admission."
            case .invalidFormat: return "Unsupported or corrupt processed-recording history."
            }
        }
    }

    private struct Storage: Codable, Sendable {
        var version = 2
        var legacyFingerprints: Set<String> = []
        var resolutions: [String: Resolution] = [:]
    }

    private var storage = Storage()
    private let fileURL: URL?
    private let write: @Sendable (Data, URL) throws -> Void
    /// Read errors permanently protect both files for this instance. Reopen after storage repair.
    private var loadFailure: String?
    /// Write failures are retryable; uncommitted changes are never published in memory.
    private(set) var persistenceError: String?

    init(storageDirectory: URL? = nil,
         write: @escaping @Sendable (Data, URL) throws -> Void = {
             try $0.write(to: $1, options: .atomic)
         }) {
        self.write = write
        let directory = storageDirectory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Conjoyn", isDirectory: true)
        fileURL = directory?.appendingPathComponent("processed_groups_v2.json")
        do {
            guard let directory, let fileURL else {
                throw LedgerError.unavailable("Processed-recording storage is unavailable.")
            }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            if let bytes = try Self.readIfPresent(fileURL) {
                let decoded = try JSONDecoder().decode(Storage.self, from: bytes)
                guard decoded.version == 2,
                      decoded.resolutions.keys.allSatisfy(Self.isV2Key) else {
                    throw LedgerError.invalidFormat
                }
                storage = decoded
            }
            // Always read original history too: a corrupt/unknown original must not be silently
            // treated as empty, even if a v2 file exists. Neither input is overwritten on load.
            let legacyURL = directory.appendingPathComponent("processed_groups.json")
            if let bytes = try Self.readIfPresent(legacyURL) {
                storage.legacyFingerprints.formUnion(try JSONDecoder().decode([String].self, from: bytes))
            }
        } catch {
            loadFailure = error.localizedDescription
            persistenceError = error.localizedDescription
        }
    }

    // MARK: - V2 API

    func classify(_ identity: WatchRecordingIdentity, legacyFingerprint: String) -> Classification {
        if let persistenceError { return .storageUnavailable(persistenceError) }
        guard identity.version == WatchRecordingDescriptor.version, Self.isV2Key(identity.ledgerKey) else {
            return .storageUnavailable(LedgerError.unsupportedIdentity.localizedDescription)
        }
        guard identity.strength == .strong else { return .weak(identity.weakReasons) }
        switch resolution(for: identity) {
        case .admitted, .alreadyProcessed: return .knownV2
        case .processOnce: return .newRecording
        case nil:
            return storage.legacyFingerprints.contains(legacyFingerprint) ? .legacyAmbiguous : .newRecording
        }
    }

    /// The durable decision only. Call classification as well before authorizing any new work.
    func resolution(for identity: WatchRecordingIdentity) -> Resolution? {
        storage.resolutions[identity.ledgerKey]
    }

    /// Explicit decisions bind one exact v2 descriptor. No policy is chosen automatically.
    /// Weak identities still classify as weak after a decision; callers must inspect the decision
    /// separately, revalidate the descriptor and never describe this as strong recording identity.
    mutating func resolve(_ identity: WatchRecordingIdentity, as resolution: Resolution) throws {
        if let loadFailure { throw LedgerError.unavailable(loadFailure) }
        guard identity.version == WatchRecordingDescriptor.version, Self.isV2Key(identity.ledgerKey) else {
            throw LedgerError.unsupportedIdentity
        }
        if identity.strength == .weak, resolution == .admitted,
           storage.resolutions[identity.ledgerKey] == nil {
            throw LedgerError.weakIdentity
        }
        // Idempotent retries/clicks cannot reopen an already sealed recording.
        if let existing = storage.resolutions[identity.ledgerKey],
           existing == .admitted || existing == .alreadyProcessed {
            if persistenceError != nil { try persist(storage) }
            return
        }
        var candidate = storage
        candidate.resolutions[identity.ledgerKey] = resolution
        try persist(candidate)
    }

    /// Caller must first durably save the pending queue job, then commit here, then release its
    /// processing gate. On failure retain/retry the pending job; do not enqueue a second copy.
    mutating func commitAdmission(_ identity: WatchRecordingIdentity) throws {
        try resolve(identity, as: .admitted)
    }

    // MARK: - Transitional V1 production API (retire when W3 switches callers)

    func contains(_ group: RecordGroup) -> Bool {
        storage.legacyFingerprints.contains(Self.fingerprint(for: group))
    }

    var allFingerprints: Set<String> { storage.legacyFingerprints }

    @discardableResult
    mutating func insert(_ group: RecordGroup) -> Bool {
        var candidate = storage
        candidate.legacyFingerprints.insert(Self.fingerprint(for: group))
        do {
            try persist(candidate)
            return true
        } catch { return false }
    }

    /// Legacy compatibility hash only. New callers use WatchRecordingDescriptor.identity.
    static func fingerprint(for group: RecordGroup) -> String {
        let token = group.clips.map { clip in
            "\(clip.stem)|\(clip.index)|\(clip.variantSuffix ?? "")"
        }.joined(separator: ";")

        let digest = SHA256.hash(data: Data(token.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Persistence

    /// Retry a failed write of the last committed state. Failed candidate decisions must be
    /// retried explicitly by their owner; save() cannot silently admit unqueued/cancelled work.
    @discardableResult
    mutating func save() -> Bool {
        do {
            try persist(storage)
            return true
        } catch { return false }
    }

    private mutating func persist(_ candidate: Storage) throws {
        do {
            if let loadFailure { throw LedgerError.unavailable(loadFailure) }
            guard let fileURL else { throw LedgerError.unavailable("Processed-recording storage is unavailable.") }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try write(encoder.encode(candidate), fileURL)
            storage = candidate
            persistenceError = nil
        } catch {
            persistenceError = error.localizedDescription
            throw error
        }
    }

    private static func isV2Key(_ key: String) -> Bool {
        key.hasPrefix("v2:") && key.utf8.count == 67 && key.dropFirst(3).utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    /// Only ENOENT is a normal first launch. Permissions, directories and all other read failures
    /// protect the existing path instead of degrading to an empty ledger.
    private static func readIfPresent(_ url: URL) throws -> Data? {
        do { return try Data(contentsOf: url) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
    }
}
