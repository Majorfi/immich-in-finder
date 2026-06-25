import XCTest

final class DateChunkLayoutTests: XCTestCase {

    // Single year, single month, fits one page: the whole tree collapses to the
    // month's assets hanging directly off the container.
    func testSingleMonthSmallCollapsesToAssets() {
        let layout = DateChunkLayout(monthCounts: ["2024-03": 50], size: 100)
        XCTAssertFalse(layout.hasYearLevel)
        XCTAssertFalse(layout.hasMonthLevel(year: "2024"))
        XCTAssertEqual(layout.rootChildren(), .assets(month: "2024-03"))
        XCTAssertNil(layout.assetParentNode(month: "2024-03", indexInMonth: 0))
    }

    // Single month over the page size: pages hang directly off the container, no
    // month or year folder around them.
    func testSingleMonthLargeCollapsesToPages() {
        let layout = DateChunkLayout(monthCounts: ["2024-03": 250], size: 100)
        XCTAssertEqual(layout.rootChildren(), .folders([
            .page(month: "2024-03", index: 0),
            .page(month: "2024-03", index: 1),
            .page(month: "2024-03", index: 2)
        ]))
        XCTAssertNil(layout.parentNode(of: .page(month: "2024-03", index: 0)))
        XCTAssertEqual(layout.assetParentNode(month: "2024-03", indexInMonth: 0), .page(month: "2024-03", index: 0))
        XCTAssertEqual(layout.assetParentNode(month: "2024-03", indexInMonth: 150), .page(month: "2024-03", index: 1))
    }

    // One year, several months: month folders hang off the container (no year
    // folder), and an asset's parent is its month.
    func testSingleYearMultiMonth() {
        let layout = DateChunkLayout(monthCounts: ["2024-03": 50, "2024-07": 80], size: 100)
        XCTAssertFalse(layout.hasYearLevel)
        XCTAssertTrue(layout.hasMonthLevel(year: "2024"))
        guard case .folders(let nodes) = layout.rootChildren() else {
            return XCTFail("expected month folders")
        }
        XCTAssertEqual(Set(nodes), [.month("2024-03"), .month("2024-07")])
        XCTAssertEqual(layout.monthChildren("2024-03"), .assets(month: "2024-03"))
        XCTAssertNil(layout.parentNode(of: .month("2024-03")))
        XCTAssertEqual(layout.assetParentNode(month: "2024-07", indexInMonth: 0), .month("2024-07"))
    }

    // Multiple years: year folders at the top, then months inside each, with the
    // adaptive collapse applied per year.
    func testMultiYearNesting() {
        let layout = DateChunkLayout(monthCounts: ["2023-05": 30, "2024-03": 50, "2024-07": 80], size: 100)
        XCTAssertTrue(layout.hasYearLevel)
        XCTAssertEqual(layout.rootChildren(), .folders([.year("2024"), .year("2023")]))
        // 2024 has two months -> month folders under the year.
        guard case .folders(let monthsOf2024) = layout.yearChildren("2024") else {
            return XCTFail("expected month folders for 2024")
        }
        XCTAssertEqual(Set(monthsOf2024), [.month("2024-03"), .month("2024-07")])
        XCTAssertEqual(layout.parentNode(of: .month("2024-03")), .year("2024"))
        XCTAssertEqual(layout.assetParentNode(month: "2024-03", indexInMonth: 0), .month("2024-03"))
        // 2023 has one small month -> collapses to that month's assets under the year.
        XCTAssertEqual(layout.yearChildren("2023"), .assets(month: "2023-05"))
        XCTAssertEqual(layout.assetParentNode(month: "2023-05", indexInMonth: 0), .year("2023"))
    }

    // Multi-year where a single-month year is itself paged: the pages hang off the
    // year folder (month level collapsed), and assets point at those pages.
    func testMultiYearWithPagedSingleMonth() {
        let layout = DateChunkLayout(monthCounts: ["2023-05": 250, "2024-03": 50], size: 100)
        XCTAssertEqual(layout.yearChildren("2023"), .folders([
            .page(month: "2023-05", index: 0),
            .page(month: "2023-05", index: 1),
            .page(month: "2023-05", index: 2)
        ]))
        XCTAssertEqual(layout.parentNode(of: .page(month: "2023-05", index: 0)), .year("2023"))
        XCTAssertEqual(layout.assetParentNode(month: "2023-05", indexInMonth: 120), .page(month: "2023-05", index: 1))
        // 2024 is a single small month -> its asset collapses to the year folder.
        XCTAssertEqual(layout.assetParentNode(month: "2024-03", indexInMonth: 0), .year("2024"))
    }

    func testCountsFromAssetsGroupByCaptureMonth() {
        let assets = ["2024-03-01", "2024-03-31", "2024-07-15"].map(Self.decodeAsset)
        XCTAssertEqual(DateChunkLayout.counts(of: assets), ["2024-03": 2, "2024-07": 1])
        XCTAssertEqual(DateChunkLayout.month(of: Self.decodeAsset(date: "2024-07-15")), "2024-07")
    }

    private static func decodeAsset(date: String) -> Asset {
        let json = Fixtures.assetJSON(date: date)
        return try! JSONDecoder().decode(Asset.self, from: Data(json.utf8))
    }
}
