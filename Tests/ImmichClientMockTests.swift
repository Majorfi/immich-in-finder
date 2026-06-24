import XCTest

// Drives ImmichClient against MockURLProtocol; no server, runs in CI. Covers
// error handling, decoding, the pagination loop, multipart upload, and the
// timeline probe helpers, which the live integration tests don't exercise.
final class ImmichClientMockTests: XCTestCase {
    private let asset = Fixtures.assetJSON(date: "2024-01-01")

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

    // MARK: retry / backoff

    // A transient transport blip (timeout) on the first attempt is retried, and
    // the subsequent success is returned, proving the bounded retry kicks in.
    func testTransientTransportFailureThenSuccessIsRetried() async throws {
        let calls = AtomicInt()
        let client = MockClient.make { _ in
            if calls.next() == 1 { throw URLError(.timedOut) }
            return (200, Data(#"[{"id":"a","albumName":"X","assetCount":3}]"#.utf8))
        }
        let albums = try await client.listAlbums()
        XCTAssertEqual(albums.map(\.albumID), ["a"])
        XCTAssertEqual(calls.count, 2, "first attempt failed transiently, second succeeded")
    }

    // A transient HTTP status (503) on the first attempt is retried, and the
    // subsequent 200 is returned.
    func testTransientHTTPStatusThenSuccessIsRetried() async throws {
        let calls = AtomicInt()
        let client = MockClient.make { _ in
            if calls.next() == 1 { return (503, Data("{}".utf8)) }
            return (200, Data(#"[{"id":"a","albumName":"X","assetCount":3}]"#.utf8))
        }
        let albums = try await client.listAlbums()
        XCTAssertEqual(albums.map(\.albumID), ["a"])
        XCTAssertEqual(calls.count, 2, "first attempt 503, second 200")
    }

    // A 4xx (auth) is definitive: it must NOT be retried, so exactly one
    // attempt fires and the httpStatus error surfaces immediately.
    func testAuthErrorIsNotRetried() async {
        let calls = AtomicInt()
        let client = MockClient.make { _ in
            _ = calls.next()
            return (401, Data("{}".utf8))
        }
        await XCTAssertThrowsErrorAsync(try await client.listAlbums()) { error in
            guard case ImmichError.httpStatus(_, let code) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(code, 401)
        }
        XCTAssertEqual(calls.count, 1, "4xx is single-attempt, no retry")
    }

    // Retries are bounded: a persistently transient status exhausts at exactly
    // maxAttempts and then surfaces the httpStatus error.
    func testTransientRetryExhausts() async {
        let calls = AtomicInt()
        let client = MockClient.make { _ in
            _ = calls.next()
            return (503, Data("{}".utf8))
        }
        await XCTAssertThrowsErrorAsync(try await client.listAlbums()) { error in
            guard case ImmichError.httpStatus(_, let code) = error else { return XCTFail("got \(error)") }
            XCTAssertEqual(code, 503)
        }
        XCTAssertEqual(calls.count, 3, "bounded at maxAttempts")
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
        XCTAssertEqual(tags.map { "\($0.tagID):\($0.name)" }, ["t:Trip"])
    }

    func testListCitiesDerivesPlaces() async throws {
        let withLoc = Fixtures.assetJSON(date: "2024-01-01", city: "Paris", country: "France")
        let noLoc = asset // no exifInfo -> filtered out
        let client = MockClient.make(json: "[\(withLoc),\(noLoc)]")
        let places = try await client.listCities()
        XCTAssertEqual(places, [PlaceSummary(country: "France", city: "Paris")])
    }

    func testListPeopleFiltersUnnamed() async throws {
        let json = #"{"people":[{"id":"1","name":"Alice","isHidden":false},{"id":"2","name":"","isHidden":false}],"hasNextPage":false}"#
        let client = MockClient.make(json: json)
        let people = try await client.listPeople()
        XCTAssertEqual(people.map(\.personID), ["1"])
    }

    // MARK: pagination

    func testSearchPaginatesUntilNoNextPage() async throws {
        let calls = AtomicInt()
        let item = asset
        let client = MockClient.make { _ in
            let next: String = if calls.next() == 1 { "\"2\"" } else { "null" }
            return (200, Data(#"{"assets":{"items":[\#(item)],"nextPage":\#(next)}}"#.utf8))
        }
        let assets = try await client.searchAllFavorites()
        XCTAssertEqual(assets.count, 2, "two pages, one item each")
    }

    // MARK: write methods

    func testUploadAssetParsesCreatedAndDuplicate() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).bin")
        try Data([0x1, 0x2]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let created = MockClient.make(json: #"{"id":"new","status":"created"}"#)
        let r1 = try await created.uploadAsset(filename: "a.png", fileURL: url, createdAt: "t", modifiedAt: "t")
        XCTAssertEqual(r1.ID, "new")
        XCTAssertFalse(r1.isDuplicate)

        let dup = MockClient.make(json: #"{"id":"old","status":"duplicate"}"#)
        let r2 = try await dup.uploadAsset(filename: "a.png", fileURL: url, createdAt: "t", modifiedAt: "t")
        XCTAssertTrue(r2.isDuplicate)
    }

    func testCreateAndRenameAlbumDecode() async throws {
        let client = MockClient.make(json: #"{"id":"al","albumName":"Name","assetCount":0}"#)
        let created = try await client.createAlbum(name: "Name")
        XCTAssertEqual(created.albumID, "al")
        let renamed = try await client.renameAlbum(ID: "al", name: "Name")
        XCTAssertEqual(renamed.albumName, "Name")
    }

    func testMutationsHitCorrectEndpoints() async throws {
        let log = RequestLog()
        let client = MockClient.make { req in log.record(req); return (200, Data("[]".utf8)) }
        try await client.addAssets(albumID: "a", assetIDs: ["x"])
        try await client.removeAssets(albumID: "a", assetIDs: ["x"])
        try await client.trashAssets(assetIDs: ["x"])
        try await client.deleteAssetsPermanently(assetIDs: ["x"])
        try await client.deleteAlbum(ID: "a")
        XCTAssertEqual(log.all, [
            "PUT /api/albums/a/assets",
            "DELETE /api/albums/a/assets",
            "DELETE /api/assets",
            "DELETE /api/assets",
            "DELETE /api/albums/a",
        ])
    }

    func testTrailingSlashIsStrippedFromBaseURL() {
        let client = ImmichClient(baseURL: URL(string: "https://mock.test/")!, apiKey: "k")
        XCTAssertEqual(client.baseURL.absoluteString, "https://mock.test")
    }

    func testDownloadReturnsRawBytes() async throws {
        let client = MockClient.make { _ in (200, Data([0xFF, 0xD8, 0xFF])) }
        let original = try await client.downloadOriginal(assetID: "x")
        XCTAssertEqual(original.count, 3)
        let thumbnail = try await client.downloadThumbnail(assetID: "x", size: nil)
        XCTAssertEqual(thumbnail.count, 3)
    }

    // MARK: timeline helpers

    // One bucketed query yields the non-empty months for the year (other years'
    // buckets are filtered out), preserving the "YYYY-MM" output format.
    func testNonEmptyMonthsDerivesFromBuckets() async throws {
        let json = #"[{"timeBucket":"2024-01-01","count":5},{"timeBucket":"2024-03-01","count":2},{"timeBucket":"2023-06-01","count":9}]"#
        let client = MockClient.make(json: json)
        let months = await client.nonEmptyMonths(year: "2024")
        XCTAssertEqual(months, ["2024-01", "2024-03"])
    }

    // The bucket fetch failing falls open: every candidate month is kept rather
    // than dropped, so one transient error never hides the whole year.
    func testNonEmptyMonthsFallsOpenOnError() async throws {
        let client = MockClient.make { _ in (500, Data("{}".utf8)) }
        let months = await client.nonEmptyMonths(year: "2024")
        XCTAssertEqual(months.count, 12)
        XCTAssertEqual(months.first, "2024-01")
    }

    // Non-empty years are the distinct year prefixes of the bucket list, sorted
    // descending.
    func testNonEmptyYearsDerivesFromBuckets() async throws {
        let json = #"[{"timeBucket":"2022-01-01","count":1},{"timeBucket":"2021-05-01","count":1},{"timeBucket":"2020-12-01","count":1},{"timeBucket":"2022-07-01","count":1}]"#
        let client = MockClient.make(json: json)
        let years = await client.nonEmptyYears()
        XCTAssertEqual(years, [2022, 2021, 2020])
    }

    // Years come only from the bucket list, so a failed bucket fetch yields an
    // empty list (there is no date range to fall back on, unlike nonEmptyMonths).
    func testNonEmptyYearsEmptyOnError() async throws {
        let client = MockClient.make { _ in (500, Data("{}".utf8)) }
        let years = await client.nonEmptyYears()
        XCTAssertEqual(years, [])
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
