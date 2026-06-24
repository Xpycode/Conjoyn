import Foundation
import AVFoundation
import CoreMedia

// MARK: - DJI Folder Reader (Wave 2, tasks 2.2/2.3/2.4 — first cut)

/// Scans a folder for DJI media segments, builds `[DJIClip]`, and groups them into `RecordGroup`s
/// ready to become queue jobs.
///
/// This is the **first-cut** folder→jobs path that lets the app join a typical single-recording
/// folder today. It uses a deliberately **simple grouping rule** — one group per camera/lens
/// **variant suffix**, segments ordered by capture index — instead of the full metadata-continuity
/// grouping (the real task 2.4), which needs real DJI footage to design and validate. The
/// camera-variant **no-merge boundary** from the spec *is* honoured here (clips with different
/// `_W`/`_T`/… suffixes never share a group); what's deferred is splitting one suffix into separate
/// recordings by `creation_time` gaps. When the footage-gated grouping engine lands, only `group(_:)`
/// changes — the discovery/probe pipeline stays.
///
/// Metadata is read AVFoundation-first per the project's read strategy: `AVURLAsset` for the exact
/// `CMTime` duration and embedded `creation_time`, plus a best-effort ffprobe pass for the
/// copy-relevant stream parameters (codec/res/fps/…). A failed stream probe is non-fatal — the
/// clip still joins and the pre-join parameter guard (task 2.6) runs at join time regardless.
enum DJIFolderReader {

    /// The outcome of scanning one folder.
    struct Discovery: Sendable {
        /// Groups ready to enqueue, one per camera variant, segments in capture order.
        var groups: [RecordGroup]
        /// Media files that parsed as DJI but could not be probed (e.g. unreadable duration).
        var errors: [ClipParseError]
        /// Plausible-media filenames (`.mp4`/`.mov`/`.srt`/`.lrf`) that didn't match a DJI scheme.
        var skippedNonDJI: [String]

        /// Total segments across all groups.
        var clipCount: Int { groups.reduce(0) { $0 + $1.clipCount } }
    }

