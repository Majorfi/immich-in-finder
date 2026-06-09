import XCTest

final class VisibleSectionsTests: XCTestCase {
    func testRoundTripThroughAppGroupDefaults() {
        let original = VisibleSections.load()
        defer { VisibleSections.save(original) }
        VisibleSections.save([.albums, .tags])
        XCTAssertEqual(VisibleSections.load(), [.albums, .tags])
    }

    func testDefaultsToAllWhenUnset() {
        let original = VisibleSections.load()
        defer { VisibleSections.save(original) }
        AppGroup.defaults?.removeObject(forKey: AppGroup.DefaultsKey.visibleSections)
        XCTAssertEqual(VisibleSections.load(), Set(SectionKind.allCases))
    }

    func testAppGroupConstants() {
        XCTAssertEqual(AppGroup.domainDisplayName, "Immich")
        XCTAssertFalse(AppGroup.identifier.isEmpty)
        XCTAssertFalse(AppGroup.domainIdentifier.isEmpty)
        _ = AppGroup.defaults // exercise the suite accessor
    }
}

// ImmichCache memoizes in-flight fetches and drops them on invalidation. Driven
// by a mock client so we can count the underlying network calls.
final class ImmichCacheTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil }

    private func countingClient(_ counter: AtomicInt, json: String) -> ImmichClient {
        MockClient.make { _ in _ = counter.next(); return (200, Data(json.utf8)) }
    }

    func testAlbumListIsMemoized() async throws {
        let calls = AtomicInt()
        let cache = ImmichCache(client: countingClient(calls, json: "[]"))
        _ = try await cache.albumList()
        _ = try await cache.albumList()
        XCTAssertEqual(calls.count, 1, "second call should hit the cache")
    }

    func testInvalidateAlbumListRefetches() async throws {
        let calls = AtomicInt()
        let cache = ImmichCache(client: countingClient(calls, json: "[]"))
        _ = try await cache.albumList()
        await cache.invalidateAlbumList()
        _ = try await cache.albumList()
        XCTAssertEqual(calls.count, 2)
    }

    func testAssetsForLocationMemoizedPerKey() async throws {
        let calls = AtomicInt()
        let page = #"{"assets":{"items":[],"nextPage":null}}"#
        let cache = ImmichCache(client: countingClient(calls, json: page))
        _ = try await cache.assets(for: .album(id: "a"))
        _ = try await cache.assets(for: .album(id: "a"))   // cached
        _ = try await cache.assets(for: .tag(id: "t"))      // different key -> new fetch
        XCTAssertEqual(calls.count, 2)
    }

    func testInvalidateLocationRefetches() async throws {
        let calls = AtomicInt()
        let page = #"{"assets":{"items":[],"nextPage":null}}"#
        let cache = ImmichCache(client: countingClient(calls, json: page))
        _ = try await cache.assets(for: .favorite)
        await cache.invalidate(.favorite)
        _ = try await cache.assets(for: .favorite)
        XCTAssertEqual(calls.count, 2)
    }

    func testListCachesCoverAllKinds() async throws {
        // people / city / tag list memoizers share the same shape.
        let people = ImmichCache(client: MockClient.make(json: #"{"people":[],"hasNextPage":false}"#))
        _ = try await people.peopleList()
        let cities = ImmichCache(client: MockClient.make(json: "[]"))
        _ = try await cities.cityList()
        let tags = ImmichCache(client: MockClient.make(json: "[]"))
        _ = try await tags.tagList()
    }
}
