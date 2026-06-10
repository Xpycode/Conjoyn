import Foundation

/// Helper struct for timecode arithmetic.
///
/// Ported byte-for-byte from P2toMXF (`Models/P2Clip.swift`). Keeps the rounded-fps
/// `totalFrames` behaviour so NTSC rates (29.97 → 30, 23.976 → 24) bucket correctly,
/// and the `frameGap` continuity check used to detect seams between segments.
struct Timecode: Equatable {
    let hours: Int
    let minutes: Int
    let seconds: Int
    let frames: Int
    let frameRate: Double

    /// Parse timecode string in format "HH:MM:SS:FF"
    init?(string: String, frameRate: Double) {
        let components = string.split(separator: ":").compactMap { Int($0) }
        guard components.count == 4 else { return nil }

        self.hours = components[0]
        self.minutes = components[1]
        self.seconds = components[2]
        self.frames = components[3]
        self.frameRate = frameRate
    }

    init(hours: Int, minutes: Int, seconds: Int, frames: Int, frameRate: Double) {
        self.hours = hours
        self.minutes = minutes
        self.seconds = seconds
        self.frames = frames
        self.frameRate = frameRate
    }

    /// Convert to absolute frame number for arithmetic operations
    /// Note: Uses rounded frame rate to handle NTSC (29.97 → 30, 23.976 → 24)
    var totalFrames: Int {
        let fps = Int(frameRate.rounded())
        return hours * 3600 * fps + minutes * 60 * fps + seconds * fps + frames
    }

    /// Create timecode from total frames
    /// Note: Uses rounded frame rate to handle NTSC (29.97 → 30, 23.976 → 24)
    static func from(frames: Int, frameRate: Double) -> Timecode {
        let fps = Int(frameRate.rounded())
        guard fps > 0 else {
            return Timecode(hours: 0, minutes: 0, seconds: 0, frames: 0, frameRate: frameRate)
        }
        var remaining = frames

        let h = remaining / (3600 * fps)
        remaining %= (3600 * fps)

        let m = remaining / (60 * fps)
        remaining %= (60 * fps)

        let s = remaining / fps
        let f = remaining % fps

        return Timecode(hours: h, minutes: m, seconds: s, frames: f, frameRate: frameRate)
    }

    /// Calculates the frame gap between end of clip1 and start of clip2
    /// Returns: 0 = continuous, positive = gap, negative = overlap
    static func frameGap(from tc1: Timecode, duration1Frames: Int, to tc2: Timecode) -> Int {
        let expectedNextFrame = tc1.totalFrames + duration1Frames
        let actualNextFrame = tc2.totalFrames
        return actualNextFrame - expectedNextFrame
    }

    /// Formatted timecode string (HH:MM:SS:FF) for display
    var description: String {
        String(format: "%02d:%02d:%02d:%02d", hours, minutes, seconds, frames)
    }
}
