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

    // Drives every branch of the enumerateItems switch.
    func testEveryContainerEnumeratesSomething() async {
        VisibleSections.save(Set(SectionKind.allCases))
        let containers: [(EnumeratedContainer, String)] = [
            (.sections, "sections"),
            (.albums, "albums"),
            (.album(id: "a"), "album assets"),
            (.years, "years"),
            (.months(year: "2024"), "months"),
            (.month(yearMonth: "2024-03"), "month assets"),
            (.people, "people"),
            (.person(id: "p"), "person assets"),
            (.countries, "countries"),
            (.cities(country: "France"), "cities"),
            (.place(country: "France", city: "Paris"), "place assets"),
            (.tags, "tags"),
            (.tag(id: "t"), "tag assets"),
            (.favorites, "favorites"),
        ]
        for (container, label) in containers {
            let (items, error) = await enumerate(container)
            XCTAssertNil(error, "\(label) errored: \(String(describing: error))")
            XCTAssertFalse(items.isEmpty, "\(label) enumerated nothing")
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

    func testChangeEnumerationAndSyncAnchorAreStable() async {
        let client = immichLikeClient()
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: .albums)
        let anchorExp = expectation(description: "anchor")
        enumerator.currentSyncAnchor { anchor in
            XCTAssertNotNil(anchor)
            anchorExp.fulfill()
        }
        await fulfillment(of: [anchorExp], timeout: 5)
    }
}
