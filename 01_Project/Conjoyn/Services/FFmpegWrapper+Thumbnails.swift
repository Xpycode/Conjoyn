import Foundation
import AppKit

// MARK: - Frame Extraction for Thumbnails (Wave 1, task 1.10)

/// Ported from P2toMXF (`Services/FFmpegWrapper+Thumbnails.swift`). Format-agnostic — it extracts a
/// single frame from any video file FFmpeg can open, so it ports essentially byte-for-byte. For DJI
/// the source is always the self-contained MP4/MOV segment (no PROXY/ICON variants to fall back to).
extension FFmpegWrapper {

    /// Extracts a single frame from a video file at the specified timestamp.
    /// - Parameters:
    ///   - videoURL: Path to the video file (MP4, MOV, …).
    ///   - timestamp: Time in seconds to extract the frame.
    ///   - maxWidth: Maximum width for the output image (aspect ratio preserved).
    /// - Returns: `NSImage` if successful, `nil` otherwise.
    func extractFrame(from videoURL: URL, atSeconds timestamp: Double, maxWidth: Int = 320) async -> NSImage? {
        guard let ffmpeg = ffmpegPath else { return nil }

        // Check for cancellation before starting (fast path)
        guard !Task.isCancelled else { return nil }

        // Use -ss before -i for fast seeking.
        // Output JPEG to stdout via pipe.
        let args = [
            "-ss", String(format: "%.3f", timestamp),
            "-i", videoURL.path,
            "-frames:v", "1",
            "-vf", "scale=\(maxWidth):-1",  // Scale to maxWidth, maintain aspect ratio
            "-q:v", "2",                      // Good quality JPEG
            "-f", "image2pipe",
            "-vcodec", "mjpeg",
            "-"                               // Output to stdout
        ]

        // Thread-safe wrapper to ensure the continuation is resumed exactly once.
        final class ContinuationGuard: @unchecked Sendable {
            private let lock = NSLock()
            private var continuation: CheckedContinuation<NSImage?, Never>?

            init(_ continuation: CheckedContinuation<NSImage?, Never>) {
                self.continuation = continuation
            }

            func resume(returning value: NSImage?) {
                lock.lock()
                defer { lock.unlock() }
                continuation?.resume(returning: value)
                continuation = nil
            }
        }

        return await withCheckedContinuation { continuation in
            let guard_ = ContinuationGuard(continuation)
            let process = Process()
            process.executableURL = ffmpeg
            process.arguments = args

            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.standardOutput = outputPipe
            process.standardError = errorPipe

            process.terminationHandler = { _ in
                let imageData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                if !imageData.isEmpty, let image = NSImage(data: imageData) {
                    guard_.resume(returning: image)
                } else {
                    guard_.resume(returning: nil)
                }
            }

            do {
                try process.run()

                // Monitor for task cancellation while FFmpeg runs.
                // Terminates orphaned FFmpeg processes when thumbnails scroll off-screen.
                Task.detached { [weak process] in
                    while let p = process, p.isRunning {
                        if Task.isCancelled {
                            p.terminate()
                            guard_.resume(returning: nil)
                            return
                        }
                        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms check interval
                    }
                }
            } catch {
                guard_.resume(returning: nil)
            }
        }
    }
}
