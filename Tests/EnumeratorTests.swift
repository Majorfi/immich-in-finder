import XCTest
import FileProvider

// Captures what an enumerator hands back, so we can drive ItemEnumerator with a
// mocked client and assert the items without the File Provider system.
final class MockEnumObserver: NSObject, NSFileProviderEnumerationObserver {
    var items: [NSFileProviderItem] = []
    var error: Error?
    var didEnumerateCalls = 0
    var lastUpTo: NSFileProviderPage?
    let done = XCTestExpectation(description: "enumeration finished")

    func didEnumerate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        didEnumerateCalls += 1
        items.append(contentsOf: updatedItems)
    }
    func finishEnumerating(upTo nextPage: NSFileProviderPage?) { lastUpTo = nextPage; done.fulfill() }
    func finishEnumeratingWithError(_ error: any Error) { self.error = error; done.fulfill() }
}

// Captures a change round: the didUpdate items and the final (anchor, moreComing)
// the enumerator reports, so the no-op change feed can be asserted without the
// File Provider system.
final class MockChangeObserver: NSObject, NSFileProviderChangeObserver {
    var updated: [NSFileProviderItem] = []
    var deleted: [NSFileProviderItemIdentifier] = []
    var didUpdateCalls = 0
    var finalAnchor: NSFileProviderSyncAnchor?
    var moreComing = false
    let done = XCTestExpectation(description: "changes finished")

    func didUpdate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        didUpdateCalls += 1
        updated.append(contentsOf: updatedItems)
    }
    func didDeleteItems(withIdentifiers deletedItemIdentifiers: [NSFileProviderItemIdentifier]) {
        deleted.append(contentsOf: deletedItemIdentifiers)
    }
    func finishEnumeratingChanges(upTo anchor: NSFileProviderSyncAnchor, moreComing: Bool) {
        finalAnchor = anchor
        self.moreComing = moreComing
        done.fulfill()
    }
    func finishEnumeratingWithError(_ error: any Error) { done.fulfill() }
}

