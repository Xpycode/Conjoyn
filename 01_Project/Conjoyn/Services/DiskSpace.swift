import Foundation

// MARK: - Volume Capacity Helper (Wave 1, task 1.5)

/// Pure helper for querying volume capacity and identity.
/// Used by `TempDirectoryManager`, the pre-join disk-space preflight, and error-message enrichment.
///
/// Ported from P2toMXF unchanged — it was already format-agnostic (no P2/MXF assumptions).
enum DiskSpace {

    /// Returns available capacity in bytes for important (user-initiated) writes at the given URL's volume.
    /// Falls back to the legacy `volumeAvailableCapacityKey` if the "important usage" key is unavailable
    /// **or reports a non-positive value**. Returns `nil` if the URL's volume can't be queried (e.g. the
    /// path no longer exists).
    ///
    /// The fallback-on-zero is load-bearing: `volumeAvailableCapacityForImportantUsageKey` is a boot-volume
    /// convenience that returns **0 (not nil)** on external / secondary APFS volumes (SD cards, external
    /// SSDs). Trusting that 0 made the disk-space preflight reject every join to an external destination —
    /// the normal case — even with hundreds of GB free. See `usableCapacity(importantUsage:legacy:)`.
    static func availableCapacity(for url: URL) -> Int64? {
        let keys: [URLResourceKey] = [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]
        guard let values = try? url.resourceValues(forKeys: Set(keys)) else {
            return nil
        }
        return usableCapacity(
            importantUsage: values.volumeAvailableCapacityForImportantUsage,
            legacy: values.volumeAvailableCapacity.map(Int64.init)
        )
    }

    /// Pure selection between the two capacity signals (extracted for testing).
    /// Prefers the "important usage" figure (the most accurate "what you can actually write" value on the
    /// boot volume, since it counts purgeable space), but treats a **non-positive** value as a miss and
    /// falls back to the legacy raw capacity — because external/secondary volumes report it as 0.
    static func usableCapacity(importantUsage: Int64?, legacy: Int64?) -> Int64? {
        if let important = importantUsage, important > 0 {
            return important
        }
        return legacy
    }

    /// Returns the user-facing name of the volume containing the given URL (e.g. "Macintosh HD", "1TB extra").
    /// Returns `nil` if the URL's volume can't be queried.
    static func volumeName(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeNameKey]) else {
            return nil
        }
        return values.volumeName
    }

    /// Returns true if both URLs reside on the same volume.
    /// If either lookup fails, returns false (conservative — treats unknown as different volumes).
    static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        guard
            let aValues = try? a.resourceValues(forKeys: [.volumeURLKey]),
            let bValues = try? b.resourceValues(forKeys: [.volumeURLKey]),
            let aVolume = aValues.volume,
            let bVolume = bValues.volume
        else {
            return false
        }
        return aVolume == bVolume
    }

    /// Formats a byte count as a short, human-readable string using GB/MB as appropriate.
    /// Uses the file-size byte counter style (GB not GiB) to match macOS Finder display.
    static func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}
