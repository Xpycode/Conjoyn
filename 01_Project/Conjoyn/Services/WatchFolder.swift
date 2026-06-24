import CoreServices
import Foundation

// MARK: - Watch Folder (Wave 5B, task 5.6)

/// Recursive FSEvents monitor over a watched root directory.
///
/// `WatchFolder` wraps a single `FSEventStreamRef` and delivers a coalesced "something changed"
/// signal to a caller-supplied callback. Its job is narrow: turn low-level C callbacks into a
/// clean Swift closure. Grouping, stability gating, and enqueueing are the consumer's concern.
///
/// ## Callback contract — "rescan" not "what changed"
/// FSEvents only reports *that* a path under the watched root changed, not *which* files or *how*.
/// The callback therefore carries **no arguments** — it means "rescan the root now". Callers must
/// re-read the directory tree on every invocation rather than trying to track deltas.
///
/// ## Coalescing / latency
/// **`latency` IS the debounce.** FSEvents accumulates all events that arrive within `latency`
/// seconds into a single batch, then fires the stream callback exactly once. Adding a second
/// Swift-side debounce timer on top of this would only delay delivery without buying any extra
/// coalescing — resist the temptation. The default of 1.0 s is comfortable for SD-card ingest
/// where dozens of segment files land in a short burst; tighten to ~0.25 s for local-copy targets.
///
/// ## Thread safety (`@unchecked Sendable`)
/// `WatchFolder` is marked `@unchecked Sendable` because it wraps an opaque C pointer
/// (`FSEventStreamRef`) that Swift's type system cannot reason about. The invariant that makes
/// this safe:
///   - `streamRef` and `started` are mutated **only** from `start()` and `stop()`, which the
///     *owner* is expected to call from a stable context (typically the main actor or a single
///     queue).
///   - The C stream callback fires on `dispatchQueue` (our private GCD queue). It reads `self`
///     through the context `info` pointer and immediately calls `onChange`, which is `@Sendable`
///     and must itself be concurrency-safe. The callback never mutates `streamRef` or `started`.
///   - The stream is given real `retain`/`release` context callbacks, so **the stream itself holds
///     a strong reference** to this object for its entire lifetime. That closes a teardown
///     use-after-free: `stop()`/`deinit` run on the owner's actor while a callback may still be
///     in flight on `dispatchQueue`; the stream's own retain keeps `self` alive until
///     `FSEventStreamRelease` (after `Invalidate`, when no further callbacks can fire) balances it.
///   - **Ownership contract:** because the running stream holds its own retain on `self`, the owner
///     **must call `stop()`** to break that stream↔self cycle before dropping the monitor (the
///     `WatchFolderCoordinator` does, via `stopMonitor()` on every disable/re-monitor). While a
///     started stream is alive, `deinit` will *not* fire on its own — its retain keeps `self` up. The
///     `deinit { stop() }` below is therefore a fallback for the unstarted / already-stopped case
///     (where no stream retain exists), not the primary teardown path.
final class WatchFolder: @unchecked Sendable {

    // MARK: - Public API

    /// Root directory to watch recursively.
    let url: URL

    /// FSEvents batching window (seconds). One callback fires per batch regardless of how many
    /// filesystem events landed inside the window. Tune per caller; 1.0 s suits SD-card ingest.
    let latency: TimeInterval

    /// Called once per coalesced FSEvents batch. Runs on `dispatchQueue`. Must be `@Sendable`
    /// because it crosses actor/task boundaries — capture only `Sendable` state inside.
    private let onChange: @Sendable () -> Void

    // MARK: - Private State

    /// The live FSEvents stream, or `nil` when stopped.
    private var streamRef: FSEventStreamRef?

    /// Guards against double-start / double-stop.
    private var started = false

    /// Private serial queue on which FSEvents delivers callbacks. Using a dedicated queue (rather
    /// than the main run loop) keeps the stream alive even when the main loop is blocked and avoids
    /// adding latency to UI work.
    private let dispatchQueue: DispatchQueue

    // MARK: - Init

    /// - Parameters:
    ///   - url:      Root directory to monitor recursively.
    ///   - latency:  FSEvents coalescing window in seconds (default 1.0 s).
    ///   - onChange: Zero-argument closure called once per coalesced event batch.
    ///               Runs on an internal GCD queue; must be `@Sendable`.
    init(url: URL, latency: TimeInterval = 1.0, onChange: @escaping @Sendable () -> Void) {
        self.url = url
        self.latency = latency
        self.onChange = onChange
        self.dispatchQueue = DispatchQueue(
            label: "com.lucesumbrarum.conjoyn.watchfolder",
            qos: .utility
        )
    }

