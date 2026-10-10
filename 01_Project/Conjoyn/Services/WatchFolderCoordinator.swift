import Foundation

// MARK: - Watch Folder Coordinator (Wave 5C, task 5.9 + 5.10)

/// Thin `@MainActor` shell that wires `WatchFolderReconciler` (the pure brain) to the real
/// filesystem, queue, ledger, and FSEvents monitor.
///
/// **Responsibilities:** hold injectable dependencies, orchestrate the poll cycle, enqueue
/// ready groups, persist state, and support relaunch resume. All policy decisions are
/// delegated to `WatchFolderReconciler` so this class stays testable in isolation.
///
/// **Dependency injection pattern** matches `ProcessedGroupLedger` and `SpeedTracker`: every
/// external collaborator (discovery, sampling, clock, queue, ledger, settings, bookmark) is
/// injectable so tests can drive the coordinator without FFmpeg or a real filesystem.
@MainActor
final class WatchFolderCoordinator: ObservableObject {

    // MARK: - Status

    /// Coarse status exposed to the UI (Wave 5D). Kept intentionally lean — the UI wave owns
    /// the presentation; this type only needs to surface enough for a meaningful indicator.
    enum Status: Equatable, Sendable {
        /// FSEvents monitor is not running.
        case idle
        /// Configured output cannot currently be used; polling continues for recovery.
        case outputUnavailable
        /// History could not be read or saved; further automatic admission is paused.
        case historyUnavailable
        case discoveryStalled
        /// Monitor is active; N groups have been observed but have not yet settled / completed.
        case watching(settlingCount: Int)
        /// Groups have been enqueued into `QueueManager`.
        case queued(count: Int)
    }

    @Published private(set) var status: Status = .idle
    struct ReviewRecord: Identifiable {
        let descriptor: WatchRecordingDescriptor
        let group: RecordGroup
        let generations: [String: WatchFileGeneration]
        let reason: String
        var id: String { descriptor.identity.ledgerKey }
    }
    @Published private(set) var reviewRecords: [ReviewRecord] = []
    private let persistSettings: (WatchFolderSettings) -> Void
    private let watchEntryID: UUID
    private let ledgerNamespace: String
    private let discoverBound: (@Sendable (URL) async -> WatchDiscovery)?
    private let fileIdentifier: @Sendable (URL) -> String?
    // Filename membership is independent of metadata probing: even an unreadable new video
    // can be a missing predecessor. Only a coherent, complete bucket may authorize admission.
    private struct MembershipKey: Hashable, Sendable {
        let family: String
        let variant: String?
        let recording: Int?
    }
    private typealias Membership = [MembershipKey: Set<String>]
    private struct MembershipSnapshot: Sendable {
        let buckets: Membership
        let rootPaths: [String]
    }
    private var membershipGenerations: Membership = [:]
    private var membershipTask: (id: UUID, events: Int, task: Task<MembershipSnapshot?, Never>)?
    private var membershipRequestID: UUID?
    private let membershipReader: @Sendable (URL) async -> [URL]?
    private let membershipTimeoutSleep: @Sendable (TimeInterval) async -> Void
    private var metadataGenerations: [String: WatchFileGeneration] = [:]
    private var rejectedProbePaths: [URL] = []
    private var rejectedProbeSamples: [String: [FileStabilityGate.Sample]] = [:]
    private var lifecycleGeneration = 0
    private var disabled = false
    private var currentRoot: URL?
    private var invalidatedApprovals: Set<String> = []
    private var approvedGenerations: [String: [String: WatchFileGeneration]] = [:]

    var reloadHistory: (() -> ProcessedGroupLedger)?
    func commitAdmission(_ snapshot: WatchIdentitySnapshot) throws {
        guard snapshot.ledgerNamespace == ledgerNamespace else {
            throw ProcessedGroupLedger.LedgerError.unavailable("Admission belongs to another history namespace.")
        }
        if ledger.persistenceError != nil, let reloadHistory { ledger = reloadHistory() }
        try ledger.commitAdmission(snapshot.identity)
    }

    /// A review result only authorizes this exact observed generation. Admission runs through
    /// the next normal readiness pass; dismissing the sheet never creates a decision.
    func resolveReview(_ id: String, as resolution: ProcessedGroupLedger.Resolution) async {
        guard let currentRoot, await refreshMembership(rootURL: currentRoot) != nil else { return }
        guard !disabled, resolution != .admitted,
              let record = reviewRecords.first(where: { $0.id == id }),
              record.generations.allSatisfy({ generation(at: URL(fileURLWithPath: $0.key)) == $0.value }) else {
            reviewRecords.removeAll { $0.id == id }
            return
        }
        do {
            try ledger.resolve(record.descriptor.identity, as: resolution)
            invalidatedApprovals.remove(id)
            approvedGenerations[id] = record.generations
            reviewRecords.removeAll { $0.id == id }
        } catch { status = .historyUnavailable }
    }

    private func invalidateChangedApprovals() {
        for (id, stamps) in approvedGenerations where !stamps.allSatisfy({
            generation(at: URL(fileURLWithPath: $0.key)) == $0.value
        }) {
            invalidatedApprovals.insert(id)
        }
    }

    private func generation(at url: URL) -> WatchFileGeneration? {
        sample(url).map { WatchFileGeneration(sample: $0, identifier: fileIdentifier(url)) }
    }

    // MARK: - Output folder (Wave 5D)

    /// Resolve afresh on every pass and immediately before enqueue. The manager captures the
    /// saved entry, so bookmark failures retain configured intent and restored volumes recover.
    var resolveOutputDestination: () -> WatchFolderEntry.OutputDestination = { .unconfigured } {
        didSet { refreshOutputAvailability() }
    }

