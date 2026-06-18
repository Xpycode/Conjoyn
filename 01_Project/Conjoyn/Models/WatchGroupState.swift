import Foundation

// MARK: - Watch Group State (Wave 5A, task 5.3)

/// State machine for a single watch-folder group as it moves from initial file discovery
/// through stability settling, grouping, readiness, the join operation, metadata
/// verification, and finally a terminal outcome. Persisted as a raw `String` so the
/// watch-folder coordinator can survive app relaunch without losing per-group progress.
///
/// Only the transitions listed in `canTransition(to:)` are legal; everything else is
/// refused to prevent the coordinator from silently skipping required stages or
/// re-activating completed work.
enum WatchGroupState: String, Codable, Sendable, CaseIterable {

    /// FSEvents / DispatchSource saw new files; no settling timer started yet.
    case discovered

    /// Quiet-window timer is running; waiting for the filesystem to stop changing.
    /// Self-loop is intentional: additional files reset the timer, producing repeated
    /// `settling → settling` transitions until the window finally expires.
    case settling

    /// Files are stable; metadata continuity analysis has grouped them into a candidate set.
    case grouped

    /// `CompleteSetGate` confirmed the set is complete; the join may begin.
    case ready

    /// FFmpeg concat demuxer is running.
    case joining

    /// Join finished; checking output timecode, duration, and creation-date metadata.
    case verifyingMetadata

    /// All verification steps passed; the joined file is accepted.
    case done

    /// Any stage encountered an unrecoverable error; no further transitions allowed.
    case failed

    // MARK: - Transition table

    /// Returns `true` when moving from `self` to `next` is a legal transition.
    ///
    /// The table encodes the full happy path plus re-settle and failure escape hatches.
    /// `done` and `failed` are terminal: no outgoing edges exist.
    func canTransition(to next: WatchGroupState) -> Bool {
        switch self {
        case .discovered:
            return next == .settling || next == .failed
        case .settling:
            // Self-loop allowed: new segment resets the quiet-window timer.
            return next == .grouped || next == .settling || next == .failed
        case .grouped:
            // Re-settle when a new segment arrives after grouping.
            return next == .ready || next == .settling || next == .failed
        case .ready:
            return next == .joining || next == .failed
        case .joining:
            return next == .verifyingMetadata || next == .failed
        case .verifyingMetadata:
            return next == .done || next == .failed
        case .done, .failed:
            // Terminal states: no outgoing transitions.
            return false
        }
    }

    /// Performs the transition to `next` if it is legal; returns `next` on success, `nil` otherwise.
    ///
    /// Pure and value-typed: callers replace the stored state with the returned value.
    func transition(to next: WatchGroupState) -> WatchGroupState? {
        canTransition(to: next) ? next : nil
    }

    // MARK: - Convenience

    /// `true` for terminal states that accept no further transitions.
    var isTerminal: Bool { self == .done || self == .failed }
}
