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
        XCTAssertEqual(AppGroup.domainDisplayName, "Findich")
        XCTAssertFalse(AppGroup.identifier.isEmpty)
        XCTAssertFalse(AppGroup.domainIdentifier.isEmpty)
        // If this is nil the VisibleSections round-trip above silently no-ops,
        // so assert it; also an early warning if the suite becomes unavailable.
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
        _ = try await cache.assets(for: .favorite)
        _ = try await cache.assets(for: .favorite)          // cached
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
        let people = ImmichCache(client: countingClient(pCalls, json: #"{"people":[{"id":"p","name":"Al","isHidden":false}],"hasNextPage":false}"#))
        let p1 = try await people.peopleList()
        _ = try await people.peopleList()
        XCTAssertEqual(pCalls.count, 1)
        XCTAssertEqual(p1.map(\.personID), ["p"])

        let cCalls = AtomicInt()
        let cities = ImmichCache(client: countingClient(cCalls, json: "[]"))
        _ = try await cities.cityList()
        _ = try await cities.cityList()
        XCTAssertEqual(cCalls.count, 1)

        let tCalls = AtomicInt()
        let tags = ImmichCache(client: countingClient(tCalls, json: #"[{"id":"t","name":"T","value":"T"}]"#))
        let t1 = try await tags.tagList()
        _ = try await tags.tagList()
        XCTAssertEqual(tCalls.count, 1)
        XCTAssertEqual(t1.map(\.tagID), ["t"])
    }

    // A bumped refresh generation must flush the cache so the next read refetches
    // from the server. This is the app -> extension "Update" channel: the app bumps
    // the shared counter, and refreshIfNeeded (run at the top of each enumeration)
    // observes the change and drops the memoized fetches.
    func testRefreshGenerationBumpFlushesCache() async throws {
        let original = AppGroup.refreshGeneration
        defer { AppGroup.defaults?.set(original, forKey: AppGroup.DefaultsKey.refreshGeneration) }
        let calls = AtomicInt()
        let cache = ImmichCache(client: countingClient(calls, json: "[]"))
        _ = try await cache.albumList()
        AppGroup.bumpRefreshGeneration()
        await cache.refreshIfNeeded()
        _ = try await cache.albumList()
        XCTAssertEqual(calls.count, 2, "a generation bump must drop the memoized fetch")
    }

    // Without a bump (and within the TTL) refreshIfNeeded must be a no-op, so a
    // steady enumeration loop keeps serving cached data instead of re-hitting the
    // server on every pass.
    func testRefreshWithoutBumpKeepsCache() async throws {
        let original = AppGroup.refreshGeneration
        defer { AppGroup.defaults?.set(original, forKey: AppGroup.DefaultsKey.refreshGeneration) }
        let calls = AtomicInt()
        let cache = ImmichCache(client: countingClient(calls, json: "[]"))
        _ = try await cache.albumList()
        await cache.refreshIfNeeded()
        _ = try await cache.albumList()
        XCTAssertEqual(calls.count, 1, "an unchanged generation must not reflush")
    }

    // A failed bucket fetch must not be memoized: timelineYears evicts on error
    // so the next pass retries instead of leaving the Timeline stuck empty.
    func testTimelineYearsNotCachedOnError() async throws {
        let buckets = #"[{"timeBucket":"2024-03-01","count":1}]"#
        let cache = ImmichCache(client: MockClient.make { _ in (500, Data("{}".utf8)) })
        await XCTAssertThrowsErrorAsync(try await cache.timelineYears())
        MockURLProtocol.handler = { _ in (200, Data(buckets.utf8)) }
        let years = try await cache.timelineYears()
        XCTAssertEqual(years, [2024], "the retry must refetch, not return a cached empty result")
    }
}
