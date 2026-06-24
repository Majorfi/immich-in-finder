import XCTest

// The models map Immich's JSON (id -> assetID, etc.) and tolerate missing
// optional fields. These fixtures pin the wire contract so a server-shape
// surprise fails here rather than silently in the Finder.
final class ModelDecodingTests: XCTestCase {
    private let decoder = JSONDecoder()

    func testAssetFullDecoding() throws {
        let json = Data("""
        {"id":"abc","type":"IMAGE","originalFileName":"x.jpg","checksum":"ck",
         "fileCreatedAt":"2024-01-01T00:00:00.000Z","fileModifiedAt":"2024-01-02T00:00:00.000Z",
         "exifInfo":{"fileSizeInByte":123,"city":"Paris","country":"France","state":"IDF"}}
        """.utf8)
        let asset = try decoder.decode(Asset.self, from: json)
        XCTAssertEqual(asset.assetID, "abc")
        XCTAssertEqual(asset.type, .image)
        XCTAssertEqual(asset.originalFileName, "x.jpg")
        XCTAssertEqual(asset.checksum, "ck")
        XCTAssertEqual(asset.exifInfo?.fileSizeInByte, 123)
        XCTAssertEqual(asset.exifInfo?.city, "Paris")
        XCTAssertEqual(asset.exifInfo?.country, "France")
    }

    func testAssetToleratesMissingOptionals() throws {
        let json = Data(#"{"id":"x","type":"VIDEO","originalFileName":"v.mp4","fileCreatedAt":"2024-01-01T00:00:00.000Z"}"#.utf8)
        let asset = try decoder.decode(Asset.self, from: json)
        XCTAssertEqual(asset.type, .video)
        XCTAssertNil(asset.checksum)
        XCTAssertNil(asset.fileModifiedAt)
        XCTAssertNil(asset.exifInfo)
    }

    func testUnknownAssetTypeIsNotImage() throws {
        // OTHER maps explicitly; an unexpected enum value would throw, which we
        // want to know about, so assert the known mapping holds.
        let json = Data(#"{"id":"x","type":"OTHER","originalFileName":"f","fileCreatedAt":"2024-01-01T00:00:00.000Z"}"#.utf8)
        XCTAssertEqual(try decoder.decode(Asset.self, from: json).type, .other)
    }

    func testAlbumSummary() throws {
        let json = Data(#"{"id":"al","albumName":"Trip","assetCount":42}"#.utf8)
        let s = try decoder.decode(AlbumSummary.self, from: json)
        XCTAssertEqual(s.albumID, "al")
        XCTAssertEqual(s.albumName, "Trip")
        XCTAssertEqual(s.assetCount, 42)
    }

    func testPersonSummary() throws {
        let json = Data(#"{"id":"p","name":"Alice","isHidden":false}"#.utf8)
        let p = try decoder.decode(PersonSummary.self, from: json)
        XCTAssertEqual(p.personID, "p")
        XCTAssertEqual(p.name, "Alice")
        XCTAssertEqual(p.isHidden, false)
    }

    func testTagSummary() throws {
        let json = Data(#"{"id":"t","name":"2020","value":"2020","parentId":null}"#.utf8)
        let t = try decoder.decode(TagSummary.self, from: json)
        XCTAssertEqual(t.tagID, "t")
        XCTAssertEqual(t.name, "2020")
    }

    func testSearchResponsePagination() throws {
        let json = Data("""
        {"assets":{"items":[{"id":"a","type":"IMAGE","originalFileName":"x.jpg","fileCreatedAt":"2024-01-01T00:00:00.000Z"}],"nextPage":"2"}}
        """.utf8)
        let r = try decoder.decode(SearchResponse.self, from: json)
        XCTAssertEqual(r.assets.items.count, 1)
        XCTAssertEqual(r.assets.nextPage, "2")
    }

    func testPeopleResponse() throws {
        let json = Data(#"{"people":[{"id":"p","name":"","isHidden":false}],"hasNextPage":true,"total":1,"hidden":0}"#.utf8)
        let r = try decoder.decode(PeopleResponse.self, from: json)
        XCTAssertEqual(r.people.count, 1)
        XCTAssertEqual(r.hasNextPage, true)
    }
}

final class MonthBoundsTests: XCTestCase {
    func testMidYear() {
        let bounds = ImmichClient.monthBounds("2024-03")
        XCTAssertEqual(bounds.after, "2024-03-01T00:00:00.000Z")
        XCTAssertEqual(bounds.before, "2024-04-01T00:00:00.000Z")
    }

    func testDecemberRollsOverToNextYear() {
        let bounds = ImmichClient.monthBounds("2024-12")
        XCTAssertEqual(bounds.after, "2024-12-01T00:00:00.000Z")
        XCTAssertEqual(bounds.before, "2025-01-01T00:00:00.000Z")
    }
}
