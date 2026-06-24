import XCTest
@testable import Conjoyn

// MARK: - WatchFolder lifecycle / FSEvents context retain-balance tests

/// `WatchFolder` wraps an `FSEventStreamRef` and (after the teardown-UAF hardening) gives the stream
/// real `retain`/`release` context callbacks so the stream holds its own strong reference to the
/// monitor while it can deliver callbacks. That introduces an intentional stream↔monitor cycle that
/// an explicit `stop()` must break (via `FSEventStreamRelease` → the `release` callback).
///
/// A use-after-free needs a real callback/teardown race to reproduce, which is too flaky to assert
/// deterministically. What we *can* pin down is the **retain/release balance**: an over-retain would
/// leak the monitor; a missing/extra release would leak or crash. These tests prove the object's
/// lifetime is exactly right around start/stop — the property the new callbacks are responsible for.
final class WatchFolderTests: XCTestCase {

    private func freshTmpDir() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("WatchFolderTests-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// `FSEventStreamRelease` runs the context `release` callback asynchronously on the stream's
    /// dispatch queue (it keeps `self` alive until the queue has drained — exactly the UAF guard we
    /// want), so the final dealloc can land a beat after `stop()` returns. Spin briefly until the weak
    /// reference clears, so the assertion tests "deallocs eventually" rather than "deallocs this tick".
    private func waitForDealloc(_ ref: () -> AnyObject?, timeout: TimeInterval = 2.0) {
        let deadline = Date().addingTimeInterval(timeout)
        while ref() != nil && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    /// An unstarted monitor never created a stream, so there's no stream-held retain — it must
    /// dealloc as soon as the last ordinary reference drops.
    func testUnstartedMonitorDeallocs() {
        let dir = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        weak var weakRef: WatchFolder?
        autoreleasepool {
            let wf = WatchFolder(url: dir, latency: 0.1) { }
            weakRef = wf
            XCTAssertNotNil(weakRef)
        }
        XCTAssertNil(weakRef, "an unstarted monitor holds no stream retain and must dealloc normally")
    }

    /// After `start()` the stream retains the monitor; `stop()` must release that retain so the
    /// monitor deallocs once the last ordinary reference drops. A leak here means the new
    /// `release` callback didn't fire (or `retain` over-counted).
    func testStartedMonitorDeallocsAfterExplicitStop() {
        let dir = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        weak var weakRef: WatchFolder?
        autoreleasepool {
            let wf = WatchFolder(url: dir, latency: 0.1) { }
            weakRef = wf
            wf.start()
            wf.stop()   // FSEventStreamRelease → release callback balances the create-time retain
        }
        waitForDealloc { weakRef }
        XCTAssertNil(weakRef, "explicit stop() must balance the stream's retain so the monitor deallocs")
    }

    /// `start()` / `stop()` are documented idempotent. Double-calling must not crash (double-release)
    /// or wedge, and the monitor must still dealloc cleanly afterwards.
    func testStartStopAreIdempotent() {
        let dir = freshTmpDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        weak var weakRef: WatchFolder?
        autoreleasepool {
            let wf = WatchFolder(url: dir, latency: 0.1) { }
            weakRef = wf
            wf.start()
            wf.start()   // no-op
            wf.stop()
            wf.stop()    // no-op, must not double-release
        }
        waitForDealloc { weakRef }
        XCTAssertNil(weakRef, "idempotent start/stop must leave the monitor deallocatable")
    }
}
