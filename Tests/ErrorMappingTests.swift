import XCTest
import FileProvider

final class ErrorMappingTests: XCTestCase {
    private func mappedCode(_ error: Error) -> Int? {
        let ns = fileProviderError(from: error) as NSError
        return if ns.domain == NSFileProviderErrorDomain { ns.code } else { nil }
    }

    func testHTTPStatusesMapToFileProviderCodes() {
        XCTAssertEqual(mappedCode(ImmichError.httpStatus(path: "/x", code: 401)), NSFileProviderError.notAuthenticated.rawValue)
        XCTAssertEqual(mappedCode(ImmichError.httpStatus(path: "/x", code: 403)), NSFileProviderError.notAuthenticated.rawValue)
        XCTAssertEqual(mappedCode(ImmichError.httpStatus(path: "/x", code: 404)), NSFileProviderError.noSuchItem.rawValue)
        XCTAssertEqual(mappedCode(ImmichError.httpStatus(path: "/x", code: 413)), NSFileProviderError.insufficientQuota.rawValue)
        XCTAssertEqual(mappedCode(ImmichError.httpStatus(path: "/x", code: 507)), NSFileProviderError.insufficientQuota.rawValue)
    }

    func testUnmappedStatusPassesThrough() {
        // 500 isn't a known mapping; the original error is returned unchanged.
        XCTAssertNil(mappedCode(ImmichError.httpStatus(path: "/x", code: 500)))
    }

    func testNetworkErrorsMapToServerUnreachable() {
        for code: URLError.Code in [.notConnectedToInternet, .cannotConnectToHost, .timedOut, .networkConnectionLost, .dnsLookupFailed] {
            XCTAssertEqual(mappedCode(URLError(code)), NSFileProviderError.serverUnreachable.rawValue, "\(code)")
        }
    }

    func testUnknownErrorPassesThrough() {
        let original = ImmichError.badURL("nope")
        XCTAssertNil(mappedCode(original), "unknown errors should not be rewritten")
    }

    // End-to-end through the enumerator: a 401 surfaces as notAuthenticated.
    func testEnumerationErrorIsMapped() async {
        let client = MockClient.make(status: 401, json: "{}")
        let enumerator = ItemEnumerator(client: client, cache: ImmichCache(client: client), container: .albums)
        let observer = MockEnumObserver()
        enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage(Data()))
        await fulfillment(of: [observer.done], timeout: 10)
        let nsError = observer.error as? NSError
        XCTAssertEqual(nsError?.domain, NSFileProviderErrorDomain)
        XCTAssertEqual(nsError?.code, NSFileProviderError.notAuthenticated.rawValue)
    }
}
