import XCTest

// Drives ImmichClient against MockURLProtocol — no server, runs in CI. Covers
// error handling, decoding, the pagination loop, multipart upload, and the
// timeline probe helpers, which the live integration tests don't exercise.
final class ImmichClientMockTests: XCTestCase {
    private let asset = #"{"id":"x","type":"IMAGE","originalFileName":"f.jpg","fileCreatedAt":"2024-01-01T00:00:00.000Z"}"#

    override func tearDown() {
        MockURLProtocol.handler = nil
    }

    // MARK: error handling

    func testHTTPErrorStatusThrows() async {
        let client = MockClient.make(status: 500, json: "{}")
        await XCTAssertThrowsErrorAsync(try await client.listAlbums()) { error in
            guard case ImmichError.httpStatus(_, let code) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(code, 500)
        }
    }

    func testMalformedJSONThrows() async {
        let client = MockClient.make(json: "definitely not json")
        await XCTAssertThrowsErrorAsync(try await client.listAlbums()) { error in
            XCTAssertTrue(error is DecodingError, "got \(error)")
        }
    }

    func testTransportFailureThrows() async {
        let client = MockClient.make { _ in throw URLError(.notConnectedToInternet) }
        await XCTAssertThrowsErrorAsync(try await client.listAlbums())
    }

    // MARK: decoding success

    func testListAlbumsDecodes() async throws {
        let client = MockClient.make(json: #"[{"id":"a","albumName":"X","assetCount":3}]"#)
        let albums = try await client.listAlbums()
        XCTAssertEqual(albums.map(\.albumID), ["a"])
    }

    func testListTagsDecodes() async throws {
        let client = MockClient.make(json: #"[{"id":"t","name":"Trip","value":"Trip"}]"#)
        let tags = try await client.listTags()
        XCTAssertEqual(tags.map { "\($0.id):\($0.name)" }, ["t:Trip"])
    }

    func testListCitiesDerivesPlaces() async throws {
        let withLoc = #"{"id":"x","type":"IMAGE","originalFileName":"f.jpg","fileCreatedAt":"2024-01-01T00:00:00.000Z","exifInfo":{"city":"Paris","country":"France"}}"#
        let noLoc = asset // no exifInfo -> filtered out
        let client = MockClient.make(json: "[\(withLoc),\(noLoc)]")
        let places = try await client.listCities()
        XCTAssertEqual(places, [PlaceSummary(country: "France", city: "Paris")])
    }

    func testListPeopleFiltersUnnamed() async throws {
        let json = #"{"people":[{"id":"1","name":"Alice","isHidden":false},{"id":"2","name":"","isHidden":false}],"hasNextPage":false}"#
        let client = MockClient.make(json: json)
        let people = try await client.listPeople()
        XCTAssertEqual(people.map(\.id), ["1"])
    }

    // MARK: pagination

    func testSearchPaginatesUntilNoNextPage() async throws {
        let calls = AtomicInt()
        let item = asset
        let client = MockClient.make { _ in
            let next = calls.next() == 1 ? "\"2\"" : "null"
            return (200, Data(#"{"assets":{"items":[\#(item)],"nextPage":\#(next)}}"#.utf8))
        }
        let assets = try await client.searchAllAlbum(albumID: "a")
        XCTAssertEqual(assets.count, 2, "two pages, one item each")
    }

    // MARK: write methods

    func testUploadAssetParsesCreatedAndDuplicate() async throws {
        let created = MockClient.make(json: #"{"id":"new","status":"created"}"#)
        let r1 = try await created.uploadAsset(filename: "a.png", data: Data([0x1, 0x2]), createdAt: "t", modifiedAt: "t")
        XCTAssertEqual(r1.id, "new")
        XCTAssertFalse(r1.isDuplicate)

        let dup = MockClient.make(json: #"{"id":"old","status":"duplicate"}"#)
        let r2 = try await dup.uploadAsset(filename: "a.png", data: Data([0x1]), createdAt: "t", modifiedAt: "t")
        XCTAssertTrue(r2.isDuplicate)
    }

    func testCreateAndRenameAlbumDecode() async throws {
        let client = MockClient.make(json: #"{"id":"al","albumName":"Name","assetCount":0}"#)
        let created = try await client.createAlbum(name: "Name")
        XCTAssertEqual(created.albumID, "al")
        let renamed = try await client.renameAlbum(id: "al", name: "Name")
        XCTAssertEqual(renamed.albumName, "Name")
    }

    func testMutationsHitCorrectEndpoints() async throws {
        let log = RequestLog()
        let client = MockClient.make { req in log.record(req); return (200, Data("[]".utf8)) }
        try await client.addAssets(albumID: "a", assetIDs: ["x"])
        try await client.removeAssets(albumID: "a", assetIDs: ["x"])
        try await client.trashAssets(assetIDs: ["x"])
        try await client.deleteAssetsPermanently(assetIDs: ["x"])
        try await client.deleteAlbum(id: "a")
        XCTAssertEqual(log.all, [
            "PUT /api/albums/a/assets",
            "DELETE /api/albums/a/assets",
            "DELETE /api/assets",
            "DELETE /api/assets",
            "DELETE /api/albums/a",
        ])
    }

    func testDownloadReturnsRawBytes() async throws {
        let client = MockClient.make { _ in (200, Data([0xFF, 0xD8, 0xFF])) }
        let original = try await client.downloadOriginal(assetID: "x")
        XCTAssertEqual(original.count, 3)
        let thumbnail = try await client.downloadThumbnail(assetID: "x", size: nil)
        XCTAssertEqual(thumbnail.count, 3)
    }

    // MARK: timeline probe helpers

    func testAssetYearRange() async throws {
        let client = MockClient.make(json: #"{"assets":{"items":[\#(asset)],"nextPage":null}}"#)
        let range = try await client.assetYearRange()
        XCTAssertEqual(range?.oldest, 2024)
        XCTAssertEqual(range?.newest, 2024)
    }

    func testAssetYearRangeNilWhenEmpty() async throws {
        let client = MockClient.make(json: #"{"assets":{"items":[],"nextPage":null}}"#)
        let range = try await client.assetYearRange()
        XCTAssertNil(range)
    }

    func testNonEmptyMonthsKeepsAllWhenPresent() async throws {
        let client = MockClient.make(json: #"{"assets":{"items":[\#(asset)],"nextPage":null}}"#)
        let months = await client.nonEmptyMonths(year: "2024")
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first, "2024-01")
    }

    // A failing probe falls open — the candidate is kept rather than dropped.
    func testNonEmptyMonthsFallsOpenOnError() async throws {
        let client = MockClient.make { _ in (500, Data("{}".utf8)) }
        let months = await client.nonEmptyMonths(year: "2024")
        XCTAssertEqual(months.count, 12)
    }

    func testNonEmptyYears() async throws {
        let client = MockClient.make(json: #"{"assets":{"items":[\#(asset)],"nextPage":null}}"#)
        let years = await client.nonEmptyYears(oldest: 2020, newest: 2022)
        XCTAssertEqual(years, [2022, 2021, 2020])
    }
}

// A thread-safe counter for stateful mock handlers (probe helpers fire requests
// concurrently).
final class AtomicInt: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()
    func next() -> Int {
        lock.lock(); defer { lock.unlock() }
        value += 1
        return value
    }
    var count: Int {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

// XCTAssertThrowsError has no async form; this awaits then asserts.
func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ handler: (Error) -> Void = { _ in },
    file: StaticString = #filePath, line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("expected an error to be thrown", file: file, line: line)
    } catch {
        handler(error)
    }
}
