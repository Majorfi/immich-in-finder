import XCTest
import FileProvider

// Captures what an enumerator hands back, so we can drive ItemEnumerator with a
// mocked client and assert the items without the File Provider system.
final class MockEnumObserver: NSObject, NSFileProviderEnumerationObserver {
    var items: [NSFileProviderItem] = []
    var error: Error?
    let done = XCTestExpectation(description: "enumeration finished")

    func didEnumerate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        items.append(contentsOf: updatedItems)
    }
    func finishEnumerating(upTo nextPage: NSFileProviderPage?) { done.fulfill() }
    func finishEnumeratingWithError(_ error: any Error) { self.error = error; done.fulfill() }
}

final class EnumeratorTests: XCTestCase {
    override func tearDown() { MockURLProtocol.handler = nil }

    // One handler that answers every endpoint the enumerator touches, keyed by
    // path, so a single client serves all container types.
    private func immichLikeClient() -> ImmichClient {
        let asset = #"{"id":"x","type":"IMAGE","originalFileName":"f.jpg","fileCreatedAt":"2024-03-15T00:00:00.000Z","exifInfo":{"city":"Paris","country":"France"}}"#
        return MockClient.make { req in
            switch req.url?.path ?? "" {
            case "/api/albums":
                return (200, Data(#"[{"id":"a","albumName":"Trip","assetCount":1}]"#.utf8))
            case "/api/search/metadata":
                return (200, Data("{\"assets\":{\"items\":[\(asset)],\"nextPage\":null}}".utf8))
            case "/api/people":
                return (200, Data(#"{"people":[{"id":"p","name":"Alice","isHidden":false}],"hasNextPage":false}"#.utf8))
            case "/api/search/cities":
                return (200, Data("[\(asset)]".utf8))
            case "/api/tags":
                return (200, Data(#"[{"id":"t","name":"Trip","value":"Trip"}]"#.utf8))
            default:
                return (200, Data("{}".utf8))
            }
        }
    }

    private func enumerate(_ container: EnumeratedContainer) async -> (items: [NSFileProviderItem], error: Error?) {
        let client = immichLikeClient()
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

    func testSyncAnchorIsTheStableSentinel() async {
        let client = immichLikeClient()
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: .albums)
        let anchorExp = expectation(description: "anchor")
        enumerator.currentSyncAnchor { anchor in
            XCTAssertEqual(anchor?.rawValue, Data("anchor-v1".utf8))
            anchorExp.fulfill()
        }
        await fulfillment(of: [anchorExp], timeout: 5)
    }
}
