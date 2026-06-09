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
        // If this is nil the VisibleSections round-trip above silently no-ops,
        // so assert it — also an early warning if the suite becomes unavailable.
        XCTAssertNotNil(AppGroup.defaults)
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

    func testListCachesAreMemoized() async throws {
        // people / city / tag list memoizers share the album-list shape: a
        // second call must not refetch, and the decoded result is returned.
        let pCalls = AtomicInt()
        let people = ImmichCache(client: MockClient.make { _ in _ = pCalls.next(); return (200, Data(#"{"people":[{"id":"p","name":"Al","isHidden":false}],"hasNextPage":false}"#.utf8)) })
        let p1 = try await people.peopleList()
        _ = try await people.peopleList()
        XCTAssertEqual(pCalls.count, 1)
        XCTAssertEqual(p1.map(\.id), ["p"])

        let cCalls = AtomicInt()
        let cities = ImmichCache(client: MockClient.make { _ in _ = cCalls.next(); return (200, Data("[]".utf8)) })
        _ = try await cities.cityList()
        _ = try await cities.cityList()
        XCTAssertEqual(cCalls.count, 1)

        let tCalls = AtomicInt()
        let tags = ImmichCache(client: MockClient.make { _ in _ = tCalls.next(); return (200, Data(#"[{"id":"t","name":"T","value":"T"}]"#.utf8)) })
        let t1 = try await tags.tagList()
        _ = try await tags.tagList()
        XCTAssertEqual(tCalls.count, 1)
        XCTAssertEqual(t1.map(\.id), ["t"])
    }
}