    private func currentOutputDestination() -> WatchFolderEntry.OutputDestination {
        let destination = resolveOutputDestination()
        if case .resolved(let url) = destination,
           !WatchFolderEntry.isUsableOutputDirectory(url) { return .unavailable }
        return destination
    }

    private func refreshOutputAvailability() {
        guard historyIsAvailable() else { return }
        if currentOutputDestination() == .unavailable {
            status = .outputUnavailable
        } else if status == .outputUnavailable {
            status = watchFolder == nil ? .idle : .watching(settlingCount: 0)
        }
    }

    private func historyIsAvailable() -> Bool {
        if ledger.persistenceError != nil, let reloadHistory {
            ledger = reloadHistory()
            // Reopening readable bytes alone cannot prove a previously failed write recovered.
            _ = ledger.save()
        }
        guard ledger.persistenceError == nil else {
            status = .historyUnavailable
            return false
        }
        return true
    }

    // MARK: - Persisted group states

    /// In-memory snapshot of per-group `WatchGroupState`, keyed by stable fingerprint.
    /// Persisted to JSON (same `storageDirectory` pattern as `ProcessedGroupLedger`) so relaunch
    /// can restore groups that were mid-flight at quit without losing their progress marker.
    private var groupStates: [String: WatchGroupState] = [:]
    private let groupStatesFileName = "watch_group_states.json"
    private let groupStatesURL: URL?

    // MARK: - Injectable dependencies

    /// Discovers groups from a folder URL. Default calls `DJIFolderReader.read`.
    private let discover: @Sendable (URL) async -> [RecordGroup]

    /// Samples a file's current size and mtime. Default reads `FileManager` attributes.
    /// Returns `nil` when the file is inaccessible (e.g. SD card ejected mid-poll).
    private let sample: @Sendable (URL) -> FileStabilityGate.Sample?

    /// Returns the current wall-clock time. Default `Date()`.
    /// Injected so tests can supply a deterministic clock.
    private let now: @Sendable () -> Date

    private let queue: QueueManager
    private var ledger: ProcessedGroupLedger
    private let bookmark: WatchFolderBookmark
    private var settings: WatchFolderSettings

    // MARK: - Private state

    /// The live FSEvents monitor; `nil` when the coordinator is idle.
    private var watchFolder: WatchFolder?

    /// Repeating poll timer (fires at `settings.pollInterval`). Supplements FSEvents with a
    /// time-based cadence to advance the stability-gate sample history even when the filesystem
    /// is quiet (no new change events, but the gate still needs more identical samples).
    private var pollTimer: Timer?

    /// Guards the heavy **discovery** path (FSEvents-driven: per-clip ffprobe scan of the whole root).
    /// Events received in flight retain one coalesced trailing discovery. Bounded by `settings.discoverTimeout` (`withDiscoverTimeout` below) so a
    /// wedged ffprobe / stalled mount can't latch this `true` forever and silently kill the watcher.
    private var isDiscovering = false
    private var activeDiscovery: UUID?
    private(set) var refreshTask: Task<Void, Never>?
    private var scheduledRefreshID: UUID?
    private var discoverySequence = 0
    private var pendingRefresh = false
    private var retryDeadline: Date?
    private(set) var eventGeneration = 0
    // Assigned by the manager before enable; retained across coordinator replacement.
    var discoveryBudget = WatchDiscoveryBudget()
    private let timeoutSleep: @Sendable (TimeInterval) async -> Void

    private func schedulePendingRefresh(rootURL: URL, lifecycle: Int) {
        guard !disabled, lifecycle == lifecycleGeneration, pendingRefresh, !isDiscovering,
              scheduledRefreshID == nil else { return }
        guard retryDeadline.map({ now() >= $0 }) ?? true else { return }
        guard discoveryBudget.hasCapacity else { status = .discoveryStalled; return }
        let scheduledID = UUID()
        let sequence = discoverySequence
        scheduledRefreshID = scheduledID
        refreshTask = Task { @MainActor [weak self] in
            guard let self, !self.disabled, self.lifecycleGeneration == lifecycle,
                  self.scheduledRefreshID == scheduledID else { return }
            self.scheduledRefreshID = nil
            guard self.discoverySequence == sequence else { return }
            await self.reconcile(rootURL: rootURL, rediscover: true)
        }
    }

    /// Guards the cheap **re-sample** cadence (poll-timer-driven: a `stat` per known clip, no ffprobe).
    /// Deliberately **separate** from `isDiscovering` so a wedged discovery never blocks the cadence —
    /// already-discovered groups keep accumulating stability samples and can still settle + enqueue
    /// while discovery is stuck or timing out.
    private var isResampling = false

    /// Groups from the most recent **discovery** pass. The poll timer re-samples these (cheap
    /// `stat`s) to advance the stability gate without re-running discovery's per-clip ffprobe;
    /// only an FSEvents change (a file actually appeared/changed) triggers a fresh discovery.
    private var lastGroups: [RecordGroup] = []

    /// Per-clip sample history, keyed by the clip's video file path.
    /// Appended on every poll; capped to `sampleHistoryCap` to bound memory.
    private var sampleHistory: [String: [FileStabilityGate.Sample]] = [:]

    /// Maximum sample history length per clip. A cap of 5× requiredStablePolls is generous:
    /// the gate only needs the tail, so extra history is harmless but we don't grow unboundedly.
    private let sampleHistoryCap = 15

    /// Per-group last-change wall-clock timestamp, keyed by stable fingerprint.
    /// Reset whenever a clip's sample changes OR a new member appears. Used to compute `quietElapsed`.
    private var groupLastChanged: [String: Date] = [:]

