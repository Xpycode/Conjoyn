import Foundation
import SwiftUI
import AppKit

// MARK: - Conversion View Model (UI ↔ QueueManager wiring)

/// Front-end state for choosing a source folder, scanning it into groups, tuning settings, and
/// handing jobs to the `QueueManager` engine. The queue itself (jobs, progress, console, processing
/// state) lives on `QueueManager`; this view model owns only the *pre-enqueue* state — the selected
/// folders, the discovered groups, and the in-flight `ConversionSettings`.
///
/// Security-scoped access: source/output folders come from `NSOpenPanel`, and jobs are created via
/// `QueueManager.addJob(folderName:…)` → `ConversionJob.withBookmarks`, which captures
/// security-scoped bookmarks while the panel-granted access is live. `QueueManager.processJob` later
/// resolves those bookmarks (the engine's access gate rejects non-bookmarked URLs). Sandbox is off
/// but Hardened Runtime is on, so the bookmarks are what make access survive across launches.
@MainActor
final class ConversionViewModel: ObservableObject {

    /// The shared engine. Views also observe this directly for queue/console/progress state.
    let queue: QueueManager
    private let ffmpeg: FFmpegWrapper
    /// Row-thumbnail extraction (first frame of a group's first segment), shared across rows.
    let thumbnails: ThumbnailManager

    // MARK: - Pre-enqueue state

    @Published var sourceFolderURL: URL?
    @Published var outputFolderURL: URL?
    @Published var settings = ConversionSettings()

    /// Output-renaming state. Session-only (not in `ConversionSettings`, which is `Codable` and
    /// frozen onto every job) — only the *resolved* output name needs to ride on the job, and that
    /// already does via `destinationURL`. Toggling `renameEnabled` opens/closes the rename popover;
    /// `renameOptions` is the live pattern the popover edits and the enqueue path applies.
    @Published var renameEnabled = false
    @Published var renameOptions = RenamePatternEngine.Options.default

    /// Memoised recording-start date per group (`group.id` → resolved `Date?`). Resolving reads the
    /// `.SRT` + filesystem, so the rename preview — which re-renders on every keystroke — must not
    /// re-resolve each time. Cleared on every `scan()`.
    private var resolvedStartCache: [UUID: Date?] = [:]

    @Published private(set) var groups: [RecordGroup] = []
    /// Which groups will be enqueued by `addToQueue`. Defaults after a scan to the **split**
    /// recordings only (the ones that actually need joining), so pointing at a whole SD card doesn't
    /// silently queue ~60 lone single clips. The user ticks/unticks individual rows.
    @Published private(set) var selectedGroupIDs: Set<UUID> = []
    @Published private(set) var parseErrors: [ClipParseError] = []
    @Published private(set) var skippedFiles: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusMessage: String?

    init(queue: QueueManager = .shared) {
        self.queue = queue
        self.ffmpeg = queue.ffmpeg
        self.thumbnails = ThumbnailManager(ffmpeg: queue.ffmpeg)
    }

    // MARK: - Derived

    var totalClips: Int { groups.reduce(0) { $0 + $1.clipCount } }

    /// The groups that `addToQueue` will enqueue, in display order.
    var selectedGroups: [RecordGroup] { groups.filter { selectedGroupIDs.contains($0.id) } }
    var selectedCount: Int { selectedGroupIDs.count }

    var canAddToQueue: Bool { !selectedGroups.isEmpty && outputFolderURL != nil && !isScanning }

    func isSelected(_ group: RecordGroup) -> Bool { selectedGroupIDs.contains(group.id) }

    // MARK: - Selection

    func toggleSelection(_ group: RecordGroup) {
        if selectedGroupIDs.contains(group.id) { selectedGroupIDs.remove(group.id) }
        else { selectedGroupIDs.insert(group.id) }
    }

    func selectAllGroups() { selectedGroupIDs = Set(groups.map(\.id)) }
    func selectNoGroups() { selectedGroupIDs = [] }
    func selectSplitGroupsOnly() {
        selectedGroupIDs = Set(groups.filter { $0.groupType == .split }.map(\.id))
    }

