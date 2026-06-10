import Foundation
import AVFoundation
import CoreMedia

// MARK: - Source Timecode Reader (rename-and-tc-disclosure, Part 2)

/// Reads the embedded `tmcd` (TimeCode32) sample from a QuickTime/MP4 file. Ported 1:1 from
/// Penumbra's `SourceTimecodeReader` (the X-H2S metadata path); the algorithm is camera-agnostic.
///
/// Pattern: TN2310 — *AVFoundation: Timecode Support with AVAssetWriter and AVAssetReader*. The
/// reader pulls the first sample buffer from the asset's timecode track, interprets its 4-byte
/// payload as a big-endian Int32 frame counter, and converts it to `CVSMPTETime` using the format
/// description's frameQuanta + drop-frame flag.
///
/// **Conjoyn use is display-only.** Most DJI MP4s carry *no* timecode track at all (the joiner
/// *creates* a fresh `tmcd` from the resolved recording-start wall-clock), so `read` typically
/// throws `.noTimecodeTrack` — which the queue-row disclosure renders as "—". When a source clip
/// *does* carry a `tmcd` it is almost always `00:00:00:00`. Either way the value is shown beside the
/// *applied* timecode purely to make the "the camera gave us nothing usable" story visible; it is
/// **never** compared against, or stamped onto, the output. (Engine basis: `docs/decisions.md`,
/// 2026-06-09 "date+timecode stamp model".)
actor SourceTimecodeReader {

    struct Result: Equatable, @unchecked Sendable {
        // `@unchecked Sendable`: every stored field is a trivial, immutable value type (an `Int32`,
        // a `Bool`, and a `CVSMPTETime` C struct of integer fields). `CVSMPTETime` isn't declared
        // `Sendable`, so the conformance can't be checked automatically, but the value is safe to
        // hand across the actor boundary. Mirrors the `@unchecked Sendable` use in `FFmpegWrapper`.

        /// Decoded start timecode (hours/minutes/seconds/frames).
        let startTimecode: CVSMPTETime
        /// Frames per second declared by the timecode-track format description.
        let frameQuanta: Int32
        /// True if the track sets `kCMTimeCodeFlag_DropFrame`.
        let isDropFrame: Bool

        /// FCP-style "HH:MM:SS:FF" (drop-frame uses ';' before frames).
        var formatted: String {
            let separator = isDropFrame ? ";" : ":"
            return String(
                format: "%02d:%02d:%02d\(separator)%02d",
                Int(startTimecode.hours),
                Int(startTimecode.minutes),
                Int(startTimecode.seconds),
                Int(startTimecode.frames)
            )
        }

        // CVSMPTETime is a C struct without Equatable; compare its fields.
        static func == (lhs: Result, rhs: Result) -> Bool {
            lhs.frameQuanta == rhs.frameQuanta
                && lhs.isDropFrame == rhs.isDropFrame
                && lhs.startTimecode.hours   == rhs.startTimecode.hours
                && lhs.startTimecode.minutes == rhs.startTimecode.minutes
                && lhs.startTimecode.seconds == rhs.startTimecode.seconds
                && lhs.startTimecode.frames  == rhs.startTimecode.frames
                && lhs.startTimecode.counter == rhs.startTimecode.counter
        }
    }

    enum ReaderError: LocalizedError, Equatable {
        case noTimecodeTrack
        case readerInitFailed(String)
        case startReadingFailed(String)
        case noSampleBuffer
        case missingFormatDescription
        case unsupportedFormatType(FourCharCode)
        case emptyBlockBuffer

        var errorDescription: String? {
            switch self {
            case .noTimecodeTrack:
                return "Asset has no tmcd timecode track."
            case .readerInitFailed(let msg):
                return "AVAssetReader init failed: \(msg)"
            case .startReadingFailed(let msg):
                return "AVAssetReader startReading failed: \(msg)"
            case .noSampleBuffer:
                return "Timecode track produced no sample buffer."
            case .missingFormatDescription:
                return "Sample buffer lacks a format description."
            case .unsupportedFormatType(let code):
                let chars = String(
                    format: "%c%c%c%c",
                    (Int(code) >> 24) & 0xff,
                    (Int(code) >> 16) & 0xff,
                    (Int(code) >>  8) & 0xff,
                    Int(code) & 0xff
                )
                return "Unsupported timecode format type '\(chars)'. Expected 'tmcd'."
            case .emptyBlockBuffer:
                return "Timecode sample block buffer is empty."
            }
        }
    }

    func read(from url: URL) async throws -> Result {
        let asset = AVURLAsset(url: url)

        let timecodeTracks = try await asset.loadTracks(withMediaType: .timecode)
        guard let track = timecodeTracks.first else {
            throw ReaderError.noTimecodeTrack
        }

        let reader: AVAssetReader
        do {
            reader = try AVAssetReader(asset: asset)
        } catch {
            throw ReaderError.readerInitFailed(error.localizedDescription)
        }

        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        guard reader.canAdd(output) else {
            throw ReaderError.readerInitFailed("canAdd(output) returned false")
        }
        reader.add(output)

        guard reader.startReading() else {
            throw ReaderError.startReadingFailed(
                reader.error?.localizedDescription ?? "unknown"
            )
        }
        defer { reader.cancelReading() }

        guard let sampleBuffer = output.copyNextSampleBuffer() else {
            throw ReaderError.noSampleBuffer
        }

        guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer) else {
            throw ReaderError.missingFormatDescription
        }

        let formatType = CMFormatDescriptionGetMediaSubType(formatDescription)
        guard formatType == kCMTimeCodeFormatType_TimeCode32 else {
            throw ReaderError.unsupportedFormatType(formatType)
        }

        guard let blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer) else {
            throw ReaderError.emptyBlockBuffer
        }

        var lengthAtOffset = 0
        var totalLength = 0
        var rawPointer: UnsafeMutablePointer<Int8>?
        let status = CMBlockBufferGetDataPointer(
            blockBuffer,
            atOffset: 0,
            lengthAtOffsetOut: &lengthAtOffset,
            totalLengthOut: &totalLength,
            dataPointerOut: &rawPointer
        )
        guard status == kCMBlockBufferNoErr,
              let pointer = rawPointer,
              lengthAtOffset >= MemoryLayout<Int32>.size else {
            throw ReaderError.emptyBlockBuffer
        }

        var bigEndianFrame: Int32 = 0
        memcpy(&bigEndianFrame, pointer, MemoryLayout<Int32>.size)
        let frameNumber = Int32(bigEndian: bigEndianFrame)

        let frameQuanta = CMTimeCodeFormatDescriptionGetFrameQuanta(formatDescription)
        let flags = CMTimeCodeFormatDescriptionGetTimeCodeFlags(formatDescription)
        let isDropFrame = (flags & UInt32(kCMTimeCodeFlag_DropFrame)) != 0

        let timecode = Self.timecode(
            forFrameNumber: frameNumber,
            frameQuanta: Int32(frameQuanta),
            isDropFrame: isDropFrame
        )

        return Result(
            startTimecode: timecode,
            frameQuanta: Int32(frameQuanta),
            isDropFrame: isDropFrame
        )
    }

    /// TN2310 Listing 8 — modular conversion of a frame counter to CVSMPTETime.
    /// Drop-frame correction: at 29.97 fps two frames are dropped each minute
    /// except every tenth minute; the integer math here mirrors the listing.
    static func timecode(
        forFrameNumber frameNumber: Int32,
        frameQuanta: Int32,
        isDropFrame: Bool
    ) -> CVSMPTETime {
        var frame = frameNumber

        if isDropFrame {
            let framesPer10Minutes = frameQuanta * 60 * 10 - 9 * 2
            let d = frame / framesPer10Minutes
            let m = frame % framesPer10Minutes

            let framesPerMinute = frameQuanta * 60 - 2
            if m > 1 {
                frame = frame
                    + (9 * 2 * d)
                    + 2 * ((m - 2) / framesPerMinute)
            } else {
                frame = frame + 9 * 2 * d
            }
        }

        let fps = max(frameQuanta, 1)
        var tc = CVSMPTETime()
        tc.frames  = Int16(frame % fps)
        let totalSeconds = frame / fps
        tc.seconds = Int16(totalSeconds % 60)
        let totalMinutes = totalSeconds / 60
        tc.minutes = Int16(totalMinutes % 60)
        tc.hours   = Int16(totalMinutes / 60)
        tc.subframes = 0
        tc.subframeDivisor = 0
        tc.counter = UInt32(bitPattern: frame)
        // CVSMPTETime.type and .flags use the Core Video flag set, not the Core
        // Media one — leaving them zero. Consumers should rely on the sibling
        // `isDropFrame` field on Result instead.
        return tc
    }
}