    /// Total groups successfully enqueued this session (drives `.queued` status).
    private var sessionEnqueuedCount = 0

    // MARK: - Init

    /// Production init — all dependencies use real implementations.
    ///
    /// - Parameter storageDirectory: Directory for `watch_group_states.json`. `nil` resolves to
    ///   `~/Library/Application Support/Conjoyn`. Tests pass a temp dir.
    convenience init(storageDirectory: URL? = nil) {
        let ffmpeg = FFmpegWrapper()
        self.init(
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
            queue: .shared,
            ledger: ProcessedGroupLedger(storageDirectory: storageDirectory),
            bookmark: WatchFolderBookmark(),
            settings: WatchFolderSettings.load(),
            storageDirectory: storageDirectory,
            discoverBound: { url in
                let result = await DJIFolderReader.read(folder: url, using: ffmpeg)
                return WatchDiscovery(groups: result.groups, generations: result.metadataGenerations, retryPaths: result.retryPaths)
            },
            persistSettings: { $0.save() }
        )
    }

    /// Full injectable init for tests and the convenience overload above.
    init(
        discover: @escaping @Sendable (URL) async -> [RecordGroup],
        sample: @escaping @Sendable (URL) -> FileStabilityGate.Sample?,
        now: @escaping @Sendable () -> Date,
        queue: QueueManager,
        ledger: ProcessedGroupLedger,
        bookmark: WatchFolderBookmark,
        settings: WatchFolderSettings,
        storageDirectory: URL? = nil,
        watchEntryID: UUID = UUID(),
        ledgerNamespace: String? = nil,
        discoverBound: (@Sendable (URL) async -> WatchDiscovery)? = nil,
        fileIdentifier: @escaping @Sendable (URL) -> String? = { WatchFileGeneration.read($0)?.identifier },
        persistSettings: @escaping (WatchFolderSettings) -> Void = { _ in },
        membershipReader: @escaping @Sendable (URL) async -> [URL]? = { url in
            WatchFolderCoordinator.readMembershipFiles(rootURL: url)
        },
        membershipTimeoutSleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        },
        timeoutSleep: @escaping @Sendable (TimeInterval) async -> Void = { seconds in
            try? await Task.sleep(nanoseconds: UInt64(max(0, seconds) * 1_000_000_000))
        }
    ) {
        self.membershipReader = membershipReader
        self.membershipTimeoutSleep = membershipTimeoutSleep
        self.timeoutSleep = timeoutSleep
        self.persistSettings = persistSettings
        self.watchEntryID = watchEntryID
        self.ledgerNamespace = ledgerNamespace ?? watchEntryID.uuidString
        self.discoverBound = discoverBound
        self.fileIdentifier = fileIdentifier
        self.discover = discover
        self.sample = sample
        self.now = now
        self.queue = queue
        self.ledger = ledger
        self.bookmark = bookmark
        self.settings = settings

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
            self.groupStatesURL = dir.appendingPathComponent(groupStatesFileName)
        } else {
            self.groupStatesURL = nil
        }

        self.groupStates = Self.loadGroupStates(from: groupStatesURL)
        if ledger.persistenceError != nil { status = .historyUnavailable }
    }

    // MARK: - Enable / Disable

    /// Activates the watch-folder for `rootURL`: persists the bookmark, marks settings enabled,
    /// starts FSEvents monitoring, and kicks an immediate rescan.
    func enable(rootURL: URL) {
        if currentRoot != nil { invalidateLifecycle() }
        disabled = false
        currentRoot = rootURL
        do {
            try bookmark.save(url: rootURL)
        } catch {
            #if DEBUG
            print("[WatchFolderCoordinator] bookmark save failed: \(error)")
            #endif
        }

        settings.enabled = true
        persistSettings(settings)

        startMonitor(rootURL: rootURL)
        let lifecycle = lifecycleGeneration
        Task { @MainActor [weak self] in
            guard let self, self.lifecycleGeneration == lifecycle, !self.disabled else { return }
            await self.rescan(rediscover: true)
        }
    }

    /// Deactivates the watch-folder: stops FSEvents monitoring, cancels the poll timer, and
    /// persists the disabled state. No in-flight job is touched — the queue runs to completion.
    func disable() {
        disabled = true
        invalidateLifecycle()
        settings.enabled = false
        persistSettings(settings)
        stopMonitor()
        status = .idle
    }

    private func invalidateLifecycle() {
        lifecycleGeneration += 1
        activeDiscovery = nil
        refreshTask?.cancel()
        refreshTask = nil
        scheduledRefreshID = nil
        isDiscovering = false
        isResampling = false
        pendingRefresh = false
        retryDeadline = nil
        groupLastChanged.removeAll()
        invalidatedApprovals.formUnion(approvedGenerations.keys)
        metadataGenerations.removeAll()
        membershipGenerations.removeAll()
        membershipTask?.task.cancel()
        membershipTask = nil
        membershipRequestID = nil
        reviewRecords.removeAll()
        lastGroups.removeAll()
        sampleHistory.removeAll()
        rejectedProbePaths.removeAll()
        rejectedProbeSamples.removeAll()
    }

    // MARK: - Relaunch Resume (task 5.10)

    /// Called at app launch when `settings.enabled == true` to restore the previously active
    /// watch-folder without re-enqueueing groups that are already in the queue or ledger.
    ///
    /// The `QueueManager` already persisted unfinished jobs, so on relaunch those jobs come back
    /// as `.pending`. We compute `liveQueueFingerprints` from those jobs and call
    /// `WatchFolderReconciler.shouldReenqueue` to skip any group already represented — preventing
    /// a double-enqueue of a group that was mid-flight at quit.
    func resume() {
        guard settings.enabled, let rootURL = bookmark.resolve() else { return }

        enable(rootURL: rootURL)
    }

    // MARK: - Private: Monitor lifecycle

    private func startMonitor(rootURL: URL) {
        stopMonitor() // idempotent teardown of any previous monitor

        let lifecycle = lifecycleGeneration
        let wf = WatchFolder(url: rootURL, latency: 1.0) { [weak self] in
            // WatchFolder's onChange callback is @Sendable (GCD queue). Hop to MainActor.
            // A real filesystem change → re-discover (a new/changed segment may exist).
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleGeneration == lifecycle, !self.disabled else { return }
                await self.rescan(rediscover: true)
            }
        }
        wf.start()
        watchFolder = wf

        // Poll timer: advances sample history even when the filesystem is quiet (no FSEvents).
        // The timer fires on the main RunLoop (same actor context where startMonitor runs), so
        // spawning a Task to hop to @MainActor is safe and keeps the timer closure non-capturing.
        pollTimer = Timer.scheduledTimer(
            withTimeInterval: settings.pollInterval,
            repeats: true
        ) { [weak self] _ in
            // Cadence pass: re-sample known files only (cheap), no ffprobe re-discovery.
            Task { @MainActor [weak self] in
                guard let self, self.lifecycleGeneration == lifecycle, !self.disabled else { return }
                await self.rescan(rediscover: false)
            }
        }

        status = .watching(settlingCount: 0)
        refreshOutputAvailability()
    }

    private func stopMonitor() {
        watchFolder?.stop()
        watchFolder = nil
        pollTimer?.invalidate()
        pollTimer = nil
    }

    // MARK: - Private: Rescan

    /// The core reconciliation loop.
    ///
    /// - Parameter rediscover: `true` for an FSEvents-driven pass (a file changed → re-run the
    ///   heavy discovery/ffprobe scan). `false` for the poll-timer cadence (re-sample the already
    ///   discovered groups' files only — a `stat` per clip — so the stability gate can confirm a
    ///   plateau without spawning ffprobe every `pollInterval`).
    private func rescan(rediscover: Bool) async {
        guard let rootURL = bookmark.resolve() else { return }
        if rediscover { await sourceDidChange(rootURL: rootURL) }
        else { await reconcile(rootURL: rootURL, rediscover: false) }
    }

    /// Same entry point for the real FSEvent callback and deterministic event tests. Resampling
    /// identifies affected cached clips; unchanged generations remain available during a stall.
    func sourceDidChange(rootURL: URL) async {
        guard !disabled else { return }
        eventGeneration += 1
        pendingRefresh = true
        invalidatedApprovals.formUnion(approvedGenerations.keys)
        metadataGenerations = metadataGenerations.filter { generation(at: URL(fileURLWithPath: $0.key)) == $0.value }
        reviewRecords.removeAll { record in !record.generations.allSatisfy {
            generation(at: URL(fileURLWithPath: $0.key)) == $0.value
        } }
        await reconcile(rootURL: rootURL, rediscover: true)
    }

    /// One reconciliation pass against an explicit root. `rescan` resolves the bookmark and calls
    /// this; production fires it from FSEvents / the poll timer. **Test seam:** the suite calls it
    /// directly with a temp root so it can `await` a single deterministic pass (no FSEvents, no
    /// bookmark) and assert enqueue behaviour — notably that a ledger-recorded group is not
    /// re-enqueued after relaunch.
    func reconcile(rootURL: URL, rediscover: Bool) async {
        guard !disabled, historyIsAvailable() else { return }
        if let currentRoot, currentRoot != rootURL { invalidateLifecycle() }
        currentRoot = rootURL
        invalidateChangedApprovals()
        if rediscover { pendingRefresh = true }
        let lifecycle = lifecycleGeneration
        guard let membership = await refreshMembership(rootURL: rootURL),
              lifecycle == lifecycleGeneration, !disabled else { return }
        let request: UUID?
        var ownsResampling = false
        let events = eventGeneration
        if rediscover {
            guard !isDiscovering else { pendingRefresh = true; return }
            guard retryDeadline.map({ now() >= $0 }) ?? true else { pendingRefresh = true; return }
            guard let slot = discoveryBudget.acquire() else {
                pendingRefresh = true
                status = .discoveryStalled
                return
            }
            request = slot
            discoverySequence += 1
            activeDiscovery = slot
            pendingRefresh = false
            retryDeadline = nil
            isDiscovering = true
        } else {
            guard !isResampling else { return }
            request = nil
            isResampling = true
            ownsResampling = true
        }
        defer {
            if lifecycle == lifecycleGeneration {
                if rediscover, activeDiscovery == request {
                    activeDiscovery = nil
                    isDiscovering = false
                } else if ownsResampling { isResampling = false }
                schedulePendingRefresh(rootURL: rootURL, lifecycle: lifecycle)
            }
        }

        // Metadata and its file-generation stamp travel together. Production stamps each
        // probe before and after I/O; the legacy injected discover closure is an atomic test seam.
        let groups: [RecordGroup]
        if rediscover {
            let previous = Dictionary(uniqueKeysWithValues: lastGroups.flatMap(\.clips).map {
                ($0.videoURL.path, generation(at: $0.videoURL))
            })
            metadataGenerations = metadataGenerations.filter { generation(at: URL(fileURLWithPath: $0.key)) == $0.value }
            reviewRecords.removeAll { record in !record.generations.allSatisfy { generation(at: URL(fileURLWithPath: $0.key)) == $0.value } }
            let result = await withDiscoverTimeout(seconds: settings.discoverTimeout, sleep: timeoutSleep, completed: { [discoveryBudget] in
                discoveryBudget.complete(request!)
            }) { [discover, discoverBound, sample, fileIdentifier] in
                if let discoverBound { return await discoverBound(rootURL) }
                let groups = await discover(rootURL)
                var stamps: [String: WatchFileGeneration] = [:]
                for clip in groups.flatMap(\.clips) {
                    guard let value = sample(clip.videoURL) else { continue }
                    let stamp = WatchFileGeneration(sample: value, identifier: fileIdentifier(clip.videoURL))
                    if let old = previous[clip.videoURL.path], old != stamp { continue }
                    stamps[clip.videoURL.path] = stamp
                }
                return WatchDiscovery(groups: groups, generations: stamps)
            }
            guard lifecycle == lifecycleGeneration, activeDiscovery == request, !disabled else { return }
            if result == nil {
                pendingRefresh = true
                retryDeadline = now().addingTimeInterval(max(0.1, settings.pollInterval))
                status = .discoveryStalled
            }
            // An event while probing makes this result obsolete; the coalesced trailing scan
            // owns fresh metadata. Already-current unaffected cached groups can still settle.
            guard events == eventGeneration else { return }
            invalidateChangedApprovals()
            if let result {
                if status == .discoveryStalled {
                    status = watchFolder == nil ? .idle : .watching(settlingCount: 0)
                }
                let after = await refreshMembership(rootURL: rootURL)
                guard lifecycle == lifecycleGeneration, activeDiscovery == request,
                      events == eventGeneration, !disabled else { return }
                guard let after else {
                    pendingRefresh = true
                    retryDeadline = now().addingTimeInterval(max(0.1, settings.pollInterval))
                    return
                }
                var probedPaths: [String: String] = [:]
                for clip in result.groups.flatMap(\.clips) {
                    probedPaths[Self.membershipPath(clip.videoURL, roots: after.rootPaths)] = clip.videoURL.path
                }
                var confirmed: Membership = [:]
                for group in result.groups {
                    guard let key = membershipKey(group),
                          (membership.buckets[key] ?? []) == (after.buckets[key] ?? []) else { continue }
                    let paths = after.buckets[key] ?? []
                    guard paths.allSatisfy({ path in
                        guard let original = probedPaths[path], let stamp = result.generations[original] else { return false }
                        return generation(at: URL(fileURLWithPath: original)) == stamp
                    }) else { continue }
                    confirmed[key] = paths
                    if membershipGenerations[key] == nil {
                        groupLastChanged[ephemeralKey(group)] = nil
                    }
                }
                membershipGenerations = confirmed
                lastGroups = result.groups
                rejectedProbePaths = result.retryPaths
                rejectedProbeSamples = rejectedProbeSamples.filter { key, _ in result.retryPaths.contains { $0.path == key } }
                metadataGenerations = result.generations.filter {
                    generation(at: URL(fileURLWithPath: $0.key)) == $0.value
                }
            }
            groups = lastGroups
        } else {
            groups = lastGroups
        }
        // Discovery suspends: the destination may have vanished or been reselected meanwhile.
        refreshOutputAvailability()
        for path in rejectedProbePaths {
            if let current = sample(path) {
                var samples = rejectedProbeSamples[path.path] ?? []
                samples.append(current)
                rejectedProbeSamples[path.path] = Array(samples.suffix(sampleHistoryCap))
            } else { rejectedProbeSamples[path.path] = [] }
        }
        let rejectedReady = rejectedProbeSamples.values.contains {
            FileStabilityGate.isSettled(samples: $0, requiredStablePolls: settings.requiredStablePolls)
        }
        guard !groups.isEmpty else {
            if !rediscover && !isDiscovering && rejectedReady {
                isResampling = false
                ownsResampling = false
                await reconcile(rootURL: rootURL, rediscover: true)
            }
            return
        }

        // Step 2: update sample history and last-change timestamps.
        let currentNow = now()
        for group in groups {
            let fp = ephemeralKey(group)
            var groupChanged = false

            for clip in group.clips {
                let key = clip.videoURL.path
                let observed = generation(at: clip.videoURL)
                let newSample = observed?.sample
                if metadataGenerations[key] != observed || observed == nil {
                    for (id, stamps) in approvedGenerations where stamps[key] != nil && stamps[key] != observed {
                        invalidatedApprovals.insert(id)
                    }
                    metadataGenerations[key] = nil
                    reviewRecords.removeAll { $0.generations[key] != nil }
                }

                var history = sampleHistory[key] ?? []
                let lastSample = history.last

                if let newSample {
                    history.append(newSample)
                    // Cap history to avoid unbounded growth.
                    if history.count > sampleHistoryCap {
                        history.removeFirst(history.count - sampleHistoryCap)
                    }
                    sampleHistory[key] = history

                    // A changed sample (or a brand-new clip) means the group changed.
                    if lastSample == nil || lastSample != newSample {
                        groupChanged = true
                    }
                } else {
                    // Missing samples invalidate the old stability streak too.
                    sampleHistory[key] = []
                    groupChanged = true
                }
            }

            if groupChanged || groupLastChanged[fp] == nil {
                groupLastChanged[fp] = currentNow
            }
        }

        // Bound memory across a long daemon session spanning many cards: drop sample history and
        // quiet-window timers for clips/groups no longer present (card ejected, files deleted). These
        // are pure caches — a returning clip simply re-accumulates samples — so eviction is safe and
        // never touches the persisted `groupStates` progress markers. Keys are only pruned once a
        // *discovery* confirms a group is gone (on a poll pass `groups == lastGroups`, so nothing is
        // dropped on a transient read blip).
        let liveClipKeys = Set(groups.flatMap { group in group.clips.map { $0.videoURL.path } })
        let liveGroupKeys = Set(groups.map { ephemeralKey($0) })
        sampleHistory = sampleHistory.filter { liveClipKeys.contains($0.key) }
        groupLastChanged = groupLastChanged.filter { liveGroupKeys.contains($0.key) }

        // Step 3: build observations.
        let observations: [WatchFolderReconciler.GroupObservation] = groups.compactMap { group in
            guard !group.clips.isEmpty else { return nil }

            let clipSamples = group.clips.map { clip -> [FileStabilityGate.Sample] in
                sampleHistory[clip.videoURL.path] ?? []
            }

            // Last segment = the clip with the highest index.
            let lastClip = group.clips.max(by: { $0.index < $1.index })
            let lastSegmentBytes: Int64
            if let lastClip {
                lastSegmentBytes = sampleHistory[lastClip.videoURL.path]?.last?.size ?? 0
            } else {
                lastSegmentBytes = 0
            }

            let fp = ephemeralKey(group)
            let lastChanged = groupLastChanged[fp] ?? currentNow
            let quietElapsed = currentNow.timeIntervalSince(lastChanged)

            // Preceding segments = every clip except the highest-index one, for the GoPro
            // relative reference.
            let precedingSegmentBytes: [Int64] = group.clips
                .filter { $0.id != lastClip?.id }
                .map { sampleHistory[$0.videoURL.path]?.last?.size ?? 0 }

            return WatchFolderReconciler.GroupObservation(
                group: group,
                clipSamples: clipSamples,
                lastSegmentBytes: lastSegmentBytes,
                quietElapsed: quietElapsed,
                precedingSegmentBytes: precedingSegmentBytes
            )
        }

        // Step 4: ask the reconciler which groups are ready.
        let ready = WatchFolderReconciler.groupsToEnqueue(
            observations: observations,
            settings: settings,
            processedFingerprints: []
        )

        // Old group-state hashes describe progress only; they cannot authorize or suppress v2.
        guard historyIsAvailable(), lifecycle == lifecycleGeneration, !disabled else { return }
        var currentReviews: [ReviewRecord] = []
        for group in ready {
            guard historyIsAvailable() else { return }
            guard let key = membershipKey(group), membershipGenerations[key] != nil else { continue }
            guard group.clips.allSatisfy({ clip in
                guard let stamp = metadataGenerations[clip.videoURL.path] else { return false }
                return generation(at: clip.videoURL) == stamp
                    && sampleHistory[clip.videoURL.path]?.last == stamp.sample
            }) else { continue }
            let descriptor = descriptor(for: group, rootURL: rootURL)
            let identity = descriptor.identity
            guard !hasLiveJob(group, identity: identity, rootURL: rootURL) else { continue }
            let decision = ledger.resolution(for: identity)
            if decision == .admitted || decision == .alreadyProcessed { continue }
            let classification = ledger.classify(identity, legacyFingerprint: ProcessedGroupLedger.fingerprint(for: group))
            let reason: String?
            switch classification {
            case .knownV2: continue
            case .newRecording: reason = invalidatedApprovals.contains(identity.ledgerKey) ? "Files changed since the review decision." : nil
            case .legacyAmbiguous: reason = "Earlier history cannot identify this recording."
            case .weak(let reasons): reason = "Weak identity: " + reasons.map(\.rawValue).joined(separator: ", ")
            case .storageUnavailable: status = .historyUnavailable; return
            }
            if let reason, decision != .processOnce || invalidatedApprovals.contains(identity.ledgerKey) {
                let stamps = metadataGenerations.filter { key, _ in group.clips.contains { $0.videoURL.path == key } }
                currentReviews.append(ReviewRecord(descriptor: descriptor, group: group, generations: stamps, reason: reason))
                continue
            }
            guard let destURL = destinationURL(for: group, rootURL: rootURL) else {
                status = .outputUnavailable
                continue
            }
            var job = ConversionJob.withBookmarks(folderName: rootURL.lastPathComponent,
                sourceFolderURL: rootURL, clips: group.clips, settings: ConversionSettings(), destinationURL: destURL)
            job.watchIdentitySnapshot = WatchIdentitySnapshot(watchEntryID: watchEntryID,
                ledgerNamespace: ledgerNamespace, descriptor: descriptor)
            job.watchAdmissionPending = true
            // addJob saves the pending marker before recovery is permitted to commit history.
            queue.addJob(job)
            if queue.recoverWatchAdmission(job.id, commit: { try commitAdmission($0) }) {
                queue.startQueue(automatic: true)
            } else {
                status = .historyUnavailable
            }
            sessionEnqueuedCount += 1
        }
        reviewRecords = currentReviews
        if queue.jobs.contains(where: { $0.watchIdentitySnapshot?.watchEntryID == watchEntryID
            && $0.watchAdmissionPending == true && $0.status == .pending }) {
            status = .historyUnavailable
            return
        }

        if !rediscover && !isDiscovering && (rejectedReady || groups.contains(where: {
            guard let key = membershipKey($0) else { return false }
            return membershipGenerations[key] == nil
        }) || groups.flatMap(\.clips).contains(where: {
            metadataGenerations[$0.videoURL.path] == nil && FileStabilityGate.isSettled(
                samples: sampleHistory[$0.videoURL.path] ?? [], requiredStablePolls: settings.requiredStablePolls)
        })) {
            isResampling = false
            ownsResampling = false
            await reconcile(rootURL: rootURL, rediscover: true)
            return
        }
        // Step 6: update published status.
        let settlingCount = observations.filter { obs in
            let fp = ProcessedGroupLedger.fingerprint(for: obs.group)
            let state = groupStates[fp]
            return state == nil || state == .discovered || state == .settling || state == .grouped
        }.count

        if pendingRefresh && retryDeadline != nil || !discoveryBudget.hasCapacity && !isDiscovering {
            status = .discoveryStalled
        } else if currentOutputDestination() == .unavailable {
            status = .outputUnavailable
        } else if sessionEnqueuedCount > 0 {
            status = .queued(count: sessionEnqueuedCount)
        } else if watchFolder != nil {
            status = .watching(settlingCount: settlingCount)
        } else {
            status = .idle
        }
    }

    // MARK: - Private: Helpers

    private func membershipKey(_ group: RecordGroup) -> MembershipKey? {
        guard let clip = group.clips.first else { return nil }
        return MembershipKey(family: clip.family.rawValue, variant: clip.variantSuffix,
                             recording: clip.recordingNumber)
    }

    /// Match discovery's bounded card-shaped descent and parser without launching any probes.
    /// DJI indices cannot identify recordings; until metadata is available, conservatively hold
    /// its variant bucket. Other variants/families/GoPro recording numbers continue settling.
    nonisolated private static func readMembershipFiles(rootURL: URL) -> [URL]? {
        do {
            return try DJIFolderReader.resolveMediaFolders(startingAt: rootURL).flatMap { directory in
                try FileManager.default.contentsOfDirectory(at: directory,
                    includingPropertiesForKeys: nil, options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants])
                    .filter { DJIFilenameParser.parse($0)?.mediaKind == .video }
            }
        } catch { return nil }
    }

    /// Directory reads can stall on a disconnected mount too. Share discovery's actual-worker
    /// budget and timeout semantics; concurrent polls/events await one owned census task.
    private func refreshMembership(rootURL: URL) async -> MembershipSnapshot? {
        guard !disabled else { return nil }
        let lifecycle = lifecycleGeneration
        let events = eventGeneration
        let owned: (id: UUID, events: Int, task: Task<MembershipSnapshot?, Never>)
        if let membershipTask {
            owned = membershipTask
        } else {
            guard let slot = discoveryBudget.acquire() else {
                invalidateMembership(using: nil)
                status = .discoveryStalled
                return nil
            }
            let timeout = settings.discoverTimeout
            let task = Task { [membershipReader, membershipTimeoutSleep, discoveryBudget] in
                let result = await withDiscoverTimeout(seconds: timeout, sleep: membershipTimeoutSleep,
                    completed: { discoveryBudget.complete(slot) }) {
                        guard let paths = await membershipReader(rootURL) else { return nil as MembershipSnapshot? }
                        // Resolve aliases inside the bounded worker too; no new filesystem work
                        // runs on MainActor. Membership keys remain relative to this watch root.
                        let canonicalRoot = rootURL.resolvingSymlinksInPath().path
                        var roots = [rootURL.path, canonicalRoot]
                        var census: Membership = [:]
                        for url in paths {
                            guard let parsed = DJIFilenameParser.parse(url), parsed.mediaKind == .video else { continue }
                            let key = MembershipKey(family: parsed.family.rawValue, variant: parsed.variantSuffix,
                                                    recording: parsed.recordingNumber)
                            let path = Self.membershipPath(url.resolvingSymlinksInPath(), roots: [canonicalRoot])
                            // Foundation enumeration may return /var even when the selected root
                            // uses /private/var. Retain the observed alias for reader clip paths.
                            if !path.hasPrefix("/"), url.path.hasSuffix(path) {
                                let prefix = String(url.path.dropLast(path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                                let alias = "/" + prefix
                                if !roots.contains(alias) { roots.append(alias) }
                            }
                            census[key, default: []].insert(path)
                        }
                        return MembershipSnapshot(buckets: census, rootPaths: roots)
                    }
                return result ?? nil
            }
            owned = (slot, events, task)
            membershipTask = owned
            membershipRequestID = owned.id
        }
        let result = await owned.task.value
        guard lifecycle == lifecycleGeneration, membershipRequestID == owned.id, !disabled else { return nil }
        if membershipTask?.id == owned.id { membershipTask = nil }
        guard owned.events == eventGeneration else { return nil }
        invalidateMembership(using: result?.buckets)
        if result == nil { status = .discoveryStalled }
        return result
    }

    nonisolated private static func membershipPath(_ url: URL, roots: [String]) -> String {
        let path = url.path
        for root in roots {
            let prefix = root.hasSuffix("/") ? root : root + "/"
            if path.hasPrefix(prefix) { return String(path.dropFirst(prefix.count)) }
        }
        return path
    }

    private func invalidateMembership(using current: Membership?) {
        let invalid = Set(membershipGenerations.keys.filter { key in
            guard let current else { return true }
            return membershipGenerations[key] != (current[key] ?? [])
        })
        guard !invalid.isEmpty else { return }
        for group in lastGroups {
            guard let key = membershipKey(group), invalid.contains(key) else { continue }
            groupLastChanged[ephemeralKey(group)] = nil
            let paths = Set(group.clips.map { $0.videoURL.path })
            for (id, stamps) in approvedGenerations where !paths.isDisjoint(with: stamps.keys) {
                invalidatedApprovals.insert(id)
            }
        }
        reviewRecords.removeAll { record in
            membershipKey(record.group).map { invalid.contains($0) } ?? true
        }
        for key in invalid { membershipGenerations[key] = nil }
    }

    private func ephemeralKey(_ group: RecordGroup) -> String {
        // Length-prefixed paths make grouping/sampling independent of legacy and durable hashes.
        group.clips.map { "\($0.videoURL.path.utf8.count):\($0.videoURL.path)" }.joined()
    }

    private func descriptor(for group: RecordGroup, rootURL: URL) -> WatchRecordingDescriptor {
        let prefix = rootURL.standardizedFileURL.path + "/"
        return WatchRecordingDescriptor(clips: group.clips.map { clip in
            let path = clip.videoURL.standardizedFileURL.path
            return .init(cameraFamily: clip.family.rawValue, stem: clip.stem, index: clip.index,
                variant: clip.variantSuffix, recordingNumber: clip.recordingNumber,
                captureDate: clip.creationDate, duration: clip.duration,
                relativePath: path.hasPrefix(prefix) ? String(path.dropFirst(prefix.count)) : "../" + path,
                settledVideoBytes: sampleHistory[clip.videoURL.path]?.last?.size)
        })
    }

    private func hasLiveJob(_ group: RecordGroup, identity: WatchRecordingIdentity, rootURL: URL) -> Bool {
        queue.jobs.contains { job in
            guard job.status != .completed, job.status != .cancelled || job.watchAdmissionPending == true else { return false }
            if let snapshot = job.watchIdentitySnapshot {
                // Identity is root-relative, so the source root must match for another namespace.
                return snapshot.identity == identity && (snapshot.watchEntryID == watchEntryID
                    || job.sourceFolderURL.standardizedFileURL == rootURL.standardizedFileURL)
            }
            // Old/manual jobs lack an observed descriptor: never stat replacement media to
            // reconstruct one. Conservative source/clip overlap protects their captured footage.
            return job.clips.contains { old in group.clips.contains {
                old.videoURL.standardizedFileURL == $0.videoURL.standardizedFileURL
            } }
        }
    }

    // MARK: - Private: Destination URL

    /// Builds the output file URL for a group, named after the first segment's stem with `_joined`
    /// appended. Lands in the resolved output when the user chose a dedicated destination,
    /// otherwise next to the source inside `rootURL` (the v1 default).
    ///
    /// `QueueManager.addJob` calls `resolveFilenameConflict` internally to handle on-disk
    /// collisions, so we don't duplicate that logic here.
    private func destinationURL(for group: RecordGroup, rootURL: URL) -> URL? {
        let stem = group.clips.first?.stem ?? "joined"
        let suffix = group.variantSuffix.map { "_\($0)" } ?? ""
        let filename = "\(stem)\(suffix)_joined.mp4"
        let directory: URL
        switch currentOutputDestination() {
        case .unconfigured: directory = rootURL
        case .resolved(let url): directory = url
        case .unavailable: return nil
        }
        return directory.appendingPathComponent(filename)
    }

    // MARK: - Private: Group state persistence

    /// Loads `watch_group_states.json` from `url`. Returns an empty dict on any error.
    private static func loadGroupStates(from url: URL?) -> [String: WatchGroupState] {
        guard let url,
              FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: WatchGroupState].self, from: data)
        else { return [:] }
        return decoded
    }

    /// Persists `groupStates` to `watch_group_states.json`. Non-fatal: disk errors are silently
    /// dropped so a transient I/O failure doesn't crash the coordinator.
    private func saveGroupStates() {
        guard let url = groupStatesURL else { return }
        do {
            let data = try JSONEncoder().encode(groupStates)
            try data.write(to: url, options: .atomic)
        } catch {
            #if DEBUG
            print("[WatchFolderCoordinator] saveGroupStates failed: \(error)")
            #endif
        }
    }
}

