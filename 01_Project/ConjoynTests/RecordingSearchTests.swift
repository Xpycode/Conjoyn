import XCTest
@testable import Conjoyn

// MARK: - Recordings-list search tests (header search field)

/// Covers the two halves of the header search field:
///   1. `setSearch(_:)` / `resetSearch()` state — and that search, unlike `setFilter(_:)`, never
///      touches selection.
///   2. The pure matching rule — `normalizedQuery(_:)` (whitespace must not narrow the list) and
///      `matchesSearch(_:title:filenames:)` (case-insensitive, title *or* segment filename).
/// Both halves are static over plain strings, so no scanned card is needed (mirrors
/// `RecordingSortTests`).
@MainActor
final class RecordingSearchTests: XCTestCase {

    // MARK: State

    func testSetAndResetSearch() {
        let vm = ConversionViewModel()
        vm.setSearch("GX01")
        XCTAssertEqual(vm.searchText, "GX01")
        vm.resetSearch()
        XCTAssertEqual(vm.searchText, "")
    }

    func testSearchDoesNotTouchSelection() {
        // `setFilter(_:)` auto-selects matching rows; search must not — a transient text filter
        // silently changing what `addToQueue` will enqueue would be a trap.
        let vm = ConversionViewModel()
        let before = vm.selectedGroupIDs
        vm.setSearch("DJI_0042")
        XCTAssertEqual(vm.selectedGroupIDs, before)
        vm.resetSearch()
        XCTAssertEqual(vm.selectedGroupIDs, before)
    }

    // MARK: Query normalization

    func testNormalizedQueryTrimsWhitespace() {
        XCTAssertEqual(ConversionViewModel.normalizedQuery("  GX01 "), "GX01")
    }

    func testWhitespaceOnlyQueryIsNil() {
        // A space in the field must not filter the list down to nothing.
        XCTAssertNil(ConversionViewModel.normalizedQuery(""))
        XCTAssertNil(ConversionViewModel.normalizedQuery("   "))
    }

    // MARK: Matching rule

    func testMatchesTitleCaseInsensitively() {
        XCTAssertTrue(ConversionViewModel.matchesSearch(
            "gx0163", title: "GX016349 – GX026349", filenames: []))
        XCTAssertTrue(ConversionViewModel.matchesSearch(
            "dji_0042", title: "DJI_0042 – DJI_0047", filenames: []))
    }

    func testMatchesSegmentFilenameWhenTitleDoesNot() {
        // A 3-chapter split's title shows only first–last stems; the middle chapter (and the file
        // extension) live only in the filenames.
        XCTAssertTrue(ConversionViewModel.matchesSearch(
            "GX026349", title: "GX016349 – GX036349",
            filenames: ["GX016349.MP4", "GX026349.MP4", "GX036349.MP4"]))
        XCTAssertTrue(ConversionViewModel.matchesSearch(
            "gx016349.mp4", title: "GX016349 – GX036349",
            filenames: ["GX016349.MP4", "GX026349.MP4", "GX036349.MP4"]))
    }

    func testNoMatchIsFalse() {
        XCTAssertFalse(ConversionViewModel.matchesSearch(
            "DJI_0099", title: "DJI_0042 – DJI_0047",
            filenames: ["DJI_0042.MP4", "DJI_0043.MP4"]))
    }
}
