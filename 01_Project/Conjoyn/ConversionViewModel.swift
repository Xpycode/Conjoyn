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
    typealias DiscoveryReader = @Sendable (URL) async -> DJIFolderReader.Discovery
    typealias DateWarmer = @Sendable ([RecordGroup], Date?) async -> [UUID: Date?]
    private let discover: DiscoveryReader
    private let warmDates: DateWarmer
    private var scanTask: Task<Void, Never>?
    private var scanGeneration: UInt64 = 0
    private var publishedGeneration: UInt64?
    /// Row-thumbnail extraction (first frame of a group's first segment), shared across rows.
    let thumbnails: ThumbnailManager

    // MARK: - Pre-enqueue state

    @Published private(set) var sourceFolderURL: URL?
    @Published var outputFolderURL: URL?
    @Published var settings = ConversionSettings()

    /// Drives the "Apply new output folder to N pending jobs?" popover. Set true by
    /// `chooseOutputFolder()` when pending jobs target a different folder, including restored jobs.
    /// The popover's Keep/click-away resets it (the safe no-op).
    @Published var showApplyFolderPrompt = false

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

    /// Bumped when the background prewarm finishes filling `resolvedStartCache`, purely to trigger a
    /// re-render so a "sort by Date" snaps from the embedded-date fallback to the corrected order.
    /// (The cache itself is non-`@Published`; this is the observable signal.)
    @Published private var startDateRevision = 0

    @Published private(set) var groups: [RecordGroup] = []
    /// Which groups will be enqueued by `addToQueue`. Defaults after a scan to the **split**
    /// recordings only (the ones that actually need joining), so pointing at a whole SD card doesn't
    /// silently queue ~60 lone single clips. The user ticks/unticks individual rows.
    @Published private(set) var selectedGroupIDs: Set<UUID> = []

    /// Controls which recordings are visible in the list. Selection is independent — changing the
    /// filter does not clear existing selections, but `setFilter(_:)` auto-selects all matching rows.
    enum RecordingFilter { case all, splits, singles }
    @Published private(set) var recordingFilter: RecordingFilter = .all

    /// Live search query narrowing the recordings list. Display-only: unlike `setFilter(_:)` it
    /// never touches selection — a transient text filter silently changing what `addToQueue` will
    /// enqueue would be a trap. Cleared on rescan.
    @Published private(set) var searchText = ""

    /// Column the recordings list is ordered by. `.found` keeps the scanner's discovery order — the
    /// original pre-1.0.1 behaviour and the state every fresh scan resets to.
    enum SortKey: CaseIterable { case found, name, date, duration, size }
    @Published private(set) var sortKey: SortKey = .found
    @Published private(set) var sortAscending = true

    /// The view feed: `groups` filtered by `recordingFilter`, then ordered by the active sort. Kept
    /// as the single chokepoint so selection (by id) and the rename cache stay valid regardless of
    /// display order — only what the list *shows* is reordered, never `groups` itself.
    var filteredGroups: [RecordGroup] {
        var visible: [RecordGroup]
        switch recordingFilter {
        case .all:     visible = groups
        case .splits:  visible = groups.filter { $0.groupType == .split }
        case .singles: visible = groups.filter { $0.groupType == .single }
        }
        if let query = Self.normalizedQuery(searchText) {
            visible = visible.filter {
                Self.matchesSearch(query,
                                   title: $0.displayTitle,
                                   filenames: $0.clips.map(\.videoURL.lastPathComponent))
            }
        }
        guard sortKey != .found else { return visible }   // discovery order — leave untouched
        // Decorate-sort-undecorate: resolve each group's sort fields once (the date resolve is the
        // costly part), let `ordered(_:)` apply the key + direction + undated-last policy, then drop
        // back to groups.
        return Self.ordered(visible.map { (group: $0, field: sortField(for: $0)) },
                            field: { $0.field },
                            by: sortKey,
                            ascending: sortAscending)
            .map { $0.group }
    }
    @Published private(set) var parseErrors: [ClipParseError] = []
    @Published private(set) var skippedFiles: [String] = []
    @Published private(set) var isScanning = false
    @Published private(set) var statusMessage: String?

    init(queue: QueueManager = .shared,
         discover: DiscoveryReader? = nil,
         warmDates: DateWarmer? = nil) {
        self.queue = queue
        let ffmpeg = queue.ffmpeg
        self.discover = discover ?? { source in
            await DJIFolderReader.read(folder: source, using: ffmpeg)
        }
        self.warmDates = warmDates ?? { groups, override in
            await Task.detached(priority: .utility) {
                var resolved: [UUID: Date?] = [:]
                for group in groups {
                    let date = group.clips.first.flatMap {
                        RecordingStartResolver.resolve(forFirstSegment: $0, manualOverride: override).date
                    }
                    resolved.updateValue(date, forKey: group.id)
                }
                return resolved
            }.value
        }
        self.thumbnails = ThumbnailManager(ffmpeg: ffmpeg)
    }

    deinit { scanTask?.cancel() }

    // MARK: - Derived

    var totalClips: Int { groups.reduce(0) { $0 + $1.clipCount } }

    /// The groups that `addToQueue` will enqueue, in display order.
    var selectedGroups: [RecordGroup] { groups.filter { selectedGroupIDs.contains($0.id) } }
    var selectedCount: Int { selectedGroupIDs.count }

    var canAddToQueue: Bool {
        publishedGeneration == scanGeneration && !selectedGroups.isEmpty
            && outputFolderURL != nil && !isScanning
    }

    /// Pending (unstarted) jobs — the only ones `applyOutputFolderToPendingJobs` may re-point.
    var pendingJobCount: Int { queue.pendingCount }

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
    func selectSingleGroupsOnly() {
        selectedGroupIDs = Set(groups.filter { $0.groupType == .single }.map(\.id))
    }

    /// Sets the visibility filter and auto-selects all matching rows.
    func setFilter(_ filter: RecordingFilter) {
        recordingFilter = filter
        switch filter {
        case .all:     selectAllGroups()
        case .splits:  selectSplitGroupsOnly()
        case .singles: selectSingleGroupsOnly()
        }
    }

    /// Resets the filter to `.all` without changing selection. Called on rescan.
    func resetFilter() { recordingFilter = .all }

    // MARK: - Search

    func setSearch(_ text: String) { searchText = text }

    /// Clears the search query. Called on rescan so a new card starts unfiltered.
    func resetSearch() { searchText = "" }

    /// The effective search query: trimmed, `nil` when empty — a whitespace-only query must not
    /// narrow the list.
    static func normalizedQuery(_ raw: String) -> String? {
        let query = raw.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? nil : query
    }

    /// Whether one recording matches a search query: case-insensitive substring of either the row
    /// title (the stem range a split shows) or any segment's filename — so `GX016349` finds its
    /// recording even when the title reads `GX016349 – GX026349`. Static over plain strings so the
    /// match rule is unit-testable without a scanned card (mirrors `orders(_:before:by:)`).
    static func matchesSearch(_ query: String, title: String, filenames: [String]) -> Bool {
        title.localizedCaseInsensitiveContains(query)
            || filenames.contains { $0.localizedCaseInsensitiveContains(query) }
    }

    // MARK: - Sorting

    /// Picks the sort column. Clicking the active column flips direction (Finder behaviour);
    /// switching columns starts from that column's natural default direction.
    func setSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            sortAscending = Self.defaultAscending(for: key)
        }
    }

    /// Resets to discovery order. Called on rescan so a new card starts predictable.
    func resetSort() {
        sortKey = .found
        sortAscending = true
    }

    /// First-click direction per column. Name reads naturally A→Z; the numeric/time columns lead
    /// with the "interesting" end (newest, longest, biggest) the way Finder defaults Size to large-first.
    private static func defaultAscending(for key: SortKey) -> Bool {
        switch key {
        case .found, .name:           return true
        case .date, .duration, .size: return false
        }
    }

    /// The list-sort fields for one group, pulled out so the ordering logic stays pure and
    /// unit-testable (no `RecordGroup`, no date-resolver I/O). `date` is the **corrected** start.
    struct SortField: Equatable {
        var index: Int          // groupIndex — the stable tie-break
        var name: String
        var date: Date?
        var duration: Double
        var bytes: Int64
    }

    private func sortField(for g: RecordGroup) -> SortField {
        // Read the *already-resolved* date — never resolve here. Resolving opens `.SRT` files off the
        // SD card, and this runs inside `filteredGroups` during view-body evaluation on the main
        // thread, so a synchronous resolve would beachball the whole window on the first date sort.
        // Fall back to the in-memory embedded date until the background prewarm fills the cache (which
        // then bumps `startDateRevision` to re-sort into corrected order). `?? embedded` distinguishes
        // "key absent" (Date?? is .none) from "resolved to no date" (.some(nil), kept as-is).
        let resolved: Date? = resolvedStartCache[g.id] ?? g.displayStartDate
        return SortField(index: g.groupIndex,
                         name: g.displayTitle,
                         date: resolved,
                         duration: g.totalDurationSeconds,
                         bytes: g.totalBytes)
    }

    /// Orders two fields **ascending** for `key`, with a stable `index` tie-break so equal values
    /// (same size, same duration) keep a fixed order instead of jiggling between renders.
    /// `filteredGroups` reverses the whole result for descending. Internal so unit tests can drive it
    /// with plain values.
    static func orders(_ a: SortField, before b: SortField, by key: SortKey) -> Bool {
        func tie() -> Bool { a.index < b.index }
        switch key {
        case .found:
            return tie()
        case .name:
            let r = a.name.localizedStandardCompare(b.name)
            return r == .orderedSame ? tie() : r == .orderedAscending
        case .duration:
            return a.duration == b.duration ? tie() : a.duration < b.duration
        case .size:
            return a.bytes == b.bytes ? tie() : a.bytes < b.bytes
        case .date:
            // Sorts by the *corrected* recording start, so the order matches the date each row shows.
            // Undated rows (`date == nil`) are lifted out of this comparator entirely by `ordered(_:)`
            // below — they never reach here in the list path, so the `?? .distantPast` is only a
            // defensive fallback. The "undated always last" policy lives in `ordered(_:)`, which can
            // see the sort *direction*; this comparator is direction-agnostic (ascending-only).
            let da = a.date ?? .distantPast
            let db = b.date ?? .distantPast
            return da == db ? tie() : da < db
        }
    }

    /// Full list ordering for `key` + direction. `orders(_:before:by:)` only sorts ascending and has
    /// no notion of "undated"; this wrapper layers on (a) the descending reverse and (b) the
    /// **undated-rows-always-last** policy — a recording with no resolvable date (no SRT, unparseable
    /// filename, no embedded date, no filesystem date) stays pinned at the bottom in *both* sort
    /// directions, mirroring Finder's "—" behaviour. That can't be expressed through the outer reverse
    /// (which is all-or-nothing), so undated rows are partitioned out before the sort and re-appended
    /// after. Generic over the row type so it stays unit-testable with bare `SortField`s yet also
    /// drives `filteredGroups`' decorated `(group, field)` pairs — one tested code path.
    static func ordered<Row>(_ rows: [Row],
                             field: (Row) -> SortField,
                             by key: SortKey,
                             ascending: Bool) -> [Row] {
        guard key != .found else { return rows }   // discovery order — never reordered

        // Undated rows only exist for the date key (name/duration/size are non-optional). Split them
        // off, keeping them in stable discovery order (`index`) among themselves.
        let dated: [Row], undated: [Row]
        if key == .date {
            dated   = rows.filter { field($0).date != nil }
            undated = rows.filter { field($0).date == nil }
                          .sorted { field($0).index < field($1).index }
        } else {
            dated = rows; undated = []
        }

        let asc = dated.sorted { orders(field($0), before: field($1), by: key) }
        return (ascending ? asc : asc.reversed()) + undated
    }

    // MARK: - Folder selection

    func chooseSourceFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.message = "Choose a media folder (e.g. DCIM/100MEDIA)"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        setSourceFolder(url)
    }

    /// Sets the source folder and kicks off a scan. Also the entry point for drag-and-drop of a
    /// folder onto the empty state.
    @discardableResult
    func setSourceFolder(_ url: URL) -> Task<Void, Never> {
        sourceFolderURL = url
        if outputFolderURL == nil { outputFolderURL = url }
        return requestScan(source: url)
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

        Task { await acceptOutputFolder(url) }
    }

    /// Handles an accepted picker selection without changing already-queued destinations.
    /// Compare against the jobs, not the session-only selector (nil after restoring a queue).
    func acceptOutputFolder(_ url: URL) async {

        // Per-job destinations were frozen at enqueue from the *old* folder; changing the folder now
        // only governs future adds. If the folder actually changed and pending jobs exist, offer to
        // re-point them so the change isn't a silent miss (the trap hit live 2026-06-10k).
        outputFolderURL = url
        showApplyFolderPrompt = false
        if queue.jobs.contains(where: {
            $0.status == .pending && QueueManager.directoriesDiffer(
                $0.destinationURL.deletingLastPathComponent(), url
            )
        }) {
            // NSOpenPanel is ViewBridge-hosted (macOS 26+): presenting the popover in the same
            // runloop turn as panel dismissal races the remote view's async XPC teardown — its
            // stale notification observer throws and AppKit crash-on-exceptions kills the app
            // (crash 2026-07-18). Defer past the teardown before flipping the flag.
            do { try await Task.sleep(for: .milliseconds(400)) }
            catch { return }
            guard outputFolderURL == url else { return }
            showApplyFolderPrompt = true
        }
    }

    /// Re-points every pending job's output into the current `outputFolderURL` (Part B "Apply").
    /// Pending-only; preserves each job's filename stem and re-resolves collisions in `QueueManager`.
    func applyOutputFolderToPendingJobs() {
        guard let folder = outputFolderURL else { return }
        queue.reassignPendingDestinations(to: folder)
        showApplyFolderPrompt = false
    }

    // MARK: - Scan

    /// Invalidate synchronously at the UI action, before any new task can be scheduled.
    /// Returning the retained task also lets callers await discovery and its cache prewarm.
    @discardableResult
    func scan() -> Task<Void, Never>? {
        guard let source = sourceFolderURL else { return nil }
        return requestScan(source: source)
    }

    private func requestScan(source: URL) -> Task<Void, Never> {
        scanGeneration &+= 1
        let generation = scanGeneration
        scanTask?.cancel()
        publishedGeneration = nil
        selectedGroupIDs = []
        isScanning = true
        statusMessage = "Scanning \(source.lastPathComponent)…"
        groups = []
        parseErrors = []
        skippedFiles = []
        resolvedStartCache = [:]
        resetFilter()
        resetSort()
        resetSearch()

        let discover = self.discover
        let warmDates = self.warmDates
        let task = Task { [weak self] in
            let discovery = await discover(source)
            guard let self, self.scanGeneration == generation else { return }
            self.publish(discovery, source: source, generation: generation)
            // Cancellation cannot stop all filesystem/probe implementations. Ownership, not the
            // cancellation bit or source URL, is authoritative after every suspension.
            if !discovery.groups.isEmpty {
                let resolved = await warmDates(discovery.groups, self.settings.dateOverride)
                guard self.scanGeneration == generation else { return }
                for (id, date) in resolved where self.resolvedStartCache[id] == nil {
                    self.resolvedStartCache.updateValue(date, forKey: id)
                }
                self.startDateRevision &+= 1
            }
            self.scanTask = nil
        }
        scanTask = task
        return task
    }

    private func publish(_ discovery: DJIFolderReader.Discovery, source: URL, generation: UInt64) {
        publishedGeneration = generation
        groups = discovery.groups
        parseErrors = discovery.errors
        skippedFiles = discovery.skippedNonDJI
        // Pre-select the split recordings only — single lone clips need no join.
        selectSplitGroupsOnly()
        isScanning = false

        if groups.isEmpty {
            // Say *why* it's empty when we saw plausible media and rejected it on the name. The
            // "N skipped" counter lives in the recordings-list header, which isn't on screen when
            // there are no groups — without this the user gets silence for a folder full of movies.
            if skippedFiles.isEmpty {
                statusMessage = "No video segments found in \(source.lastPathComponent)."
            } else {
                let n = skippedFiles.count
                let reason = n == 1
                    ? "1 file isn't named like a DJI or GoPro recording."
                    : "\(n) files aren't named like DJI or GoPro recordings."
                statusMessage = "No recordings found in \(source.lastPathComponent) — " + reason
            }
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
        guard canAddToQueue, let source = sourceFolderURL, let outDir = outputFolderURL else { return }

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
