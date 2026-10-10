import Foundation
import Combine
import AppKit

@MainActor
protocol WatchFolderManagingCoordinator: AnyObject {
    var managerStatusPublisher: AnyPublisher<WatchFolderCoordinator.Status, Never> { get }
    var resolveOutputDestination: () -> WatchFolderEntry.OutputDestination { get set }
    func enable(rootURL: URL)
    func disable()
}

extension WatchFolderCoordinator: WatchFolderManagingCoordinator {
    var managerStatusPublisher: AnyPublisher<Status, Never> { $status.eraseToAnyPublisher() }
}

// MARK: - Watch Folder Manager (Wave 5D)

/// Owns the user's list of watch folders and runs one **isolated** `WatchFolderCoordinator` per
/// enabled entry. The coordinator (Wave 5C) is single-folder by construction and fully tested;
/// rather than rewrite it, this manager *composes* N of them, giving each its own bookmark key,
/// settings, and on-disk storage (ledger + group-state JSON) so they never collide.
///
/// **Why per-entry isolated ledgers:** clean teardown (removing a folder deletes its state) — but
/// it means cross-folder dedup is *not* automatic, so two overlapping roots would each enqueue the
/// same clips. The `rejectionReason(forAdding:existing:)` policy below is the guard against that.
///
/// **Observation:** `entries` drives the list; `statuses[id]` mirrors each coordinator's live
/// `status` (forwarded via Combine) so rows update without observing a dictionary of objects.
@MainActor
final class WatchFolderManager: ObservableObject {

    /// The result of an add attempt, so the UI can surface a rejection reason.
    enum AddResult: Equatable {
        case added(WatchFolderEntry)
        case rejected(reason: String)
    }

    // MARK: - Published state

    /// The persisted list of watch folders, in display order.
    @Published private(set) var entries: [WatchFolderEntry] = []

    /// Live coarse status per entry id, mirrored from each running coordinator. Disabled or
    /// offline entries read `.idle`.
    @Published private(set) var reviews: [UUID: [WatchFolderCoordinator.ReviewRecord]] = [:]
    private var reviewSinks: [UUID: AnyCancellable] = [:]

    @Published private(set) var statuses: [UUID: WatchFolderCoordinator.Status] = [:]

    // MARK: - Running coordinators

    private var coordinators: [UUID: any WatchFolderManagingCoordinator] = [:]
    private var activeRoots: [UUID: URL] = [:]
    // Session lifetime tombstones: remove/re-add and remounts must not reset worker capacity.
    private var discoveryBudgetsByEntry: [UUID: WatchDiscoveryBudget] = [:]
    private var discoveryBudgetsByRoot: [String: WatchDiscoveryBudget] = [:]
    private var budgetEntries: [UUID: WatchFolderEntry] = [:]

    func discoveryBudget(for entry: WatchFolderEntry, rootURL: URL) -> WatchDiscoveryBudget {
        let key = rootURL.standardizedFileURL.resolvingSymlinksInPath().path
        let oldKey = URL(fileURLWithPath: entry.rootPath).standardizedFileURL.resolvingSymlinksInPath().path
        let returning = budgetEntries.values.first { saved in
            guard let resolved = recovery.resolveRoot(saved) else { return false }
            return resolved.standardizedFileURL.resolvingSymlinksInPath().path == key
        }.flatMap { discoveryBudgetsByEntry[$0.id] }
        let budget = discoveryBudgetsByEntry[entry.id] ?? discoveryBudgetsByRoot[key] ?? returning
            ?? discoveryBudgetsByRoot[oldKey] ?? WatchDiscoveryBudget()
        budgetEntries[entry.id] = entry
        discoveryBudgetsByEntry[entry.id] = budget
        discoveryBudgetsByRoot[key] = budget
        discoveryBudgetsByRoot[oldKey] = budget
        return budget
    }
    @Published private(set) var unavailableEntryIDs: Set<UUID> = []

    enum RootEvent {
        case mounted
        case unmounted(URL)
    }

