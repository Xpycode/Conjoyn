import Foundation

// MARK: - Source↔Target Verification Models

// Result/value types for the true source↔target verification (Tier 0/1/2). The output of a lossless
// concat join should match the concatenation of the sources; these types carry the per-check verdicts
// and roll them up into one worst-wins seal for the queue. All `Sendable` so they cross the actor
// boundary from `SourceTargetVerifier` (off-main `Process`) back to the `@MainActor` queue cleanly.

/// Severity of a single verification check. Raw `Int` so "worst-wins" rolls up via `max`.
enum CheckSeverity: Int, Comparable, Codable, Sendable {
    case pass = 0     // Matched exactly / within tolerance.
    case info = 1     // Matched within tolerance, worth noting (e.g. sub-frame duration delta).
    case warning = 2  // Anomaly that didn't outright fail (escalate to byte-exact hash).
    case fail = 3     // Definitive mismatch — something was lost or corrupted.

    static func < (lhs: CheckSeverity, rhs: CheckSeverity) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Tolerant decode (see `VerificationCheck.Kind.init(from:)` for the full rationale). An
    /// unrecognised severity clamps to `.warning` rather than throwing: a value this build doesn't
    /// know is worth surfacing, and it must never be able to discard the persisted queue.
    init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(Int.self)
        self = CheckSeverity(rawValue: raw) ?? .warning
    }
}

/// The return value of a pure comparator — a severity plus an optional human detail. Mapped into a
/// `VerificationCheck` (with its `kind`/`label`) by the verifier.
enum CheckOutcome: Equatable, Sendable {
    case pass
    case info(String)
    case warning(String)
    case fail(String)

    var severity: CheckSeverity {
        switch self {
        case .pass: return .pass
        case .info: return .info
        case .warning: return .warning
        case .fail: return .fail
        }
    }

    /// The attached human-readable detail, or `nil` for a clean `.pass`.
    var detail: String? {
        switch self {
        case .pass: return nil
        case .info(let message), .warning(let message), .fail(let message): return message
        }
    }
}

/// One verification check's verdict, ready for persistence and display.
struct VerificationCheck: Codable, Sendable, Equatable {
    /// Which comparison produced this check.
    enum Kind: String, Codable, Sendable {
        case readability    // Tier 0: output decodes / packet-count probe exits 0.
        case packetCount    // Tier 1: output packet count == Σ(sources), exact.
        case packetBytes    // Tier 1: output packet bytes == Σ(sources), exact.
        case duration       // Tier 1: output duration ≈ Σ(source durations), ±1 frame.
        case avDrift        // Tier 1: output v:0 vs a:0 duration within tolerance.
        case codecParams    // Tier 1: codec params identical across segments + output.
        case timecodeWriteback  // Tier 1 (metadata): output `tmcd` matches the assigned start timecode.
        // Named `gpmdParity`, not `telemetryParity`: `QueuePersistenceCompatTests` (G0.3) already
        // uses the JSON string "telemetryParity" as its stand-in for "a kind this build doesn't
        // recognize yet" — reusing that literal here would turn a protected test's placeholder into
        // a real, decodable case and break it.
        case gpmdParity     // Tier 1 (GoPro only): gpmd packet-count/bytes parity, mirroring
                            // `packetCount`/`packetBytes` for the telemetry stream (decision 4 —
                            // selected by absolute index, never `d:0`).
        case hashMatch      // Tier 2: per-stream packet MD5 matches.

        /// A kind written by a build that knew about a check this one doesn't. Never produced by
        /// the verifier — only by decoding.
        case unknown

        /// Tolerant decode: an unrecognised `kind` becomes `.unknown` instead of throwing.
        ///
        /// **Why.** These values ride inside the persisted queue (`ConversionJob.sourceTargetResult`),
        /// so a `RawRepresentable` decode failure here doesn't lose one check — it throws out of
        /// `decode([ConversionJob].self)`, and `QueueManager.loadQueue`'s catch
        /// (`QueueManager.swift:301`) discards the user's **entire** queue. A new check kind is
        /// coming in this GoPro pass (the telemetry parity check, G5.1), and downgrade/rollback
        /// paths are real, so the failure mode is not hypothetical. The check's `label` and
        /// `detail` are plain strings and survive intact, so an unknown kind still displays
        /// correctly — only the identity is coarsened.
        ///
        /// **Note the limit:** this protects builds from *this* one onward. A blob written by a
        /// newer build and read by shipped 1.0.4 still throws — 1.0.4 has no such fallback, and
        /// nothing here can change that retroactively.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    let kind: Kind
    let severity: CheckSeverity
    let label: String   // Short human label, e.g. "Packet count".
    let detail: String  // One-line explanation, surfaced in tooltips/chips.
}

/// The aggregate result of one verification pass over a completed join.
struct SourceTargetResult: Codable, Sendable, Equatable {
    /// How deep the pass went.
    enum Tier: String, Codable, Sendable {
        case fast       // Tier 0+1 (container-index comparison).
        case thorough   // Tier 0+1+2 (byte-exact packet hash).

        /// Tolerant decode, for the same reason as `VerificationCheck.Kind` — this value rides in
        /// the persisted queue, so an unrecognised tier must degrade, not throw. An unknown tier
        /// reads as `.fast`: the weaker claim, so a rollback can never over-state what was checked.
        init(from decoder: Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Tier(rawValue: raw) ?? .fast
        }
    }

    let tier: Tier
    let checks: [VerificationCheck]
    let verifiedAt: Date
    let duration: TimeInterval   // Wall-clock seconds the pass took.

    /// Worst-wins severity across all checks (`.pass` when there are no checks).
    var overall: CheckSeverity {
        checks.map(\.severity).max() ?? .pass
    }

    /// Whether the join is considered good (nothing worse than an informational note).
    var passed: Bool { overall <= .info }

    /// Whether the seal should be orange — passed-but-flagged.
    var hasWarning: Bool { overall == .warning }

    /// Detail of the first failing check, if any.
    var firstFailureReason: String? {
        checks.first { $0.severity == .fail }?.detail
    }

    /// A short human-readable one-liner for the seal tooltip / log.
    var summary: String {
        if let reason = firstFailureReason {
            return reason
        }
        let warnings = checks.filter { $0.severity == .warning }
        if !warnings.isEmpty {
            if warnings.count == 1, let only = warnings.first {
                return only.detail
            }
            return "\(warnings.count) warnings"
        }
        return "All checks passed"
    }
}
