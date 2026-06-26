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

    // HTTP header names are case-insensitive, so rows differing only by case
    // collapse to one entry deterministically: the last-entered row wins and
    // keeps its own casing.
    func testAsRequestHeadersDedupesCaseInsensitively() {
        let headers = [CustomHeader(name: "X-Foo", value: "first"), CustomHeader(name: "x-foo", value: "second")]
        XCTAssertEqual(headers.asRequestHeaders, ["x-foo": "second"])
    }

    // Two rows with identical name/value are equal despite distinct rowIDs, so a
    // reload (which mints fresh rowIDs) never reads as a credential change.
    func testEqualityIgnoresRowIdentity() {
        XCTAssertEqual(CustomHeader(name: "X", value: "1"), CustomHeader(name: "X", value: "1"))
    }
}