final class EnumeratorTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil }

    private func enumerate(_ container: EnumeratedContainer) async -> (items: [NSFileProviderItem], error: Error?) {
        let client = MockClient.immichLike(citiesReturnAsset: true)
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: container)
        let observer = MockEnumObserver()
        enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage(Data("p".utf8)))
        await fulfillment(of: [observer.done], timeout: 10)
        return (observer.items, observer.error)
    }

    // Drives every branch of the enumerateItems switch and checks the first item
    // each branch produces (not just that something came back).
    func testEveryContainerEnumeratesExpectedItems() async {
        let original = VisibleSections.load()
        defer { VisibleSections.save(original) }
        VisibleSections.save(Set(SectionKind.allCases))
        // (container, label, expected first filename or nil to only check non-empty)
        let containers: [(EnumeratedContainer, String, String?)] = [
            (.sections, "sections", "Albums"),
            (.albums, "albums", "Trip"),
            (.album(id: "a"), "album assets", "f.jpg"),
            (.years, "years", "2024"),
            (.months(year: "2024"), "months", nil),
            (.month(yearMonth: "2024-03"), "month assets", "f.jpg"),
            (.people, "people", "Alice"),
            (.person(id: "p"), "person assets", "f.jpg"),
            (.countries, "countries", "France"),
            (.cities(country: "France"), "cities", "Paris"),
            (.place(country: "France", city: "Paris"), "place assets", "f.jpg"),
            (.tags, "tags", "Trip"),
            (.tag(id: "t"), "tag assets", "f.jpg"),
            (.favorites, "favorites", "f.jpg"),
        ]
        for (container, label, expectedFirst) in containers {
            let (items, error) = await enumerate(container)
            XCTAssertNil(error, "\(label) errored: \(String(describing: error))")
            XCTAssertFalse(items.isEmpty, "\(label) enumerated nothing")
            if let expectedFirst {
                XCTAssertEqual(items.first?.filename, expectedFirst, "\(label) first item")
            }
        }
    }

    // A client whose /api/search/metadata returns nextPage:"2" on the first call
    // and null afterwards, so a folder spans two pages.
    private func twoPageSearchClient() -> ImmichClient {
        let calls = AtomicInt()
        let item = Fixtures.assetJSON()
        return MockClient.make { _ in
            let next: String
            if calls.next() == 1 {
                next = "\"2\""
            } else {
                next = "null"
            }
            return (200, Data(#"{"assets":{"items":[\#(item)],"nextPage":\#(next)}}"#.utf8))
        }
    }

    // enumerateItems paginates: page 1 delivers its items and hands back a non-nil
    // cursor pointing at page 2; the system re-enters with that cursor, which
    // delivers the last page and finishes upTo nil. Only one page is held at a time.
    func testEnumerateItemsPaginates() async {
        let client = twoPageSearchClient()
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: .favorites)

        let first = MockEnumObserver()
        enumerator.enumerateItems(for: first, startingAt: NSFileProviderPage(NSFileProviderPage.initialPageSortedByName as Data))
        await fulfillment(of: [first.done], timeout: 10)
        XCTAssertNil(first.error)
        XCTAssertEqual(first.items.count, 1, "page 1 of the two-page mock holds one item")
        XCTAssertNotNil(first.lastUpTo, "more pages remain, so a cursor is handed back")
        XCTAssertEqual(first.lastUpTo.map { immichPageNumber(from: $0) }, 2, "cursor points at page 2")

        let second = MockEnumObserver()
        enumerator.enumerateItems(for: second, startingAt: first.lastUpTo!)
        await fulfillment(of: [second.done], timeout: 10)
        XCTAssertNil(second.error)
        XCTAssertEqual(second.items.count, 1, "page 2 delivers the remaining item")
        XCTAssertNil(second.lastUpTo, "the last page finishes upTo nil")
    }

    // enumerateChanges is a no-op for every container: no didUpdate, finishes
    // moreComing false against the same anchor it was given.
    func testEnumerateChangesIsNoOp() async {
        let client = MockClient.immichLike(citiesReturnAsset: true)
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: .favorites)
        let changes = MockChangeObserver()
        let anchor = NSFileProviderSyncAnchor(Data("static".utf8))
        enumerator.enumerateChanges(for: changes, from: anchor)
        await fulfillment(of: [changes.done], timeout: 5)
        XCTAssertEqual(changes.didUpdateCalls, 0, "no incremental change feed")
        XCTAssertFalse(changes.moreComing)
        XCTAssertEqual(changes.finalAnchor?.rawValue, anchor.rawValue)
    }

    // The sections container honours the visible-folders setting.
    func testSectionsRespectVisibility() async {
        VisibleSections.save([.albums])
        defer { VisibleSections.save(Set(SectionKind.allCases)) }
        let (items, error) = await enumerate(.sections)
        XCTAssertNil(error)
        XCTAssertEqual(items.map(\.filename), ["Albums"])
    }

    // A server error surfaces through finishEnumeratingWithError.
    func testEnumerationErrorIsReported() async {
        let client = MockClient.make(status: 500, json: "{}")
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: .albums)
        let observer = MockEnumObserver()
        enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage(Data()))
        await fulfillment(of: [observer.done], timeout: 10)
        XCTAssertNotNil(observer.error)
    }

    // currentSyncAnchor returns nil: with no change feed, the system re-runs the
    // full enumerateItems on every reopen rather than asking for deltas.
    func testSyncAnchorIsNil() async {
        let client = MockClient.immichLike(citiesReturnAsset: true)
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: .favorites)
        let anchorExp = expectation(description: "anchor")
        enumerator.currentSyncAnchor { anchor in
            XCTAssertNil(anchor)
            anchorExp.fulfill()
        }
        await fulfillment(of: [anchorExp], timeout: 5)
    }
}