    // MARK: - Lifecycle

    /// Creates, schedules, and starts the FSEvents stream.
    ///
    /// Idempotent: calling `start()` on an already-running monitor is a no-op.
    ///
    /// Lifecycle order (FSEvents requirement):
    ///   1. `FSEventStreamCreate` — allocate the stream.
    ///   2. `FSEventStreamSetDispatchQueue` — attach to a GCD queue.
    ///   3. `FSEventStreamStart` — begin event delivery.
    func start() {
        guard !started else { return }

        // Pass `self` through the context info pointer, with real `retain`/`release` callbacks so the
        // **stream takes its own strong reference** to this object. FSEvents calls `retain` once when
        // the stream is created and `release` once at `FSEventStreamRelease` (step 3 of `stop()`,
        // after `Invalidate` guarantees no further callbacks). That retain is what keeps `self` alive
        // if the owner releases it (e.g. `stopMonitor()` swaps in a new monitor, or the coordinator
        // deallocs) while a callback is still in flight on `dispatchQueue` — closing the teardown UAF.
        // The callback still uses `takeUnretainedValue()`: it does not consume the stream's retain.
        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: watchFolderContextRetain,
            release: watchFolderContextRelease,
            copyDescription: nil
        )

        // C callback: cannot capture Swift context, so recovers `self` via the info pointer.
        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            // Guard against a nil info pointer (defensive — FSEvents always passes one when
            // context.info is non-nil, but the API signature is UnsafeMutableRawPointer?).
            guard let info else { return }
            let monitor = Unmanaged<WatchFolder>.fromOpaque(info).takeUnretainedValue()
            // One invocation per coalesced batch — call onChange exactly once.
            monitor.onChange()
        }

        let paths = [url.path as CFString] as CFArray

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths,
            // We only care about future changes; skip replaying the changelog since boot.
            UInt64(kFSEventStreamEventIdSinceNow),
            latency,
            // kFSEventStreamCreateFlagFileEvents  — file-granularity events (not just dir).
            // kFSEventStreamCreateFlagUseCFTypes  — paths delivered as CFArray of CFString.
            // kFSEventStreamCreateFlagNoDefer     — don't hold back the first event in a batch;
            //                                       fire as soon as latency elapses rather than
            //                                       waiting for a second event to arrive.
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
            )
        ) else {
            // FSEventStreamCreate should never fail for a valid path; log and bail gracefully.
            #if DEBUG
            print("[WatchFolder] FSEventStreamCreate failed for \(url.path)")
            #endif
            return
        }

        // Step 2: attach to our GCD queue (must precede Start).
        FSEventStreamSetDispatchQueue(stream, dispatchQueue)

        // Step 3: begin delivery.
        FSEventStreamStart(stream)

        streamRef = stream
        started = true
    }

    /// Stops, invalidates, and releases the FSEvents stream.
    ///
    /// Idempotent: safe to call on an already-stopped monitor, and called automatically on `deinit`.
    ///
    /// Teardown order (FSEvents requirement):
    ///   1. `FSEventStreamStop`     — halt event delivery.
    ///   2. `FSEventStreamInvalidate` — detach from its queue/run loop.
    ///   3. `FSEventStreamRelease`  — free the stream object.
    func stop() {
        guard started, let stream = streamRef else { return }

        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)

        streamRef = nil
        started = false
    }

    // MARK: - Deinit

    deinit {
        stop()
    }
}

// MARK: - FSEvents context retain/release

// C function pointers for `FSEventStreamContext`. They can't capture Swift state, so they live at
// file scope and round-trip the `info` pointer through `Unmanaged`. Together they give the stream a
// balanced strong reference to the `WatchFolder` for its whole lifetime (see `start()`).

/// Retains the `WatchFolder` behind the context `info` pointer. FSEvents calls this when the stream
/// is created; balanced by `watchFolderContextRelease` at `FSEventStreamRelease`.
private let watchFolderContextRetain: CFAllocatorRetainCallBack = { info in
    guard let info else { return nil }
    return UnsafeRawPointer(Unmanaged<WatchFolder>.fromOpaque(info).retain().toOpaque())
}

/// Releases the `WatchFolder` retained by `watchFolderContextRetain`. FSEvents calls this when the
/// stream is released, after `Invalidate` has guaranteed no further callbacks can fire.
private let watchFolderContextRelease: CFAllocatorReleaseCallBack = { info in
    guard let info else { return }
    Unmanaged<WatchFolder>.fromOpaque(info).release()
}
