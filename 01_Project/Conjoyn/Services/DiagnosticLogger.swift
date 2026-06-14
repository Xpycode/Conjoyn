import Foundation

// MARK: - Diagnostic Logger

/// Persistent, file-backed diagnostic log at `~/Library/Application Support/Conjoyn/diagnostic.log`.
///
/// Conjoyn already keeps an in-app console (`QueueManager.consoleLines`), but that buffer is
/// **ephemeral** — it dies with the app. When a user reports a bug after quitting and relaunching,
/// there is nothing on disk to ask them for. This logger mirrors the same lifecycle messages to a
/// file that survives quit / crash / relaunch, so a support request can include a retrievable
/// artifact. It does **not** replace the console; `QueueManager.log()` writes to both.
///
/// Conventions match the family services (`SpeedTracker` / `QueueManager`):
///   - `@MainActor` + a `shared` singleton (every caller is already on the main actor).
///   - An **injectable** storage directory so tests write to a temp dir instead of the real
///     app-support file.
///   - Append-based, *not* rewrite-on-boundary like the JSON stores — a log only ever grows during
///     a session, so we seek-to-end and append one line at a time. The messages are coarse,
///     event-level (job start / SUCCESS / FAILED / resolution milestones, ~a handful per job), so
///     synchronous main-thread writes cost nothing. The high-frequency `speed=` / progress stream
///     deliberately flows through `activeMetrics`, not `log()`, so it never reaches this file.
@MainActor
final class DiagnosticLogger {
    // MARK: - Shared Instance
    static let shared = DiagnosticLogger()

    // MARK: - Constants
    private static let logFileName = "diagnostic.log"

    /// Soft ceiling for the on-disk log before `rotateIfNeeded()` should act. ~1 MB of ISO-stamped
    /// event lines is tens of thousands of entries — plenty of history without unbounded growth.
    static let maxBytes = 1_000_000

    // MARK: - Persistence

    /// Where the log is written. `nil` only if the app-support directory couldn't be located, in
    /// which case logging silently no-ops — a diagnostics facility must never block or crash the app
    /// it exists to diagnose.
    let logFileURL: URL?

    /// ISO-8601 with fractional seconds — sortable, unambiguous across time zones, and ideal for a
    /// log a user might email back days later (the console uses a friendly `.medium` time instead).
    private let timestampFormatter: ISO8601DateFormatter

    // MARK: - Init

    /// - Parameter storageDirectory: Directory to write `diagnostic.log` in. `nil` (the default,
    ///   used by `shared`) resolves to `~/Library/Application Support/Conjoyn`. Tests pass a temp dir
    ///   so they never touch the real log file.
    init(storageDirectory: URL? = nil) {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter

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
            self.logFileURL = dir.appendingPathComponent(Self.logFileName)
        } else {
            self.logFileURL = nil
        }

        // A session marker keeps multi-launch logs readable: a reader can see where each run of the
        // app begins, and the version stamp ties the lines that follow to a specific build.
        appendLine("──────── session started · Conjoyn \(Self.appVersionString) ────────")
    }

    // MARK: - Public API

    /// Appends one timestamped line to the log file. Safe to call from anywhere on the main actor;
    /// all failures are swallowed by design (diagnostics must never crash the app they diagnose).
    func log(_ message: String) {
        appendLine(message)
    }

    /// Returns the last `maxLines` lines of the current `diagnostic.log`, or `nil` if the file is
    /// missing/empty. This is the read counterpart to `log()` — it feeds the feedback sheet's
    /// "Attach recent log" toggle so a bug report can carry recent context.
    ///
    /// Reads **only the current generation**, not the rotated `diagnostic.log.1`: the freshest
    /// lines are what a just-filed report needs, and bounding to one file keeps the read a single
    /// cheap slurp. Like everything in this type it **never throws** — any failure yields `nil`
    /// rather than disturbing the app it diagnoses. The returned text is sent verbatim, so callers
    /// that forward it externally own any redaction; Conjoyn's lines are coarse event milestones
    /// (job start / SUCCESS / FAILED / file names) with no secrets.
    func recentTail(maxLines: Int = 80) -> String? {
        guard maxLines > 0,
              let url = logFileURL,
              let contents = try? String(contentsOf: url, encoding: .utf8)
        else { return nil }

        let lines = contents.split(separator: "\n", omittingEmptySubsequences: true)
        guard !lines.isEmpty else { return nil }

        return lines.suffix(maxLines).joined(separator: "\n")
    }

    // MARK: - File Writing

    private func appendLine(_ message: String) {
        guard let url = logFileURL else { return }

        rotateIfNeeded()

        let stamped = "[\(timestampFormatter.string(from: Date()))] \(message)\n"
        guard let data = stamped.data(using: .utf8) else { return }

        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            // First write of the session — the file doesn't exist yet, so create it with this line.
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Rotation

    /// Single-generation rotation: when `diagnostic.log` reaches `maxBytes`, move it aside to
    /// `diagnostic.log.1` (replacing any prior `.1`) so the next append starts a fresh file. This
    /// keeps ~2 files of recent history that survive a relaunch — the case that matters when a user
    /// reports a bug *after* quitting — while bounding disk to ~2 × `maxBytes`.
    ///
    /// Called from `appendLine` before every write, so it stays cheap (one `attributesOfItem` stat
    /// per line) and, like everything in this type, **never throws**: a rotation failure leaves the
    /// oversized file in place and logging simply continues, rather than taking the app down.
    private func rotateIfNeeded() {
        guard let url = logFileURL,
              let size = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int,
              size >= Self.maxBytes else { return }

        let rotated = url.deletingLastPathComponent()
            .appendingPathComponent(Self.logFileName + ".1")
        try? FileManager.default.removeItem(at: rotated)   // clear the previous generation, if any
        try? FileManager.default.moveItem(at: url, to: rotated)
        // `appendLine` re-creates a fresh `diagnostic.log` on its next write (file no longer exists).
    }

    // MARK: - Version

    /// `"1.0 (100)"` — marketing version + build, read from the bundle so the log self-identifies
    /// which build produced it (the single most useful fact in a user-supplied log).
    private static var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}
