import XCTest
@testable import Conjoyn

// MARK: - Recordings-list sort tests (1.0.1 sortable columns)

/// Covers the two halves of the sortable column headers:
///   1. `setSort(_:)` direction state machine — re-clicking the active column flips direction;
///      switching columns adopts that column's natural default.
///   2. The pure `orders(_:before:by:)` comparator — key selection, the stable `index` tie-break,
///      `localizedStandard` name ordering, and the undated-row (`nil` date) policy.
/// The comparator is `static` over plain `SortField` values, so neither half needs a scanned card.
@MainActor
final class RecordingSortTests: XCTestCase {

    private typealias Field = ConversionViewModel.SortField

    private func field(_ index: Int,
                       name: String = "DJI_0001",
                       date: Date? = nil,
                       duration: Double = 0,
                       bytes: Int64 = 0) -> Field {
        Field(index: index, name: name, date: date, duration: duration, bytes: bytes)
    }

    // MARK: setSort direction state machine

    func testFirstClickAdoptsColumnDefaultDirection() {
        let vm = ConversionViewModel()
        // Name reads naturally A→Z (ascending); the numeric/time columns lead with the interesting
        // end (descending: newest / longest / biggest first).
        vm.setSort(.name)
        XCTAssertEqual(vm.sortKey, .name)
        XCTAssertTrue(vm.sortAscending)

        vm.setSort(.date)
        XCTAssertEqual(vm.sortKey, .date)
        XCTAssertFalse(vm.sortAscending)

        vm.setSort(.size)
        XCTAssertFalse(vm.sortAscending)

        vm.setSort(.duration)
        XCTAssertFalse(vm.sortAscending)
    }

    func testReclickingActiveColumnTogglesDirection() {
        let vm = ConversionViewModel()
        vm.setSort(.name)               // ascending
        vm.setSort(.name)               // → descending
        XCTAssertEqual(vm.sortKey, .name)
        XCTAssertFalse(vm.sortAscending)
        vm.setSort(.name)               // → ascending again
        XCTAssertTrue(vm.sortAscending)
    }

    func testSwitchingColumnsResetsToThatColumnsDefault() {
        let vm = ConversionViewModel()
        vm.setSort(.name)               // ascending
        vm.setSort(.name)               // descending
        vm.setSort(.date)               // switching → date's default (descending), not a toggle
        XCTAssertFalse(vm.sortAscending)
    }

    func testResetSortReturnsToDiscoveryOrder() {
        let vm = ConversionViewModel()
        vm.setSort(.size)
        vm.resetSort()
        XCTAssertEqual(vm.sortKey, .found)
        XCTAssertTrue(vm.sortAscending)
    }

    // MARK: Comparator — keys

    func testNameOrderingIsNumericAware() {
        // localizedStandardCompare keeps DJI_0002 before DJI_0010 (not lexicographic "10" < "2").
        let a = field(1, name: "DJI_0002")
        let b = field(2, name: "DJI_0010")
        XCTAssertTrue(ConversionViewModel.orders(a, before: b, by: .name))
        XCTAssertFalse(ConversionViewModel.orders(b, before: a, by: .name))
    }

    func testDurationAndSizeOrderAscending() {
        let short = field(1, duration: 60, bytes: 1_000)
        let long  = field(2, duration: 600, bytes: 9_000)
        XCTAssertTrue(ConversionViewModel.orders(short, before: long, by: .duration))
        XCTAssertTrue(ConversionViewModel.orders(short, before: long, by: .size))
    }

    func testDateOrdersAscending() {
        let older = field(1, date: Date(timeIntervalSince1970: 1_000))
        let newer = field(2, date: Date(timeIntervalSince1970: 9_000))
        XCTAssertTrue(ConversionViewModel.orders(older, before: newer, by: .date))
    }

    // MARK: Comparator — stable tie-break

    func testEqualValuesFallBackToDiscoveryIndex() {
        // Same size; order must follow groupIndex so equal rows never jiggle between renders.
        let first  = field(3, bytes: 5_000)
        let second = field(7, bytes: 5_000)
        XCTAssertTrue(ConversionViewModel.orders(first, before: second, by: .size))
        XCTAssertFalse(ConversionViewModel.orders(second, before: first, by: .size))
    }

    func testFoundKeyIsPureDiscoveryOrder() {
        let a = field(2, name: "DJI_9999", bytes: .max)
        let b = field(5, name: "DJI_0001", bytes: 0)
        XCTAssertTrue(ConversionViewModel.orders(a, before: b, by: .found))
    }

    // MARK: List ordering — undated rows (the nil-date policy: Finder "always last")

    /// Undated rows (`date == nil`) are pinned to the **bottom in BOTH directions**, matching Finder's
    /// "—" behaviour. This lives in `ordered(_:)`, not `orders(_:)`, because it needs the direction.
    /// `index` doubles as the row identity here so we can assert position by id.

    func testUndatedRowsLandLastWhenNewestFirst() {
        // Descending (newest first): dated rows newest→oldest, then undated.
        let rows = [field(1, date: nil),
                    field(2, date: Date(timeIntervalSince1970: 1_000)),
                    field(3, date: Date(timeIntervalSince1970: 9_000))]
        let order = ConversionViewModel.ordered(rows, field: { $0 }, by: .date, ascending: false)
                                       .map(\.index)
        XCTAssertEqual(order, [3, 2, 1])   // newest, older, then undated last
    }

    func testUndatedRowsStillLandLastWhenOldestFirst() {
        // Ascending (oldest first): the undated row must NOT flip to the top — it stays at the bottom.
        let rows = [field(1, date: nil),
                    field(2, date: Date(timeIntervalSince1970: 1_000)),
                    field(3, date: Date(timeIntervalSince1970: 9_000))]
        let order = ConversionViewModel.ordered(rows, field: { $0 }, by: .date, ascending: true)
                                       .map(\.index)
        XCTAssertEqual(order, [2, 3, 1])   // oldest, newer, then undated last (not first)
    }

    func testMultipleUndatedKeepDiscoveryOrderAmongThemselves() {
        let rows = [field(9, date: nil),
                    field(4, date: nil),
                    field(2, date: Date(timeIntervalSince1970: 1_000))]
        let order = ConversionViewModel.ordered(rows, field: { $0 }, by: .date, ascending: false)
                                       .map(\.index)
        XCTAssertEqual(order, [2, 4, 9])   // dated first, then undated by ascending index (4 before 9)
    }

    func testNonDateSortsAreUnaffectedByPartition() {
        // The undated-last split only applies to the date key; size/duration/name pass straight
        // through orders() + the reverse.
        let rows = [field(1, bytes: 1_000), field(2, bytes: 9_000), field(3, bytes: 5_000)]
        let asc  = ConversionViewModel.ordered(rows, field: { $0 }, by: .size, ascending: true).map(\.index)
        let desc = ConversionViewModel.ordered(rows, field: { $0 }, by: .size, ascending: false).map(\.index)
        XCTAssertEqual(asc,  [1, 3, 2])
        XCTAssertEqual(desc, [2, 3, 1])
    }
}
