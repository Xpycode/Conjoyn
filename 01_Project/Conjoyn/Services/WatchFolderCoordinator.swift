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
        /// Monitor is active; N groups have been observed but have not yet settled / completed.
        case watching(settlingCount: Int)
        /// Groups have been enqueued into `QueueManager`.
        case queued(count: Int)
    }

    @Published private(set) var status: Status = .idle

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

    /// Guards against overlapping rescans: FSEvents and the poll timer can fire concurrently
    /// (one from the GCD queue hop, one from the RunLoop). A second rescan that arrives while
    /// one is in flight is silently dropped — the trailing FSEvents event will trigger another.
    private var isRescanning = false

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
            storageDirectory: storageDirectory
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
        storageDirectory: URL? = nil
    ) {
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
    }

    // MARK: - Enable / Disable

    /// Activates the watch-folder for `rootURL`: persists the bookmark, marks settings enabled,
    /// starts FSEvents monitoring, and kicks an immediate rescan.
    func enable(rootURL: URL) {
        do {
            try bookmark.save(url: rootURL)
        } catch {
            #if DEBUG
            print("[WatchFolderCoordinator] bookmark save failed: \(error)")
            #endif
        }

        settings.enabled = true
        settings.save()

        startMonitor(rootURL: rootURL)
        Task { @MainActor [weak self] in
            await self?.rescan(rediscover: true)
        }
    }

    /// Deactivates the watch-folder: stops FSEvents monitoring, cancels the poll timer, and
    /// persists the disabled state. No in-flight job is touched — the queue runs to completion.
    func disable() {
        settings.enabled = false
        settings.save()
        stopMonitor()
        status = .idle
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

        // Build the set of fingerprints already represented by live (unfinished) queue jobs.
        let liveQueueFingerprints = liveJobFingerprints()

        // Restore persisted group states that are still in-flight (not terminal) and check
        // whether they need re-enqueueing. A group in the ledger is done; a group in the live
        // queue is already being handled; only "neither" groups need action.
        var fingerprintsToReenqueue: [String] = []
        for (fp, state) in groupStates where !state.isTerminal {
            if WatchFolderReconciler.shouldReenqueue(
                fingerprint: fp,
                processedFingerprints: processedFingerprints(),
                liveQueueFingerprints: liveQueueFingerprints
            ) {
                fingerprintsToReenqueue.append(fp)
            }
        }

        // Re-enqueue is handled implicitly by the next `rescan()` pass: the reconciler will
        // see the groups are settled/complete/fresh and enqueue them. We just need to ensure
        // monitoring is running so that pass happens.
        startMonitor(rootURL: rootURL)
        Task { @MainActor [weak self] in
            await self?.rescan(rediscover: true)
        }

        #if DEBUG
        if !fingerprintsToReenqueue.isEmpty {
            print("[WatchFolderCoordinator] resume: \(fingerprintsToReenqueue.count) group(s) may need re-enqueue after rescan")
        }
        #endif
    }

    // MARK: - Private: Monitor lifecycle

    private func startMonitor(rootURL: URL) {
        stopMonitor() // idempotent teardown of any previous monitor

        let wf = WatchFolder(url: rootURL, latency: 1.0) { [weak self] in
            // WatchFolder's onChange callback is @Sendable (GCD queue). Hop to MainActor.
            // A real filesystem change → re-discover (a new/changed segment may exist).
            Task { @MainActor [weak self] in
                await self?.rescan(rediscover: true)
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
                await self?.rescan(rediscover: false)
            }
        }

        status = .watching(settlingCount: 0)
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
        await reconcile(rootURL: rootURL, rediscover: rediscover)
    }

    /// One reconciliation pass against an explicit root. `rescan` resolves the bookmark and calls
    /// this; production fires it from FSEvents / the poll timer. **Test seam:** the suite calls it
    /// directly with a temp root so it can `await` a single deterministic pass (no FSEvents, no
    /// bookmark) and assert enqueue behaviour — notably that a ledger-recorded group is not
    /// re-enqueued after relaunch.
    func reconcile(rootURL: URL, rediscover: Bool) async {
        guard !isRescanning else { return }
        isRescanning = true
        defer { isRescanning = false }

        // Step 1: obtain current groups — fresh discovery on change, else reuse the last set.
        let groups: [RecordGroup]
        if rediscover {
            groups = await discover(rootURL)
            lastGroups = groups
        } else {
            groups = lastGroups
        }
        guard !groups.isEmpty else { return }

        // Step 2: update sample history and last-change timestamps.
        let currentNow = now()
        for group in groups {
            let fp = ProcessedGroupLedger.fingerprint(for: group)
            var groupChanged = false

            for clip in group.clips {
                let key = clip.videoURL.path
                let newSample = sample(clip.videoURL)

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
                    // File inaccessible this poll — mark the group changed to reset quiet window.
                    groupChanged = true
                }
            }

            if groupChanged || groupLastChanged[fp] == nil {
                groupLastChanged[fp] = currentNow
            }
        }

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

            let fp = ProcessedGroupLedger.fingerprint(for: group)
            let lastChanged = groupLastChanged[fp] ?? currentNow
            let quietElapsed = currentNow.timeIntervalSince(lastChanged)

            return WatchFolderReconciler.GroupObservation(
                group: group,
                clipSamples: clipSamples,
                lastSegmentBytes: lastSegmentBytes,
                quietElapsed: quietElapsed
            )
        }

        // Step 4: ask the reconciler which groups are ready.
        let ready = WatchFolderReconciler.groupsToEnqueue(
            observations: observations,
            settings: settings,
            processedFingerprints: processedFingerprints()
        )

        // Step 5: enqueue ready groups.
        for group in ready {
            let destURL = destinationURL(for: group, rootURL: rootURL)
            queue.addJob(
                folderName: rootURL.lastPathComponent,
                sourceFolderURL: rootURL,
                clips: group.clips,
                settings: ConversionSettings(),
                destinationURL: destURL
            )
            queue.startQueue()

            // Seal the group in the ledger (persisted) so it's never re-enqueued — this session
            // or after relaunch.
            ledger.insert(group)

            // Advance the group's state machine toward .joining.
            let fp = ProcessedGroupLedger.fingerprint(for: group)
            let current = groupStates[fp] ?? .discovered
            groupStates[fp] = current.transition(to: .joining) ?? current
            sessionEnqueuedCount += 1
        }

        // Persist group states after any mutation.
        if !ready.isEmpty {
            saveGroupStates()
        }

        // Step 6: update published status.
        let settlingCount = observations.filter { obs in
            let fp = ProcessedGroupLedger.fingerprint(for: obs.group)
            let state = groupStates[fp]
            return state == nil || state == .discovered || state == .settling || state == .grouped
        }.count

        if sessionEnqueuedCount > 0 {
            status = .queued(count: sessionEnqueuedCount)
        } else if watchFolder != nil {
            status = .watching(settlingCount: settlingCount)
        } else {
            status = .idle
        }
    }

    // MARK: - Private: Helpers

    /// Returns the set of SHA-256 fingerprints for groups already durably processed.
    ///
    /// Reads straight from the ledger, which loads the persisted set at `init` and keeps it in
    /// memory — so this is O(1) AND correct across relaunch. (An earlier draft mirrored insertions
    /// in a separate set that started empty at launch; that re-introduced the re-join-forever bug
    /// because a previously-joined group whose source clips still sit on the card read as "fresh".)
    private func processedFingerprints() -> Set<String> {
        ledger.allFingerprints
    }

    // MARK: - Private: Destination URL

    /// Builds the output file URL for a group. Output lands next to the source (in `rootURL`),
    /// named after the first segment's stem with `_joined` appended.
    ///
    /// `QueueManager.addJob` calls `resolveFilenameConflict` internally to handle on-disk
    /// collisions, so we don't duplicate that logic here.
    ///
    /// TODO(5D): let the user choose a dedicated output folder in the watch-folder settings UI.
    private func destinationURL(for group: RecordGroup, rootURL: URL) -> URL {
        let stem = group.clips.first?.stem ?? "joined"
        let suffix = group.variantSuffix.map { "_\($0)" } ?? ""
        let filename = "\(stem)\(suffix)_joined.mp4"
        return rootURL.appendingPathComponent(filename)
    }

    // MARK: - Private: Live queue fingerprints

    /// Computes the set of stable fingerprints for queue jobs that have NOT yet finished.
    /// A transient `RecordGroup` is built from each job's clips so `ProcessedGroupLedger.fingerprint`
    /// can produce the same hash the reconciler uses. Only unfinished jobs are included — a
    /// completed job's fingerprint is already in the ledger.
    private func liveJobFingerprints() -> Set<String> {
        var fps = Set<String>()
        for job in queue.jobs where !job.status.isFinished {
            let transientGroup = RecordGroup(clips: job.clips, groupIndex: 0)
            fps.insert(ProcessedGroupLedger.fingerprint(for: transientGroup))
        }
        return fps
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
