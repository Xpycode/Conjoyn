import XCTest
@testable import Conjoyn

/// Watch-group state machine tests for task 5.3.
/// Covers every legal transition, a representative illegal set, the sole legal self-loop
/// (settling → settling), Codable round-trips for all cases, and the `isTerminal` predicate.
final class WatchGroupStateTests: XCTestCase {

    // MARK: - Legal transitions

    func testDiscoveredToSettling() {
        assertLegal(.discovered, to: .settling)
    }

    func testDiscoveredToFailed() {
        assertLegal(.discovered, to: .failed)
    }

    func testSettlingToGrouped() {
        assertLegal(.settling, to: .grouped)
    }

    func testSettlingToSettlingSelfLoop() {
        // The one legal self-loop: new segment resets the quiet-window timer.
        assertLegal(.settling, to: .settling)
    }

    func testSettlingToFailed() {
        assertLegal(.settling, to: .failed)
    }

    func testGroupedToReady() {
        assertLegal(.grouped, to: .ready)
    }

    func testGroupedToSettling() {
        // New segment arrived after grouping → must re-settle.
        assertLegal(.grouped, to: .settling)
    }

    func testGroupedToFailed() {
        assertLegal(.grouped, to: .failed)
    }

    func testReadyToJoining() {
        assertLegal(.ready, to: .joining)
    }

    func testReadyToFailed() {
        assertLegal(.ready, to: .failed)
    }

    func testJoiningToVerifyingMetadata() {
        assertLegal(.joining, to: .verifyingMetadata)
    }

    func testJoiningToFailed() {
        assertLegal(.joining, to: .failed)
    }

    func testVerifyingMetadataToDone() {
        assertLegal(.verifyingMetadata, to: .done)
    }

    func testVerifyingMetadataToFailed() {
        assertLegal(.verifyingMetadata, to: .failed)
    }

    // MARK: - Illegal transitions

    func testDiscoveredToReadyIsIllegal() {
        // Skips settling and grouped — not allowed.
        assertIllegal(.discovered, to: .ready)
    }

    func testDoneToSettlingIsIllegal() {
        // Terminal state; no outgoing edges.
        assertIllegal(.done, to: .settling)
    }

    func testFailedToJoiningIsIllegal() {
        // Terminal state; no outgoing edges.
        assertIllegal(.failed, to: .joining)
    }

    func testJoiningToDiscoveredIsIllegal() {
        // Backwards transition forbidden.
        assertIllegal(.joining, to: .discovered)
    }

    func testReadyToReadySelfLoopIsIllegal() {
        // Only .settling has a legal self-loop; .ready does not.
        assertIllegal(.ready, to: .ready)
    }

    func testGroupedToDoneIsIllegal() {
        // Skips .ready, .joining, and .verifyingMetadata.
        assertIllegal(.grouped, to: .done)
    }

    func testDoneToFailedIsIllegal() {
        // Terminal; cannot transition even to .failed.
        assertIllegal(.done, to: .failed)
    }

    func testFailedToFailedIsIllegal() {
        // Terminal; no self-loop permitted.
        assertIllegal(.failed, to: .failed)
    }

    // MARK: - Codable round-trip

    func testCodableRoundTripAllCases() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        for state in WatchGroupState.allCases {
            let data = try encoder.encode(state)
            let decoded = try decoder.decode(WatchGroupState.self, from: data)
            XCTAssertEqual(decoded, state, "Round-trip failed for .\(state.rawValue)")
        }
    }

    // MARK: - isTerminal

    func testIsTerminalTrueOnlyForDoneAndFailed() {
        for state in WatchGroupState.allCases {
            let expected = state == .done || state == .failed
            XCTAssertEqual(state.isTerminal, expected,
                           "isTerminal mismatch for .\(state.rawValue)")
        }
    }

    // MARK: - Helpers

    private func assertLegal(_ from: WatchGroupState, to next: WatchGroupState,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(from.canTransition(to: next),
                      ".\(from.rawValue) → .\(next.rawValue) should be legal",
                      file: file, line: line)
        XCTAssertEqual(from.transition(to: next), next,
                       "transition(to:) should return .\(next.rawValue)",
                       file: file, line: line)
    }

    private func assertIllegal(_ from: WatchGroupState, to next: WatchGroupState,
                                file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertFalse(from.canTransition(to: next),
                       ".\(from.rawValue) → .\(next.rawValue) should be illegal",
                       file: file, line: line)
        XCTAssertNil(from.transition(to: next),
                     "transition(to:) should return nil for illegal .\(from.rawValue) → .\(next.rawValue)",
                     file: file, line: line)
    }
}