// MARK: - Bounded discovery

/// Single-resume gate shared by the work task and the timeout task in `withDiscoverTimeout`. An
/// `actor` guarantees the "resume the continuation exactly once" invariant without a manual lock:
/// whichever task calls `claim()` first gets `true`; every later caller gets `false`.
private actor ResumeGate {
    private var claimed = false
    func claim() -> Bool {
        if claimed { return false }
        claimed = true
        return true
    }
}

/// Runs `operation`, returning its result, or `nil` if `seconds` elapse first.
///
/// Unlike a `withTaskGroup` race, the operation task is **not awaited** on the timeout path — it's
/// abandoned. This is deliberate: the thing we bound (an ffprobe `Process` inside `discover`) can
/// ignore cooperative cancellation and stay wedged on a stalled mount, and awaiting it would just
/// re-introduce the deadlock we're escaping. The orphaned task lingers until it eventually unblocks
/// (or the app quits). Its manager-owned budget slot is held until actual completion; no caller
/// can create more than two underlying workers for this root in the session.
/// Defined at file scope (not on the `@MainActor` coordinator) so its racing tasks run off the main
/// actor and don't stall the UI while a scan is in flight.
private func withDiscoverTimeout<T: Sendable>(
    seconds: TimeInterval,
    sleep: @escaping @Sendable (TimeInterval) async -> Void,
    completed: @escaping @MainActor @Sendable () -> Void,
    _ operation: @escaping @Sendable () async -> T
) async -> T? {
    let gate = ResumeGate()
    return await withCheckedContinuation { (continuation: CheckedContinuation<T?, Never>) in
        let timeoutTask = Task {
            await sleep(seconds)
            if await gate.claim() { continuation.resume(returning: nil) }
        }
        Task {
            let result = await operation()
            await completed()
            // Work won the race: stop the timer so a fast scan doesn't leave a sleeping task behind.
            if await gate.claim() {
                timeoutTask.cancel()
                continuation.resume(returning: result)
            }
        }
    }
}

/// Counts actual underlying workers, not timeout waiters. Never release on cancellation,
/// timeout or coordinator removal: an uncooperative reader may still own a process/mount.
@MainActor
final class WatchDiscoveryBudget {
    private var workers: Set<UUID> = []
    var hasCapacity: Bool { workers.count < 2 }
    var workerCount: Int { workers.count }
    func acquire() -> UUID? {
        guard hasCapacity else { return nil }
        let id = UUID()
        workers.insert(id)
        return id
    }
    func complete(_ id: UUID) { workers.remove(id) }
}