    struct RecoveryDependencies {
        var resolveRoot: (WatchFolderEntry) -> URL? = { $0.resolvedRootURL }
        var isAvailable: (URL) -> Bool = { url in
            var directory: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &directory)
                && directory.boolValue && FileManager.default.isReadableFile(atPath: url.path)
                && FileManager.default.isExecutableFile(atPath: url.path)
        }
        var observe: (@escaping @MainActor (RootEvent) -> Void) -> AnyCancellable = { receive in
            let center = NSWorkspace.shared.notificationCenter
            let mount = center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { receive(.mounted) }
            }
            let unmount = center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { note in
                guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                MainActor.assumeIsolated { receive(.unmounted(url)) }
            }
            return AnyCancellable {
                center.removeObserver(mount)
                center.removeObserver(unmount)
            }
        }
        // One fixed cadence, never one retry timer per event or per unavailable root.
        var schedule: (TimeInterval, @escaping @MainActor () -> Void) -> AnyCancellable = { interval, tick in
            let timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in
                MainActor.assumeIsolated { tick() }
            }
            return AnyCancellable { timer.invalidate() }
        }
    }

    private let admissionLedger: (String) -> ProcessedGroupLedger
    private let recovery: RecoveryDependencies
    private let coordinatorFactory: ((WatchFolderEntry, URL) -> any WatchFolderManagingCoordinator)?
    private var recoveryObservation: AnyCancellable?
    private var queueObservation: AnyCancellable?
    private var recoveryTimer: AnyCancellable?
    private var statusSinks: [UUID: AnyCancellable] = [:]

    // MARK: - Dependencies / persistence

    private let queue: QueueManager
    private let defaults: UserDefaults
    private let storeKey: String
    private let baseStorageDirectory: URL?

    /// - Parameters:
    ///   - queue: shared conversion queue all coordinators enqueue into.
    ///   - defaults: UserDefaults suite for the entry list + per-entry bookmarks (tests inject one).
    ///   - storeKey: key for the encoded `[WatchFolderEntry]` blob.
    ///   - baseStorageDirectory: root for per-entry ledger/state subdirs; `nil` ⇒ App Support/Conjoyn.
    init(
        queue: QueueManager = .shared,
        defaults: UserDefaults = .standard,
        storeKey: String = "watchFolder.entries",
        baseStorageDirectory: URL? = nil,
        recovery: RecoveryDependencies = RecoveryDependencies(),
        coordinatorFactory: ((WatchFolderEntry, URL) -> any WatchFolderManagingCoordinator)? = nil,
        admissionLedger: ((String) -> ProcessedGroupLedger)? = nil
    ) {
        self.admissionLedger = admissionLedger ?? { namespace in
            let base = baseStorageDirectory ?? FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
                .appendingPathComponent("Conjoyn", isDirectory: true)
            return ProcessedGroupLedger(storageDirectory: base.appendingPathComponent("WatchFolders/" + namespace))
        }
        self.recovery = recovery
        self.coordinatorFactory = coordinatorFactory
        self.queue = queue
        self.defaults = defaults
        self.storeKey = storeKey
        self.baseStorageDirectory = baseStorageDirectory
        self.entries = Self.loadEntries(from: defaults, key: storeKey)
        // Seed every entry's status to idle so rows render before any coordinator starts.
        for entry in entries { statuses[entry.id] = .idle }
        queueObservation = queue.$jobs.map { jobs in
            jobs.contains { $0.watchAdmissionPending == true && $0.status != .cancelled }
        }.removeDuplicates().sink { [weak self] _ in
            // @Published sends before mutation. Defer the lifetime check until jobs is current.
            Task { @MainActor [weak self] in self?.updateRecoveryObservation() }
        }
    }

    // MARK: - Lifecycle

    /// Called once at app launch: start a coordinator for every enabled entry whose volume is
    /// currently reachable. Idempotency on relaunch is handled by each entry's persisted ledger
    /// (a previously-joined group is never re-enqueued) — see `WatchFolderCoordinator`.
    func resumeAll() {
        for job in queue.jobs where job.watchAdmissionPending == true {
            if let id = job.watchIdentitySnapshot?.watchEntryID,
               !entries.contains(where: { $0.id == id && $0.enabled }) {
                queue.holdWatchAdmissions(entryID: id)
            }
        }
        recoverAdmissions()
        updateRecoveryObservation()
        reconcileRoots()
    }

    private func updateRecoveryObservation() {
        guard entries.contains(where: { $0.enabled }) || queue.jobs.contains(where: {
            $0.watchAdmissionPending == true && $0.status != .cancelled
        }) else {
            recoveryObservation = nil
            recoveryTimer = nil
            return
        }
        guard recoveryObservation == nil else { return }
        recoveryObservation = recovery.observe { [weak self] event in
            guard let self else { return }
            switch event {
            case .mounted: self.reconcileRoots()
            case .unmounted(let volume):
                // Invalidate immediately, even if filesystem availability still reports the old
                // path during notification delivery. Recovery waits for mount or the next tick.
                for (id, root) in self.activeRoots where Self.pathsOverlap(volume, root) {
                    self.markUnavailable(id)
                }
            }
        }
        recoveryTimer = recovery.schedule(5) { [weak self] in self?.reconcileRoots(); self?.recoverAdmissions() }
    }

    private func reconcileRoots() {
        for entry in entries where entry.enabled {
            guard let root = recovery.resolveRoot(entry), recovery.isAvailable(root) else {
                markUnavailable(entry.id)
                continue
            }
            if activeRoots[entry.id] == root, coordinators[entry.id] != nil { continue }
            deactivate(entry.id)
            activate(entry, resolvedRoot: root)
        }
    }

    private func markUnavailable(_ id: UUID) {
        deactivate(id)
        unavailableEntryIDs.insert(id)
    }

    // MARK: - Add / remove

    /// Adds a new watch folder for `rootURL`, enabled by default, and starts monitoring it.
    /// Returns `.rejected` (with a reason for the UI) when the overlap policy forbids it or a
    /// bookmark can't be made.
    @discardableResult
    func addFolder(rootURL: URL) -> AddResult {
        if let reason = Self.rejectionReason(forAdding: rootURL, existing: entries) {
            return .rejected(reason: reason)
        }
        guard let bookmark = try? WatchFolderEntry.makeBookmark(for: rootURL) else {
            return .rejected(reason: "Couldn't create a bookmark for that folder — it may be unreadable.")
        }
        let entry = WatchFolderEntry(
            id: UUID(),
            rootBookmark: bookmark,
            rootPath: rootURL.path,
            enabled: true
        )
        entries.append(entry)
        statuses[entry.id] = .idle
        save()
        updateRecoveryObservation()
        activate(entry)
        return .added(entry)
    }

    /// Stops monitoring, forgets the entry, and deletes its per-entry persistence (bookmark key +
    /// ledger/state subdirectory). The conversion queue is untouched — any in-flight join finishes.
    func remove(_ id: UUID) {
        queue.holdWatchAdmissions(entryID: id)
        deactivate(id)
        entries.removeAll { $0.id == id }
        statuses[id] = nil
        unavailableEntryIDs.remove(id)
        updateRecoveryObservation()
        WatchFolderBookmark(defaults: defaults, key: Self.bookmarkKey(id)).clear()
        // Retain admission/history storage: pending queue snapshots own its recovery path.
        // Orphan cleanup is deliberately outside this repair.
        save()
    }

    // MARK: - Mutate an entry

    /// Toggles a folder on/off, starting or stopping its coordinator to match.
    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].enabled = on
        save()
        updateRecoveryObservation()
        if on { activate(entries[idx]) } else {
            queue.holdWatchAdmissions(entryID: id)
            deactivate(id)
            unavailableEntryIDs.remove(id)
        }
    }

    /// Sets (or clears, with `nil`) the dedicated output folder. Live-updates a running coordinator
    /// immediately — joins enqueued after this land in the new destination.
    func setOutputFolder(_ id: UUID, url: URL?) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        if let url {
            entries[idx].outputBookmark = try? WatchFolderEntry.makeBookmark(for: url)
            entries[idx].outputPath = url.path
        } else {
            entries[idx].outputBookmark = nil
            entries[idx].outputPath = nil
        }
        save()
        let entry = entries[idx]
        coordinators[id]?.resolveOutputDestination = { entry.outputDestination }
    }

    /// Replaces the per-folder tunables. A running coordinator captured the old settings at
    /// construction (they drive its poll cadence and gates), so it's rebuilt to pick up the change.
    func updateSettings(_ id: UUID, _ settings: WatchFolderSettings) {
        guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[idx].settings = settings
        save()
        if entries[idx].enabled {
            deactivate(id)
            activate(entries[idx])
        }
    }

    // MARK: - Coordinator orchestration

    /// Resolve the saved bookmark, never the last-known display path, before starting.
    private func activate(_ entry: WatchFolderEntry, resolvedRoot: URL? = nil) {
        guard entry.enabled, coordinators[entry.id] == nil else { return }
        guard let rootURL = resolvedRoot ?? recovery.resolveRoot(entry), recovery.isAvailable(rootURL) else {
            markUnavailable(entry.id)
            return
        }
        if let index = entries.firstIndex(where: { $0.id == entry.id }), entries[index].rootPath != rootURL.path {
            entries[index].rootPath = rootURL.path
            save()
        }
        unavailableEntryIDs.remove(entry.id)
        let coordinator = coordinatorFactory?(entry, rootURL) ?? makeCoordinator(for: entry, rootURL: rootURL)
        if let concrete = coordinator as? WatchFolderCoordinator {
            concrete.discoveryBudget = discoveryBudget(for: entry, rootURL: rootURL)
        }
        coordinator.resolveOutputDestination = { entry.outputDestination }
        // Mirror the coordinator's @Published status into our per-id map. The publisher emits on
        // the main actor (status is only mutated there), so assumeIsolated is sound.
        statusSinks[entry.id] = coordinator.managerStatusPublisher.sink { [weak self] status in
            MainActor.assumeIsolated { self?.statuses[entry.id] = status }
        }
        if let concrete = coordinator as? WatchFolderCoordinator {
            reviewSinks[entry.id] = concrete.$reviewRecords.sink { [weak self] records in
                MainActor.assumeIsolated { self?.reviews[entry.id] = records }
            }
        }
        activeRoots[entry.id] = rootURL
        coordinators[entry.id] = coordinator
        coordinator.enable(rootURL: rootURL)
    }

    /// Stops + releases the coordinator for `id` (if any) and resets its status to idle.
    private func deactivate(_ id: UUID) {
        // Drop publication ownership before stopping the old coordinator. W4 additionally
        // fences all asynchronous discovery/admission writes inside that coordinator.
        reviewSinks[id] = nil
        reviews[id] = nil
        statusSinks[id] = nil
        activeRoots[id] = nil
        coordinators[id]?.disable()
        coordinators[id] = nil
        if entries.contains(where: { $0.id == id }) { statuses[id] = .idle }
    }

    /// Constructs a fully-isolated coordinator for `entry`: real discovery/sampling/clock, the
    /// shared queue, a per-entry ledger + group-state dir, a per-entry bookmark key, the entry's
    /// own settings, and its chosen output folder. Mirrors `WatchFolderCoordinator`'s production
    /// convenience init but with per-entry namespacing.
    private func makeCoordinator(for entry: WatchFolderEntry, rootURL: URL) -> WatchFolderCoordinator {
        let storage = entryStorageDirectory(entry.id)
        let ffmpeg = FFmpegWrapper()
        let coordinator = WatchFolderCoordinator(
            discover: { url in
                await DJIFolderReader.read(folder: url, using: ffmpeg).groups
            },
            sample: { url in
                let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
                guard
                    let size = (attrs?[.size] as? NSNumber)?.int64Value,
                    let modified = attrs?[.modificationDate] as? Date
                else { return nil }
                return FileStabilityGate.Sample(size: size, modified: modified)
            },
            now: { Date() },
            queue: queue,
            ledger: ProcessedGroupLedger(storageDirectory: storage),
            bookmark: WatchFolderBookmark(defaults: defaults, key: Self.bookmarkKey(entry.id)),
            settings: entry.settings,
            storageDirectory: storage,
            watchEntryID: entry.id,
            ledgerNamespace: entry.id.uuidString,
            discoverBound: { url in
                let result = await DJIFolderReader.read(folder: url, using: ffmpeg)
                return WatchDiscovery(groups: result.groups, generations: result.metadataGenerations, retryPaths: result.retryPaths)
            }
        )
        coordinator.resolveOutputDestination = { entry.outputDestination }
        coordinator.reloadHistory = { [admissionLedger] in admissionLedger(entry.id.uuidString) }
        return coordinator
    }

    func resolveReview(entryID: UUID, recordingID: String, as resolution: ProcessedGroupLedger.Resolution) {
        (coordinators[entryID] as? WatchFolderCoordinator)?.resolveReview(recordingID, as: resolution)
    }

    /// Recovery belongs to the manager, not a monitor. MainActor plus synchronous persistence
    /// serializes this with every live coordinator's ledger writes; removed entries use their
    /// saved namespace. Never derive storage ownership from a remounted source path.
    func recoverAdmissions() {
        var released = false
        for job in queue.jobs where job.watchAdmissionPending == true && job.status == .pending {
            guard let snapshot = job.watchIdentitySnapshot,
                  UUID(uuidString: snapshot.ledgerNamespace) != nil else { continue }
            let live = snapshot.ledgerNamespace == snapshot.watchEntryID.uuidString
                ? coordinators[snapshot.watchEntryID] as? WatchFolderCoordinator : nil
            if queue.recoverWatchAdmission(job.id, commit: { snapshot in
                if let live { try live.commitAdmission(snapshot) }
                else {
                    var ledger = admissionLedger(snapshot.ledgerNamespace)
                    try ledger.commitAdmission(snapshot.identity)
                }
            }) { released = true }
        }
        if released { queue.startQueue(automatic: true) }
        updateRecoveryObservation()
    }

    // MARK: - Per-entry persistence namespacing

    private static func bookmarkKey(_ id: UUID) -> String { "watchFolder.\(id.uuidString).rootBookmark" }

    private func entryStorageDirectory(_ id: UUID) -> URL? {
        let base: URL?
        if let baseStorageDirectory {
            base = baseStorageDirectory
        } else {
            base = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
                .appendingPathComponent("Conjoyn", isDirectory: true)
        }
        guard let base else { return nil }
        let dir = base.appendingPathComponent("WatchFolders/\(id.uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - Entry list persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        defaults.set(data, forKey: storeKey)
    }

    static func loadEntries(from defaults: UserDefaults, key: String) -> [WatchFolderEntry] {
        guard
            let data = defaults.data(forKey: key),
            let decoded = try? JSONDecoder().decode([WatchFolderEntry].self, from: data)
        else { return [] }
        return decoded
    }

    // MARK: - Overlap policy

    /// Decides whether `candidate` may be added given the `existing` watch folders. Return a short,
    /// human-readable reason to **reject**, or `nil` to **allow**.
    ///
    /// This is the correctness guard for multi-folder: each entry has an isolated ledger, so two
    /// roots that point at the same tree (or one nested inside the other) would each discover and
    /// enqueue the *same* clips — a double join. `pathsOverlap(_:_:)` below detects that case.
    ///
    /// **Policy:** reject when `candidate` is the same folder as, nested inside, or a parent of any
    /// existing root. An existing entry whose volume is currently offline **still blocks** — we fall
    /// back to its persisted last-known `rootPath` so a later re-mount can't silently resurrect an
    /// overlapping pair into a double join. Non-overlapping folders are always allowed.
    static func rejectionReason(forAdding candidate: URL, existing: [WatchFolderEntry]) -> String? {
        for entry in existing {
            // Offline volumes still block: resolve the live bookmark when possible, else compare
            // against the persisted last-known path (an offline folder can re-mount and overlap).
            let existingURL = entry.resolvedRootURL ?? URL(fileURLWithPath: entry.rootPath)
            if pathsOverlap(candidate, existingURL) {
                return "That folder overlaps “\(entry.rootDisplayName)”, which is already watched. "
                    + "Watching nested folders would join the same clips twice."
            }
        }
        return nil
    }

    /// True when `a` and `b` are the same directory or one is nested inside the other (so monitoring
    /// both would discover overlapping files). Compares standardized, symlink-resolved components.
    static func pathsOverlap(_ a: URL, _ b: URL) -> Bool {
        let ac = a.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let bc = b.standardizedFileURL.resolvingSymlinksInPath().pathComponents
        let n = min(ac.count, bc.count)
        return Array(ac.prefix(n)) == Array(bc.prefix(n))
    }
}
