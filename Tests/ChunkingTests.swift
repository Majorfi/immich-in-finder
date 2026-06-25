import XCTest
import FileProvider

final class ChunkingTests: XCTestCase {
    override func tearDown() {
        MockURLProtocol.handler = nil
        ChunkingSettings.save(.default)
    }

    // MARK: - Pure chunk math

    func testChunkCountRoundsUp() {
        let settings = ChunkingSettings(enabled: true, size: 100)
        XCTAssertEqual(settings.chunkCount(for: 250), 3)
        XCTAssertEqual(settings.chunkCount(for: 200), 2)
        XCTAssertEqual(settings.chunkCount(for: 1), 1)
        XCTAssertEqual(settings.chunkCount(for: 0), 1)
    }

    func testChunkIndexIsPositionOverSize() {
        let settings = ChunkingSettings(enabled: true, size: 100)
        XCTAssertEqual(settings.chunkIndex(forAssetIndex: 0, count: 250), 0)
        XCTAssertEqual(settings.chunkIndex(forAssetIndex: 99, count: 250), 0)
        XCTAssertEqual(settings.chunkIndex(forAssetIndex: 100, count: 250), 1)
        XCTAssertEqual(settings.chunkIndex(forAssetIndex: 249, count: 250), 2)
    }

    // An asset whose position exceeds the counted set still maps to the last
    // listed chunk rather than a folder that was never enumerated.
    func testChunkIndexClampsToLastChunk() {
        let settings = ChunkingSettings(enabled: true, size: 100)
        XCTAssertEqual(settings.chunkIndex(forAssetIndex: 400, count: 250), 2)
    }

    // A hostile or buggy server count must not overflow the page arithmetic or
    // make the folder count unbounded.
    func testChunkCountIsOverflowSafeAndCapped() {
        let settings = ChunkingSettings(enabled: true, size: 1000)
        XCTAssertEqual(settings.chunkCount(for: Int.max), ChunkingSettings.maxChunkFolders)
        XCTAssertEqual(settings.chunkCount(for: -5), 1)
        XCTAssertEqual(settings.chunkCount(for: 0), 1)
        XCTAssertEqual(settings.chunkCount(for: 2500), 3)
    }

    // A crafted/stale identifier index must clamp into the valid page range instead
    // of trapping on `index * size`.
    func testChunkSliceClampsCraftedIndex() {
        let huge = chunkSlice(index: .max, size: 1000, total: 2500)
        XCTAssertTrue(huge.lowerBound >= 0 && huge.upperBound <= 2500 && huge.lowerBound <= huge.upperBound)
        XCTAssertEqual(chunkSlice(index: 99, size: 1000, total: 2500), 2000..<2500)
        XCTAssertEqual(chunkSlice(index: 0, size: 1000, total: 2500), 0..<1000)
        XCTAssertEqual(chunkSlice(index: -3, size: 1000, total: 2500), 0..<1000)
        XCTAssertEqual(chunkSlice(index: 0, size: 1000, total: 0), 0..<0)
    }

    func testChunkRangeLabelDoesNotOverflowOnHugeIndex() {
        XCTAssertEqual(chunkRangeLabel(index: .max, size: 1000, total: 2500), "2001-2500")
    }