    // MARK: - Folder selection

    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a DJI media folder (e.g. DCIM/100MEDIA)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        setSourceFolder(url)
    }

    /// Sets the source folder and kicks off a scan. Also the entry point for drag-and-drop of a
    /// folder onto the empty state.
    func setSourceFolder(_ url: URL) {
        sourceFolderURL = url
        if outputFolderURL == nil { outputFolderURL = url }
        Task { await scan() }
    }

    func chooseOutputFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.message = "Choose where to save the joined file(s)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        outputFolderURL = url
    }

    // MARK: - Scan

    func scan() async {
        guard let source = sourceFolderURL else { return }
        isScanning = true
        statusMessage = "Scanning \(source.lastPathComponent)…"
        groups = []
        parseErrors = []
        skippedFiles = []
        resolvedStartCache = [:]

        let discovery = await DJIFolderReader.read(folder: source, using: ffmpeg)

        groups = discovery.groups
        parseErrors = discovery.errors
        skippedFiles = discovery.skippedNonDJI
        // Pre-select the split recordings only — single lone clips need no join.
        selectSplitGroupsOnly()
        isScanning = false

        if groups.isEmpty {
            statusMessage = "No DJI video segments found in \(source.lastPathComponent)."
        } else {
            let segs = discovery.clipCount
            let splits = selectedCount
            statusMessage = "Found \(segs) segment\(segs == 1 ? "" : "s") in "
                + "\(groups.count) group\(groups.count == 1 ? "" : "s")"
                + (splits > 0 ? " — \(splits) split recording\(splits == 1 ? "" : "s") selected." : ".")
        }
    }

    // MARK: - Enqueue

    /// Builds one job per **selected** group and hands them to the queue (does not auto-start).
    /// Per the design handoff: groups with a still-unfinished job are skipped (no accidental
    /// duplicates), and the selection clears once the jobs are added.
    func addToQueue() {
        guard let source = sourceFolderURL, let outDir = outputFolderURL else { return }

        // A group is "already queued" if some unfinished job starts with the same first segment.
        let unfinishedFirstClipIDs = Set(
            queue.jobs.filter { !$0.status.isFinished }.compactMap { $0.clips.first?.id }
        )
        let toAdd = selectedGroups.filter { group in
            guard let firstID = group.clips.first?.id else { return false }
            return !unfinishedFirstClipIDs.contains(firstID)
        }
        let skipped = selectedGroups.count - toAdd.count

        // When renaming is on, resolve the whole batch's patterned + collision-free stems up front
        // (the counter and de-dup are batch-relative). Otherwise keep the unchanged default namer,
        // which leaves on-disk collisions to the queue's `resolveFilenameConflict`.
        let ext = settings.outputContainer.fileExtension
        let renamedStems = renameEnabled ? resolveRenamedStems(for: toAdd, in: outDir) : nil

        for (i, group) in toAdd.enumerated() {
            let destination = renamedStems
                .map { outDir.appendingPathComponent("\($0[i]).\(ext)") }
                ?? destinationURL(for: group, in: outDir, disambiguate: toAdd.count > 1)
            queue.addJob(
                folderName: source.lastPathComponent,
                sourceFolderURL: source,
                clips: group.clips,
                settings: settings,
                destinationURL: destination
            )
        }
        selectedGroupIDs = []
        statusMessage = "Added \(toAdd.count) job\(toAdd.count == 1 ? "" : "s") to the queue."
            + (skipped > 0 ? " Skipped \(skipped) already queued." : "")
    }

    func startQueue() { queue.startQueue() }

    // MARK: - Helpers

    /// Output file URL for a group. The queue resolves any on-disk filename collision by appending
    /// a counter, so this only needs to disambiguate *between* this scan's groups.
    private func destinationURL(for group: RecordGroup, in outDir: URL, disambiguate: Bool) -> URL {
        let ext = settings.outputContainer.fileExtension

        var base: String
        if !settings.outputFilename.isEmpty {
            base = settings.outputFilename
        } else if settings.useFolderNameAsFilename, let source = sourceFolderURL {
            base = source.lastPathComponent
        } else {
            base = group.clips.first?.stem ?? "joined"
        }

        // More than one group being added → tag each so they don't all collapse to one name.
        if disambiguate {
            base += group.variantSuffix.map { "_\($0)" } ?? "_\(group.groupIndex)"
        }

        return outDir.appendingPathComponent("\(base).\(ext)")
    }

    // MARK: - Rename (output-name templating)

    /// One before→after line in the rename popover's live preview.
    struct RenamePreviewRow: Identifiable {
        let id: UUID
        let original: String   // the first segment's real filename, e.g. `DJI_…_0009_D.MP4`
        let result: String     // the patterned output, e.g. `DJI_…_0009_D_2026-05-21_joined.mp4`
    }

    /// Resolved recording-start wall-clock for a group's first segment, memoised. Both the rename
    /// `{date}`/`{time}` tokens and the engine's date/timecode stamp derive from this one instant
    /// (via the same `RecordingStartResolver`), so the filename and the embedded metadata agree.
    func resolvedStartDate(for group: RecordGroup) -> Date? {
        if let cached = resolvedStartCache[group.id] { return cached }
        let date = group.clips.first.flatMap {
            RecordingStartResolver.resolve(forFirstSegment: $0, manualOverride: settings.dateOverride).date
        }
        resolvedStartCache[group.id] = date
        return date
    }

    /// Up to `limit` of the currently-selected recordings rendered through the active pattern, for
    /// the popover's live preview. De-dups within the previewed set so the user sees realistic
    /// `_2` suffixes; the enqueue path additionally seeds the queue + destination folder.
    func renamePreview(limit: Int = 3) -> [RenamePreviewRow] {
        let ext = settings.outputContainer.fileExtension
        var taken = Set<String>()
        return Array(selectedGroups.prefix(limit)).enumerated().map { i, group in
            let name = group.clips.first?.stem ?? "joined"
            let stem = RenamePatternEngine.uniqueStem(
                RenamePatternEngine.applyStem(
                    name: name, date: resolvedStartDate(for: group), options: renameOptions, index: i
                ),
                taken: taken
            )
            taken.insert(stem)
            let original = group.clips.first?.videoURL.lastPathComponent ?? "\(name).MP4"
            return RenamePreviewRow(id: group.id, original: original, result: "\(stem).\(ext)")
        }
    }

    /// Patterned, collision-free output stems for one Add-to-Queue batch. The `{###}` counter is
    /// batch-relative (0-based index) and de-dup runs against the running batch ∪ unfinished-queue ∪
    /// destination-folder listing, so no two outputs — or an existing file — collide.
    private func resolveRenamedStems(for groups: [RecordGroup], in outDir: URL) -> [String] {
        var taken = existingOutputStems(in: outDir)
        return groups.enumerated().map { i, group in
            let name = group.clips.first?.stem ?? "joined"
            let stem = RenamePatternEngine.uniqueStem(
                RenamePatternEngine.applyStem(
                    name: name, date: resolvedStartDate(for: group), options: renameOptions, index: i
                ),
                taken: taken
            )
            taken.insert(stem)
            return stem
        }
    }

    /// Stems already spoken for: every unfinished queue job's output + every file in the destination
    /// folder. (A finished job's output is on disk, so the folder listing already covers it.)
    private func existingOutputStems(in outDir: URL) -> Set<String> {
        var set = Set<String>()
        for job in queue.jobs where !job.status.isFinished {
            set.insert(job.destinationURL.deletingPathExtension().lastPathComponent)
        }
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: outDir, includingPropertiesForKeys: nil
        ) {
            for url in contents { set.insert(url.deletingPathExtension().lastPathComponent) }
        }
        return set
    }
}
