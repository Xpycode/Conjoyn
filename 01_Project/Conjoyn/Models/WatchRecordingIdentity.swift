import Foundation
import CoreMedia
import CryptoKit

/// Durable metadata identity, not a content hash. Distinct footage with identical descriptors
/// remains indistinguishable. Callers must bind metadata to the settled observed file generation,
/// pass stability/complete-set gates, and revalidate samples before admission. This type does no I/O.
struct WatchRecordingDescriptor: Codable, Equatable, Sendable {
    static let version = 2

    /// Nonnegative exact seconds, reduced without floating-point conversion or signed overflow.
    struct ExactDuration: Codable, Equatable, Sendable {
        let value: Int64
        let timescale: Int32

        init?(value: Int64, timescale: Int32) {
            guard value >= 0, timescale > 0 else { return nil }
            var a = value
            var b = Int64(timescale)
            while b != 0 { (a, b) = (b, a % b) }
            self.value = value / a
            self.timescale = Int32(Int64(timescale) / a)
        }

        private enum CodingKeys: String, CodingKey { case value, timescale }
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            let value = try container.decode(Int64.self, forKey: .value)
            let timescale = try container.decode(Int32.self, forKey: .timescale)
            guard let normalized = Self(value: value, timescale: timescale) else {
                throw DecodingError.dataCorruptedError(forKey: .timescale, in: container,
                                                       debugDescription: "Invalid exact duration")
            }
            self = normalized
        }
    }

    struct Clip: Codable, Equatable, Sendable {
        // Raw family spelling intentionally avoids CameraFamily's unknown→DJI decode fallback.
        var cameraFamily: String
        var stem: String
        var index: Int
        var variant: String?
        var recordingNumber: Int?
        /// Embedded capture date, rounded to nearest microsecond since Unix epoch. Never mtime.
        var captureMicroseconds: Int64?
        var duration: ExactDuration?
        /// Caller-provided path relative to the watch root; root mount path is never hashed.
        var relativePath: String
        /// Video-only byte size captured by the caller's settled sample, never a live stat.
        var settledVideoBytes: Int64?

        init(cameraFamily: String, stem: String, index: Int, variant: String?,
             recordingNumber: Int?, captureDate: Date?, duration: CMTime?,
             relativePath: String, settledVideoBytes: Int64?) {
            self.cameraFamily = cameraFamily
            self.stem = stem
            self.index = index
            self.variant = variant
            self.recordingNumber = recordingNumber
            self.captureMicroseconds = captureDate.flatMap {
                Int64(exactly: ($0.timeIntervalSince1970 * 1_000_000).rounded())
            }
            self.duration = duration.flatMap {
                guard $0.isNumeric, $0.epoch == 0 else { return nil }
                return ExactDuration(value: $0.value, timescale: $0.timescale)
            }
            self.relativePath = relativePath
            self.settledVideoBytes = settledVideoBytes
        }
    }

    let clips: [Clip]

    /// V2 wire format: UTF-8 fields prefixed by an unsigned 64-bit big-endian byte count;
    /// integers use ASCII decimal; optional fields have a one-byte 0/1 presence tag. Ordered
    /// clip count and schema version are encoded first. No locale, JSON key ordering, date
    /// formatting, random IDs, file system calls, or delimiter escaping affect these bytes.
    var canonicalData: Data {
        var bytes = Data()
        func field(_ string: String) {
            let utf8 = Data(string.utf8)
            var count = UInt64(utf8.count).bigEndian
            withUnsafeBytes(of: &count) { bytes.append(contentsOf: $0) }
            bytes.append(utf8)
        }
        func optional(_ string: String?) {
            bytes.append(string == nil ? 0 : 1)
            if let string { field(string) }
        }
        field("Conjoyn.watch-recording")
        field(String(Self.version))
        field(String(clips.count))
        for clip in clips {
            field(clip.cameraFamily)
            field(clip.stem)
            field(String(clip.index))
            optional(clip.variant)
            optional(clip.recordingNumber.map { String($0) })
            optional(clip.captureMicroseconds.map { String($0) })
            bytes.append(clip.duration == nil ? 0 : 1)
            if let duration = clip.duration {
                field(String(duration.value))
                field(String(duration.timescale))
            }
            field(clip.relativePath)
            optional(clip.settledVideoBytes.map { String($0) })
        }
        return bytes
    }

    var identity: WatchRecordingIdentity {
        var reasons = Set<WatchRecordingIdentity.WeakReason>()
        if clips.isEmpty { reasons.insert(.emptyRecording) }
        for clip in clips {
            if clip.captureMicroseconds == nil { reasons.insert(.missingCaptureDate) }
            if clip.duration == nil { reasons.insert(.missingDuration) }
            if clip.settledVideoBytes == nil || (clip.settledVideoBytes ?? 0) < 0 {
                reasons.insert(.missingSettledSize)
            }
            if clip.cameraFamily != "dji" && clip.cameraFamily != "goPro" {
                reasons.insert(.unknownCameraFamily)
            }
            if clip.cameraFamily == "goPro" && (clip.recordingNumber == nil || (clip.recordingNumber ?? 0) < 0) {
                reasons.insert(.missingRecordingNumber)
            }
            if clip.stem.isEmpty || clip.index < 0 { reasons.insert(.invalidClipName) }
            let components = clip.relativePath.split(separator: "/", omittingEmptySubsequences: false)
            if components.contains(where: { $0.isEmpty || $0 == "." || $0 == ".." }) || clip.relativePath.contains("\0") {
                reasons.insert(.invalidRelativePath)
            }
        }
        let digest = SHA256.hash(data: canonicalData).map { String(format: "%02x", $0) }.joined()
        return WatchRecordingIdentity(version: Self.version, digest: digest,
                                      weakReasons: reasons.sorted { $0.rawValue < $1.rawValue })
    }
}

