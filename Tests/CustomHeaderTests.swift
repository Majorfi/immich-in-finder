import XCTest

final class CustomHeaderTests: XCTestCase {
    func testAsRequestHeadersDropsEmptyNames() {
        let headers = [
            CustomHeader(name: "   ", value: "ignored"),
            CustomHeader(name: "X-Real", value: "1")
        ]
        XCTAssertEqual(headers.asRequestHeaders, ["X-Real": "1"])
    }

    func testAsRequestHeadersTrimsWhitespace() {
        let headers = [CustomHeader(name: "  CF-Access-Client-Id ", value: " tok\n")]
        XCTAssertEqual(headers.asRequestHeaders, ["CF-Access-Client-Id": "tok"])
    }

    func testAsRequestHeadersLaterDuplicateWins() {
        let headers = [CustomHeader(name: "X", value: "first"), CustomHeader(name: "X", value: "second")]
        XCTAssertEqual(headers.asRequestHeaders, ["X": "second"])
    }

    // Two rows with identical name/value are equal despite distinct rowIDs, so a
    // reload (which mints fresh rowIDs) never reads as a credential change.
    func testEqualityIgnoresRowIdentity() {
        XCTAssertEqual(CustomHeader(name: "X", value: "1"), CustomHeader(name: "X", value: "1"))
    }
}
