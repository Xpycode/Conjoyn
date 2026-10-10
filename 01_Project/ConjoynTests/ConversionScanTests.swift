import XCTest
import CoreMedia
import Combine
@testable import Conjoyn

/// Drives the same synchronous entry points as the picker/drop and Rescan button. The reader
/// deliberately ignores cancellation, so only request ownership can make these tests pass.
@MainActor
final class ConversionScanTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: directory)
    }

    private func group(_ name: String) -> RecordGroup {
        RecordGroup(clips: [DJIClip(videoURL: directory.appendingPathComponent(name + ".MP4"),
                                    index: 1, stem: name,
                                    duration: CMTime(seconds: 1, preferredTimescale: 600))],
                    groupIndex: 1)
    }

    private func discovery(_ groups: [RecordGroup], skipped: [String] = [],
                           errors: [ClipParseError] = []) -> DJIFolderReader.Discovery {
        .init(groups: groups, errors: errors, skippedNonDJI: skipped)
    }

    private func overlap(latestFinishesFirst: Bool, sameSource: Bool) async {
        let reader = ScanGate<URL, DJIFolderReader.Discovery>()
        let vm = ConversionViewModel(queue: QueueManager(storageDirectory: directory),
                                     discover: { await reader.call($0) },
                                     warmDates: { _, _ in [:] })
        let a = vm.setSourceFolder(directory.appendingPathComponent("A"))
        let first = await reader.next()
        let b: Task<Void, Never>
        if sameSource {
            b = vm.scan()!
        } else {
            b = vm.setSourceFolder(directory.appendingPathComponent("B"))
        }
        let second = await reader.next()
        XCTAssertEqual(first.input.lastPathComponent, "A")
        XCTAssertEqual(second.input.lastPathComponent, sameSource ? "A" : "B")
        let newest = group("new")
        let staleError = ClipParseError(file: directory.appendingPathComponent("bad.MP4"), message: "stale")
        if latestFinishesFirst {
            await reader.finish(second.id, with: discovery([newest]))
            await b.value
            let status = vm.statusMessage
            await reader.finish(first.id, with: discovery([], skipped: ["stale.mov"], errors: [staleError]))
            await a.value
            XCTAssertEqual(vm.statusMessage, status)
        } else {
            await reader.finish(first.id, with: discovery([group("old")], skipped: ["stale.mov"], errors: [staleError]))
            await a.value
            XCTAssertTrue(vm.isScanning)
            XCTAssertTrue(vm.groups.isEmpty)
            XCTAssertTrue(vm.selectedGroupIDs.isEmpty)
            XCTAssertTrue(vm.skippedFiles.isEmpty)
            XCTAssertTrue(vm.parseErrors.isEmpty)
            XCTAssertTrue(vm.statusMessage?.hasPrefix("Scanning") == true)
            await reader.finish(second.id, with: discovery([newest]))
            await b.value
        }
        XCTAssertEqual(vm.groups.map(\.id), [newest.id])
        XCTAssertEqual(vm.selectedGroupIDs, [newest.id])
        XCTAssertTrue(vm.skippedFiles.isEmpty)
        XCTAssertTrue(vm.parseErrors.isEmpty)
        XCTAssertFalse(vm.isScanning)
    }

    func testLatestRequestWinsBothCompletionOrders() async {
        await overlap(latestFinishesFirst: true, sameSource: false)
        await overlap(latestFinishesFirst: false, sameSource: false)
    }

    func testSameURLRescanStillInvalidatesPreviousRequest() async {
        await overlap(latestFinishesFirst: true, sameSource: true)
        await overlap(latestFinishesFirst: false, sameSource: true)
    }

    func testSourceSwitchSynchronouslyPreventsEnqueueAndResetsDisplayState() async {
        let reader = ScanGate<URL, DJIFolderReader.Discovery>()
        let queue = QueueManager(storageDirectory: directory)
        let vm = ConversionViewModel(queue: queue, discover: { await reader.call($0) },
                                     warmDates: { _, _ in [:] })
        let old = group("old")
        let a = vm.setSourceFolder(directory)
        let first = await reader.next()
        await reader.finish(first.id, with: discovery([old]))
        await a.value
        XCTAssertTrue(vm.canAddToQueue)
        vm.setSearch("old")
        vm.setSort(.date)
        vm.setFilter(.splits)
        let b = vm.setSourceFolder(directory.appendingPathComponent("B"))
        // No suspension between source selection and enqueue: this was the original race window.
        XCTAssertFalse(vm.canAddToQueue)
        XCTAssertTrue(vm.selectedGroupIDs.isEmpty)
        XCTAssertTrue(vm.groups.isEmpty)
        XCTAssertEqual(vm.searchText, "")
        XCTAssertEqual(vm.sortKey, .found)
        XCTAssertEqual(vm.recordingFilter, .all)
        vm.toggleSelection(old) // even a delayed row action cannot revive enqueue eligibility
        vm.addToQueue()
        XCTAssertTrue(queue.jobs.isEmpty)
        let second = await reader.next()
        await reader.finish(second.id, with: discovery([]))
        await b.value
    }

    func testOldDatePrewarmCannotSeedNewRequestCacheWithReusedGroupIDs() async {
        await prewarmOverlap(latestFinishesFirst: false)
        await prewarmOverlap(latestFinishesFirst: true)
    }

    private func prewarmOverlap(latestFinishesFirst: Bool) async {
        let reader = ScanGate<URL, DJIFolderReader.Discovery>()
        let warmer = ScanGate<[RecordGroup], [UUID: Date?]>()
        let vm = ConversionViewModel(queue: QueueManager(storageDirectory: directory),
                                     discover: { await reader.call($0) },
                                     warmDates: { groups, _ in await warmer.call(groups) })
        let reused = group("same")
        let a = vm.setSourceFolder(directory)
        let first = await reader.next()
        await reader.finish(first.id, with: discovery([reused]))
        let warmA = await warmer.next()
        let b = vm.scan()!
        let second = await reader.next()
        await reader.finish(second.id, with: discovery([reused]))
        let warmB = await warmer.next()
        let currentDate = Date(timeIntervalSince1970: 2)
        if latestFinishesFirst {
            await warmer.finish(warmB.id, with: [reused.id: currentDate])
            await b.value
            var publications = 0
            let observation = vm.objectWillChange.sink { publications += 1 }
            await warmer.finish(warmA.id, with: [reused.id: Date(timeIntervalSince1970: 1)])
            await a.value
            XCTAssertEqual(publications, 0, "Stale prewarm must not publish a date-cache revision")
            withExtendedLifetime(observation) {}
        } else {
            await warmer.finish(warmA.id, with: [reused.id: Date(timeIntervalSince1970: 1)])
            await a.value
            await warmer.finish(warmB.id, with: [reused.id: currentDate])
            await b.value
        }
        XCTAssertEqual(vm.resolvedStartDate(for: reused), currentDate)
    }
}

/// Continuation rendezvous: call arrival and completion are both explicit, without timing sleeps.
private actor ScanGate<Input: Sendable, Output: Sendable> {
    struct Request: Sendable {
        let id: UUID
        let input: Input
    }
    private var pending: [UUID: CheckedContinuation<Output, Never>] = [:]
    private var arrivals: [Request] = []
    private var waiters: [CheckedContinuation<Request, Never>] = []

    func call(_ input: Input) async -> Output {
        await withCheckedContinuation { continuation in
            let request = Request(id: UUID(), input: input)
            pending[request.id] = continuation
            if waiters.isEmpty { arrivals.append(request) }
            else { waiters.removeFirst().resume(returning: request) }
        }
    }
    func next() async -> Request {
        if !arrivals.isEmpty { return arrivals.removeFirst() }
        return await withCheckedContinuation { waiters.append($0) }
    }
    func finish(_ id: UUID, with value: Output) {
        pending.removeValue(forKey: id)!.resume(returning: value)
    }
}
