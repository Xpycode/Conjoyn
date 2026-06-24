import Foundation

// MARK: - File Identity (cookbook #127 — TOCTOU identity verify before a destructive op)

/// A durable filesystem identity for a file — `(device, inode)` — captured at one moment so it can
/// be re-checked at another. A path string is *not* an identity: between the time a clip is queued
/// and the time FFmpeg joins it (often minutes later, as the queue drains), the same path can come
/// to point at a **different file** — the card is swapped, or the camera rotates a new recording
/// into the same `DCIM/100MEDIA/DJI_0001.MP4` slot. Joining the stale path then silently concatenates
/// the *wrong bytes*; ffmpeg has no way to notice. Capturing `(device, inode)` at enqueue and
/// re-verifying it immediately before the join closes that time-of-check-to-time-of-use gap.
///
/// See `cookbook/127-toctou-identity-verify-before-destructive-op.md`.
struct FileIdentity: Equatable, Sendable, Codable {
    let device: UInt64
    let inode: UInt64

    /// Captures the identity of the file at `url`, or `nil` if it can't be `stat`'d.
    ///
    /// Uses `lstat` per the cookbook discipline — identify the link itself, don't chase it. DJI
    /// segments are regular files (not symlinks), so `lstat` and `stat` agree here; `lstat` is the
    /// safer default for the general pattern.
    static func capture(_ url: URL) -> FileIdentity? {
        var st = stat()
        let ok = url.withUnsafeFileSystemRepresentation { path -> Bool in
            guard let path else { return false }
            return lstat(path, &st) == 0
        }
        guard ok else { return nil }
        return FileIdentity(device: UInt64(st.st_dev), inode: UInt64(st.st_ino))
    }

    /// The outcome of re-checking a file's current identity against one captured earlier. Kept as
    /// distinct cases (not a bool) so each maps to its own caller action — same discipline as
    /// cookbook #61 (classify, don't collapse).
    enum Check: Equatable, Sendable {
        /// The path still resolves to the same file we captured — safe to act.
        case matches
        /// The path now resolves to a *different* file — a swap/rotation happened. Refuse.
        case mismatch
        /// The file is gone since capture (`ENOENT`) — nothing to act on.
        case missingNow
        /// Couldn't determine identity (a transient `stat` error that isn't "gone"). Carries the
        /// reason; the caller decides whether that's fatal for its operation.
        case unverifiable(String)
    }

    /// Re-checks `url`'s current identity against `scanned` (the identity captured earlier).
    static func verify(url: URL, against scanned: FileIdentity) -> Check {
        var st = stat()
        let rc = url.withUnsafeFileSystemRepresentation { path -> Int32 in
            guard let path else { return -1 }
            return lstat(path, &st)
        }
        if rc != 0 {
            return (errno == ENOENT || errno == ENOTDIR)
                ? .missingNow
                : .unverifiable(String(cString: strerror(errno)))
        }
        let current = FileIdentity(device: UInt64(st.st_dev), inode: UInt64(st.st_ino))
        return current == scanned ? .matches : .mismatch
    }
}