    /// Reads `folder` and returns grouped, ordered clips.
    ///
    /// The chosen folder is scanned non-recursively first. If it holds no DJI media — common when
    /// the user drops a card *root* (`/Volumes/CARD`) whose clips actually live in `DCIM/DJI_001` —
    /// discovery falls back to a **shallow, card-shaped descent** (`resolveMediaFolders`): it looks
    /// through a `DCIM` container for the media subfolders and pools their contents. It is bounded
    /// to the depths real camera cards use (root → `DCIM` → media folder), never a deep recursive
    /// walk of an arbitrary directory.
    /// - Parameters:
    ///   - folder: The dropped/chosen folder — a media folder (`…/DCIM/100MEDIA`), a `DCIM`, or a
    ///     card root.
    ///   - ffmpeg: Wrapper used for the ffprobe stream-parameter pass.
    static func read(folder: URL, using ffmpeg: FFmpegWrapper) async -> Discovery {
        let fm = FileManager.default
        // Pool contents across every media folder the descent resolves (usually just `folder`).
        let contents = resolveMediaFolders(startingAt: folder).flatMap { dir in
            (try? fm.contentsOfDirectory(
                at: dir,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []
        }

        // Pair sidecars to videos by shared stem (a video and its `.SRT`/`.LRF` share the stem).
        var srtByStem: [String: URL] = [:]
        var lrfByStem: [String: URL] = [:]
        var videoFiles: [(url: URL, parsed: DJIFilenameParser.Parsed)] = []
        var skipped: [String] = []

        for url in contents {
            guard let parsed = DJIFilenameParser.parse(url) else {
                // Only surface files that look like media; ignore .DS_Store, .THM, etc.
                let ext = url.pathExtension.lowercased()
                if ["mp4", "mov", "srt", "lrf"].contains(ext) {
                    skipped.append(url.lastPathComponent)
                }
                continue
            }
            let key = parsed.stem.lowercased()
            switch parsed.mediaKind {
            case .video:     videoFiles.append((url, parsed))
            case .telemetry: srtByStem[key] = url
            case .proxy:     lrfByStem[key] = url
            case .other:     break
            }
        }

        var clips: [DJIClip] = []
        var errors: [ClipParseError] = []

        for (url, parsed) in videoFiles {
            let key = parsed.stem.lowercased()
            let asset = AVURLAsset(url: url)

            // Duration is mandatory — without it the clip can't be ordered, estimated, or joined.
            let duration: CMTime
            do {
                duration = try await asset.load(.duration)
            } catch {
                errors.append(ClipParseError(file: url, error: error))
                continue
            }
            guard duration.isNumeric, CMTimeGetSeconds(duration) > 0 else {
                errors.append(ClipParseError(file: url, message: "Could not read a valid duration"))
                continue
            }

            // Embedded creation_time — best effort (a continuity signal, not required for the join).
            var creationDate: Date?
            if let item = try? await asset.load(.creationDate) {
                creationDate = try? await item.load(.dateValue)
            }

            // Copy-relevant stream parameters — best effort; the param guard re-probes at join time.
            let streamInfo = try? await probeStream(url, using: ffmpeg)

            clips.append(DJIClip.from(
                parsed: parsed,
                videoURL: url,
                srtURL: srtByStem[key],
                lrfURL: lrfByStem[key],
                duration: duration,
                creationDate: creationDate,
                cameraModel: nil,
                streamInfo: streamInfo
            ))
        }

        return Discovery(groups: group(clips), errors: errors, skippedNonDJI: skipped)
    }

    // MARK: - Grouping (metadata-continuity, task 2.4)

    /// A file-free view of a segment for the pure grouping core, so the algorithm is unit-testable
    /// against real-footage metadata without 4 GB files on disk.
    struct SegmentMeta: Sendable {
        let id: UUID
        let variantSuffix: String?
        /// Embedded `creation_time` — real wall-clock recording start (authoritative continuity key).
        let creationDate: Date?
        /// Container **playback** duration in seconds. NOTE: for slow-motion this is several × the
        /// real elapsed time, so it is used only as a coarse upper bound on the continuation gap —
        /// never to compute when a segment "ends" in wall-clock terms.
        let containerSeconds: Double
        let sizeBytes: Int64
        let streamInfo: StreamParameterGuard.SegmentStreamInfo?
        let index: Int
        let stem: String
    }

    /// Tunables for continuity grouping. Defaults validated against real DJI footage (2026-06).
    struct GroupingTolerances: Sendable {
        /// A segment is treated as having hit the recording's **split cap** (⇒ it continues into the
        /// next file) when its size is at least this fraction of the largest segment in the set.
        /// DJI cuts a segment at a fixed byte ceiling, so capped segments cluster just under the
        /// largest file while a recording's final/only segment sits well below.
        var capSizeFraction: Double = 0.93
        /// Floor for the cap threshold, so a folder of only short clips (largest file small) doesn't
        /// flag everything as capped. No real DJI split segment is smaller than this.
        var capSizeFloorBytes: Int64 = 3_000_000_000
        /// How far past a capped segment's own **playback** length the next segment may start before
        /// it's treated as a *new* recording. Small because true splits are written back-to-back;
        /// the few seconds absorb 1-second `creation_time` rounding.
        var continuationSlackSeconds: Double = 12
        var minClips: Int = 1
    }

    /// Pure continuity-grouping core. Buckets by camera/lens variant (the hard no-merge boundary),
    /// then within each bucket walks segments in real-time order and chains a capped segment to the
    /// next when their start times are contiguous and stream parameters match. File-free and
    /// deterministic — see `group(_:)` for the `DJIClip` adapter.
    ///
    /// The keystone insight (from real footage): we chain on the **file-size split cap + real
    /// wall-clock start**, never on playback duration (which lies for slow-mo) or filename index
    /// (which resets and collides across a card). A segment at the cap continues; the first segment
    /// under the cap ends the recording.
    static func groupMetas(_ metas: [SegmentMeta], tolerances: GroupingTolerances = .init()) -> [[SegmentMeta]] {
        guard !metas.isEmpty else { return [] }

        let maxSize = metas.map(\.sizeBytes).max() ?? 0
        let capThreshold = max(tolerances.capSizeFloorBytes, Int64(tolerances.capSizeFraction * Double(maxSize)))

        let buckets = Dictionary(grouping: metas) { $0.variantSuffix ?? "" }
        var runs: [[SegmentMeta]] = []
        for key in buckets.keys.sorted() {
            let ordered = buckets[key]!.sorted(by: orderedBefore)
            var current: [SegmentMeta] = []
            for clip in ordered {
                if let prev = current.last, continues(prev, clip, capThreshold: capThreshold, tolerances: tolerances) {
                    current.append(clip)
                } else {
                    if !current.isEmpty { runs.append(current) }
                    current = [clip]
                }
            }
            if !current.isEmpty { runs.append(current) }
        }
        // Chronological display order across variants (first segment's start; index as fallback).
        return runs.sorted { lhs, rhs in
            orderedBefore(lhs.first!, rhs.first!)
        }
    }

    /// Real-time ordering: by `creation_time` when both known, else filename index then stem.
    private static func orderedBefore(_ lhs: SegmentMeta, _ rhs: SegmentMeta) -> Bool {
        if let l = lhs.creationDate, let r = rhs.creationDate, l != r { return l < r }
        return lhs.index != rhs.index ? lhs.index < rhs.index : lhs.stem < rhs.stem
    }

    /// Whether `next` is a continuation split of `prev` (same recording).
    private static func continues(
        _ prev: SegmentMeta,
        _ next: SegmentMeta,
        capThreshold: Int64,
        tolerances: GroupingTolerances
    ) -> Bool {
        // 1. Only a *capped* segment continues — the cap is why DJI opened the next file at all.
        guard prev.sizeBytes >= capThreshold else { return false }
        // 2. Never merge across camera/lens variants (the spec's hard boundary; also bucketed).
        guard prev.variantSuffix == next.variantSuffix else { return false }
        // 3. Adjacent segments of one recording carry consecutive indices — a jump means a segment is
        //    missing between them, so never bridge the hole. This is the *only* signal that catches a
        //    dropped middle segment in slow-motion footage, where step 5's wall-clock bound is the
        //    playback length (≈4× real elapsed) and is far too loose to notice the gap. Index is used
        //    here strictly as a *negative* signal within a same-variant, time-ordered run — not as a
        //    continuity key (numbering still isn't authoritative for ordering or identity; see spec).
        //    A non-consecutive index favours a safe split over a corrupt silent merge. Caveat: assumes
        //    per-variant consecutive numbering (verified on single-camera footage); multi-lens
        //    enterprise numbering is footage-gated (6.5) and to be re-validated when such a card exists.
        guard next.index == prev.index + 1 else { return false }
        // 4. Copy-relevant stream params must match when both are known (the join guard backstops nil).
        if let p = prev.streamInfo, let n = next.streamInfo,
           StreamParameterGuard.check([p, n]) != .compatible {
            return false
        }
        // 5. `next` must start within `prev`'s playback length (+slack) of `prev`'s start — and we
        //    need real `creation_time`s to judge it. Missing either ⇒ can't confirm ⇒ don't chain.
        guard let pc = prev.creationDate, let nc = next.creationDate else { return false }
        let gap = nc.timeIntervalSince(pc)
        return gap > 0 && gap <= prev.containerSeconds + tolerances.continuationSlackSeconds
    }

    /// Groups `clips` into continuous recordings (one `RecordGroup` per recording). Adapter over
    /// `groupMetas`: reads each clip's on-disk size for the split-cap signal, then maps runs back to
    /// `RecordGroup`s in chronological order.
    static func group(_ clips: [DJIClip]) -> [RecordGroup] {
        guard !clips.isEmpty else { return [] }

        let byId = Dictionary(uniqueKeysWithValues: clips.map { ($0.id, $0) })
        let metas = clips.map { c in
            SegmentMeta(
                id: c.id,
                variantSuffix: c.variantSuffix,
                creationDate: c.creationDate,
                containerSeconds: c.durationInSeconds,
                sizeBytes: c.totalFileSize,
                streamInfo: c.streamInfo,
                index: c.index,
                stem: c.stem
            )
        }

        return groupMetas(metas).enumerated().map { offset, run in
            let runClips = run.compactMap { byId[$0.id] }
            return RecordGroup(
                clips: runClips,
                groupIndex: offset + 1,
                groupType: runClips.count > 1 ? .split : .single,
                variantSuffix: runClips.first?.variantSuffix
            )
        }
    }

    // MARK: - Folder resolution (card-aware descent)

    /// Resolves which folder(s) to actually scan for media, starting from what the user dropped/chose.
    ///
    /// Returns `[folder]` unchanged when it directly contains DJI video (the common case: a media
    /// folder was picked). Otherwise performs a **shallow, card-shaped descent**: it treats a `DCIM`
    /// directory (under `folder`, or `folder` itself when it *is* `DCIM`) — and `folder` itself, for
    /// DCIM-less layouts — as parents whose *immediate* subfolders are media folders, and returns the
    /// subfolders that hold DJI video. Bounded to one subdirectory level (card root → `DCIM` → media
    /// folder), so dropping a huge home directory never triggers a deep walk.
    ///
    /// When nothing is found it returns `[folder]` so the caller still produces an (empty) scan with
    /// the original folder's name in the status message.
    static func resolveMediaFolders(startingAt folder: URL) -> [URL] {
        if containsDJIMedia(folder) { return [folder] }

        // Parents whose immediate children are candidate media folders.
        var parents: [URL] = []
        let dcim = folder.appendingPathComponent("DCIM", isDirectory: true)
        if isDirectory(dcim) { parents.append(dcim) }
        if folder.lastPathComponent.caseInsensitiveCompare("DCIM") == .orderedSame { parents.append(folder) }
        parents.append(folder) // DCIM-less cards: media folders sit directly under the dropped folder.

        let fm = FileManager.default
        var found: [URL] = []
        var seen = Set<String>()
        for parent in parents {
            let subdirs = (try? fm.contentsOfDirectory(
                at: parent,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )) ?? []
            for sub in subdirs where isDirectory(sub) && containsDJIMedia(sub) {
                if seen.insert(sub.standardizedFileURL.path).inserted { found.append(sub) }
            }
        }
        // Stable order so multi-folder cards enqueue predictably (DJI_001 before DJI_002).
        return found.isEmpty ? [folder] : found.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Whether a folder directly contains at least one file that parses as DJI **video** (cheap —
    /// filename enumeration only, no media decode).
    private static func containsDJIMedia(_ folder: URL) -> Bool {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return contents.contains { DJIFilenameParser.parse($0)?.mediaKind == .video }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }

    // MARK: - Helpers

    /// Runs the (blocking) ffprobe stream-parameter probe off the calling executor.
    private static func probeStream(
        _ url: URL,
        using ffmpeg: FFmpegWrapper
    ) async throws -> StreamParameterGuard.SegmentStreamInfo {
        try await Task.detached(priority: .userInitiated) {
            try ffmpeg.probeStreamInfo(url)
        }.value
    }
}
