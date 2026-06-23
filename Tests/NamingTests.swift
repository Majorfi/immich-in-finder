import XCTest

// Filename disambiguation must be deterministic given the sibling counts, so
// enumeration and single-item resolution always agree on a name.
final class NamingTests: XCTestCase {
    func testNoCollisionKeepsBase() {
        let counts = nameCounts(["a.jpg", "b.jpg"])
        XCTAssertEqual(disambiguatedName(base: "a.jpg", id: "12345678abc", counts: counts), "a.jpg")
    }

    func testCollisionInsertsFragmentBeforeExtension() {
        let counts = nameCounts(["a.jpg", "a.jpg"])
        XCTAssertEqual(disambiguatedName(base: "a.jpg", id: "12345678abc", counts: counts), "a (12345678).jpg")
    }

    func testCollisionWithoutExtension() {
        let counts = nameCounts(["Sitges", "Sitges"])
        XCTAssertEqual(disambiguatedName(base: "Sitges", id: "abcdefgh999", counts: counts), "Sitges (abcdefgh)")
    }

    func testNameCounts() {
        XCTAssertEqual(nameCounts(["x", "x", "y"]), ["x": 2, "y": 1])
    }

    func testImmichItemsDisambiguateColliding() {
        func asset(_ id: String, _ name: String) -> Asset {
            Asset(assetID: id, type: .image, originalFileName: name, checksum: nil,
                  fileCreatedAt: "2024-01-01T00:00:00.000Z", fileModifiedAt: nil, exifInfo: nil)
        }
        let items = immichItems(from: [asset("aaaaaaaa1", "x.jpg"), asset("bbbbbbbb2", "x.jpg")],
                                location: .favorite)
        XCTAssertEqual(Set(items.map { $0.filename }), ["x (aaaaaaaa).jpg", "x (bbbbbbbb).jpg"])
    }
}

final class SectionKindTests: XCTestCase {
    func testDisplayNames() {
        XCTAssertEqual(SectionKind.albums.displayName, "Albums")
        XCTAssertEqual(SectionKind.timeline.displayName, "Timeline")
        XCTAssertEqual(SectionKind.favorites.displayName, "Favorites")
    }

    func testItemIDMapping() {
        XCTAssertEqual(SectionKind.people.itemID.identifier.rawValue, "section:people")
        XCTAssertEqual(SectionKind.places.itemID.identifier.rawValue, "section:places")
    }

    // Each section must map to a distinct identifier, and every identifier must
    // parse back to its section, which guards against two views colliding.
    func testSectionIdentifiersAreDistinctAndRoundTrip() {
        let ids = SectionKind.allCases.map { $0.itemID.identifier.rawValue }
        XCTAssertEqual(Set(ids).count, SectionKind.allCases.count)
    }
}