struct WatchRecordingIdentity: Equatable, Sendable {
    enum Strength: String, Sendable { case strong, weak }
    enum WeakReason: String, Hashable, Sendable {
        case emptyRecording, missingCaptureDate, missingDuration, missingSettledSize
        case unknownCameraFamily, missingRecordingNumber, invalidClipName, invalidRelativePath
    }
    let version: Int
    let digest: String
    let weakReasons: [WeakReason]
    var strength: Strength { weakReasons.isEmpty ? .strong : .weak }
    var ledgerKey: String { "v\(version):\(digest)" }
}

/// Required ownership for new watch jobs survives disabled/removed entries and root remounts.
/// The ledger namespace is a stable storage identifier, not the current root URL. The optional
/// property on ConversionJob alone provides compatibility for pre-existing/manual jobs.
struct WatchIdentitySnapshot: Codable, Equatable, Sendable {
    let version: Int
    let watchEntryID: UUID
    let ledgerNamespace: String
    let descriptor: WatchRecordingDescriptor
    var identity: WatchRecordingIdentity { descriptor.identity }

    init(watchEntryID: UUID, ledgerNamespace: String, descriptor: WatchRecordingDescriptor) {
        self.version = WatchRecordingDescriptor.version
        self.watchEntryID = watchEntryID
        self.ledgerNamespace = ledgerNamespace
        self.descriptor = descriptor
    }

    private enum CodingKeys: String, CodingKey { case version, watchEntryID, ledgerNamespace, descriptor }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        guard version == WatchRecordingDescriptor.version else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container,
                                                   debugDescription: "Unsupported watch identity version")
        }
        watchEntryID = try container.decode(UUID.self, forKey: .watchEntryID)
        ledgerNamespace = try container.decode(String.self, forKey: .ledgerNamespace)
        guard !ledgerNamespace.isEmpty else {
            throw DecodingError.dataCorruptedError(forKey: .ledgerNamespace, in: container,
                                                   debugDescription: "Missing watch ledger ownership")
        }
        descriptor = try container.decode(WatchRecordingDescriptor.self, forKey: .descriptor)
    }
}