    func testSearchStatisticsClampsNegativeTotal() async throws {
        let client = MockClient.make { _ in (200, Data(#"{"total":-7}"#.utf8)) }
        let total = try await client.searchStatistics(for: .album(id: "a"))
        XCTAssertEqual(total, 0)
    }

    func testIsChunkedRespectsToggleAndSize() {
        let on = ChunkingSettings(enabled: true, size: 100)
        XCTAssertTrue(on.isChunked(count: 101), "more than one page is chunked")
        XCTAssertFalse(on.isChunked(count: 100), "exactly one page stays flat")
        let off = ChunkingSettings(enabled: false, size: 100)
        XCTAssertFalse(off.isChunked(count: 10_000))
    }

    // MARK: - Identifier grammar round-trips

    func testAssetLocationCodeRoundTrips() {
        let locations: [AssetLocation] = [
            .album(id: "AL-1"),
            .month(yearMonth: "2024-03"),
            .person(id: "P-1"),
            .tag(id: "T-1"),
            .favorite,
            .place(country: "France", city: "Paris")
        ]
        for location in locations {
            guard let decoded = AssetLocation(code: location.code) else {
                XCTFail("code did not decode: \(location.code)")
                continue
            }
            XCTAssertEqual(decoded.code, location.code, "round-trip changed \(location.code)")
        }
    }

    func testChunkIdentifierRoundTrips() {
        let cases: [(AssetLocation, Int)] = [
            (.album(id: "AL-1"), 0),
            (.place(country: "France", city: "Paris"), 7),
            (.favorite, 3)
        ]
        for (location, index) in cases {
            let identifier = ItemID.chunk(location: location, index: index).identifier
            guard case .chunk(let parsedLocation, let parsedIndex) = ItemID(identifier) else {
                XCTFail("did not parse back to a chunk: \(identifier.rawValue)")
                continue
            }
            XCTAssertEqual(parsedIndex, index)
            XCTAssertEqual(parsedLocation.code, location.code)
        }
    }

    // MARK: - Enumeration

    private func enumerate(_ container: EnumeratedContainer, client: ImmichClient) async -> [NSFileProviderItem] {
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: container)
        let observer = MockEnumObserver()
        enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage(Data("p".utf8)))
        await fulfillment(of: [observer.done], timeout: 10)
        XCTAssertNil(observer.error)
        return observer.items
    }

    // A statistics total over the threshold makes a container enumerate chunk
    // folders (named as zero-padded ranges) instead of assets, with no asset fetch.
    func testLargeContainerEnumeratesChunkFolders() async {
        ChunkingSettings.save(ChunkingSettings(enabled: true, size: 100))
        let client = MockClient.make { req in
            let path = req.url?.path ?? ""
            if path == "/api/search/statistics" {
                return (200, Data(#"{"total":250}"#.utf8))
            }
            return (200, Data("{}".utf8))
        }
        let items = await enumerate(.album(id: "a"), client: client)
        XCTAssertEqual(items.count, 3, "250 assets at size 100 split into 3 chunk folders")
        XCTAssertEqual(items.first?.filename, "001-100")
        XCTAssertEqual(items.last?.filename, "201-250")
        XCTAssertEqual(items.first?.itemIdentifier, ItemID.chunk(location: .album(id: "a"), index: 0).identifier)
        XCTAssertEqual(items.first?.parentItemIdentifier, ItemID.album("a").identifier)
    }

    // Below the threshold the container still paginates assets directly.
    func testSmallContainerStaysFlat() async {
        ChunkingSettings.save(ChunkingSettings(enabled: true, size: 100))
        let asset = Fixtures.assetJSON()
        let client = MockClient.make { req in
            let path = req.url?.path ?? ""
            if path == "/api/search/statistics" {
                return (200, Data(#"{"total":50}"#.utf8))
            }
            return (200, Data("{\"assets\":{\"items\":[\(asset)],\"nextPage\":null}}".utf8))
        }
        let items = await enumerate(.album(id: "a"), client: client)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.filename, "f.jpg", "flat enumeration yields assets, not chunk folders")
    }

    // A client whose /search/metadata returns the given (id, month) assets as one
    // page. The date strategy slices this in memory, so it never needs a
    // month-scoped search.
    private func dateClient(_ assets: [(id: String, month: String)]) -> ImmichClient {
        let items = assets.map {
            "{\"id\":\"\($0.id)\",\"type\":\"IMAGE\",\"originalFileName\":\"\($0.id).jpg\",\"fileCreatedAt\":\"\($0.month)-15T00:00:00.000Z\"}"
        }.joined(separator: ",")
        let body = "{\"assets\":{\"items\":[\(items)],\"nextPage\":null}}"
        return MockClient.make { _ in (200, Data(body.utf8)) }
    }

    private static let albumA = AssetLocation.album(id: "a")

    // Date strategy, single year with several months: the album collapses straight
    // to month folders (no year folder), parented to the album.
    func testDateStrategyEnumeratesMonthFolders() async {
        ChunkingSettings.save(ChunkingSettings(enabled: true, size: 2, strategy: .date))
        let client = dateClient([("a", "2024-03"), ("b", "2024-03"), ("c", "2024-07")])
        let items = await enumerate(.album(id: "a"), client: client)
        XCTAssertEqual(items.count, 2)
        XCTAssertEqual(
            Set(items.map { $0.itemIdentifier }),
            [ItemID.dateMonth(location: Self.albumA, yearMonth: "2024-03").identifier,
             ItemID.dateMonth(location: Self.albumA, yearMonth: "2024-07").identifier]
        )
        XCTAssertTrue(items.allSatisfy { $0.parentItemIdentifier == ItemID.album("a").identifier })
    }

    // Opening a month folder delivers that month's assets, parented to the month.
    func testDateStrategyMonthDeliversAssets() async {
        ChunkingSettings.save(ChunkingSettings(enabled: true, size: 2, strategy: .date))
        let client = dateClient([("a", "2024-03"), ("b", "2024-03"), ("c", "2024-07")])
        let items = await enumerate(.dateMonth(location: Self.albumA, yearMonth: "2024-03"), client: client)
        XCTAssertEqual(items.count, 2)
        XCTAssertTrue(items.allSatisfy { $0.parentItemIdentifier == ItemID.dateMonth(location: Self.albumA, yearMonth: "2024-03").identifier })
    }

    // A single month bigger than the page size becomes page folders, and a page's
    // assets report that page as parent (the date-strategy keystone).
    func testDateStrategyPagesALargeMonth() async {
        ChunkingSettings.save(ChunkingSettings(enabled: true, size: 2, strategy: .date))
        let client = dateClient([("a", "2024-03"), ("b", "2024-03"), ("c", "2024-03")])
        let root = await enumerate(.album(id: "a"), client: client)
        XCTAssertEqual(root.count, 2, "3 assets at size 2 in one month -> 2 page folders")
        XCTAssertEqual(root.first?.itemIdentifier, ItemID.datePage(location: Self.albumA, yearMonth: "2024-03", page: 0).identifier)
        let page = await enumerate(.datePage(location: Self.albumA, yearMonth: "2024-03", page: 1), client: client)
        XCTAssertEqual(page.count, 1)
        XCTAssertEqual(page.first?.parentItemIdentifier, ItemID.datePage(location: Self.albumA, yearMonth: "2024-03", page: 1).identifier)
    }

    // The keystone: an asset enumerated inside chunk k reports that chunk as its
    // parent, so item(for:) resolving the same asset to the same chunk agrees.
    func testChunkAssetsReportChunkParent() async {
        ChunkingSettings.save(ChunkingSettings(enabled: true, size: 100))
        let asset = Fixtures.assetJSON()
        let client = MockClient.make { req in
            (200, Data("{\"assets\":{\"items\":[\(asset)],\"nextPage\":null}}".utf8))
        }
        let items = await enumerate(.chunk(location: .album(id: "a"), index: 1), client: client)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items.first?.parentItemIdentifier, ItemID.chunk(location: .album(id: "a"), index: 1).identifier)
        XCTAssertEqual(items.first?.itemIdentifier, ItemID.asset(albumID: "a", assetID: "x").identifier, "asset identity is unchanged by chunking")
    }
}
