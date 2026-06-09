import XCTest
import FileProvider

// The identifier grammar is the spine of the whole extension: enumeration,
// item resolution, parenting and cache keys all flow through it. These tests
// pin construction ↔ parsing so a future edit can't make the two halves drift.
final class ItemIDTests: XCTestCase {
    private let allShapes = [
        "section:albums", "section:timeline", "section:people",
        "section:places", "section:tags", "section:favorites",
        "album:abc-123", "year:2024", "month:2024-03",
        "person:p-9", "country:France", "city:France:Paris", "tag:t-1",
        "asset:alb:ast", "tasset:2024-03:ast", "passet:p-9:ast",
        "qasset:France:Paris:ast", "tagasset:t-1:ast", "fasset:ast",
    ]

    func testEveryIdentifierRoundTrips() {
        for raw in allShapes {
            let rebuilt = ItemID(NSFileProviderItemIdentifier(rawValue: raw)).identifier.rawValue
            XCTAssertEqual(rebuilt, raw, "round-trip failed for \(raw)")
        }
    }

    func testRootContainer() {
        XCTAssertEqual(ItemID(.rootContainer).identifier, .rootContainer)
    }

    // The place-asset parser pins country first and the asset id last so a city
    // name containing colons still survives the round-trip.
    func testCityNameWithColonsRoundTrips() {
        let raw = "qasset:X:weird:city:name:ast"
        let rebuilt = ItemID(NSFileProviderItemIdentifier(rawValue: raw)).identifier.rawValue
        XCTAssertEqual(rebuilt, raw)
    }

    func testUnknownIdentifierIsOther() {
        guard case .other = ItemID(NSFileProviderItemIdentifier(rawValue: "nonsense")) else {
            return XCTFail("unknown identifier should parse to .other")
        }
    }

    func testAssetRefCarriesLocation() {
        let ref = ItemID(NSFileProviderItemIdentifier(rawValue: "tasset:2024-03:AST")).assetRef
        XCTAssertEqual(ref?.assetID, "AST")
        guard case .month(let yearMonth)? = ref?.location else {
            return XCTFail("expected a month location")
        }
        XCTAssertEqual(yearMonth, "2024-03")
    }

    func testFolderAndSectionHaveNoAssetRef() {
        XCTAssertNil(ItemID(NSFileProviderItemIdentifier(rawValue: "album:a")).assetRef)
        XCTAssertNil(ItemID(NSFileProviderItemIdentifier(rawValue: "section:people")).assetRef)
    }
}

final class AssetLocationTests: XCTestCase {
    private let all: [AssetLocation] = [
        .album(id: "a"), .month(yearMonth: "2024-03"), .person(id: "p"),
        .place(country: "FR", city: "Paris"), .tag(id: "t"), .favorite,
    ]

    func testCacheKeys() {
        XCTAssertEqual(AssetLocation.album(id: "a").cacheKey, "album:a")
        XCTAssertEqual(AssetLocation.month(yearMonth: "2024-03").cacheKey, "month:2024-03")
        XCTAssertEqual(AssetLocation.person(id: "p").cacheKey, "person:p")
        XCTAssertEqual(AssetLocation.place(country: "FR", city: "Paris").cacheKey, "place:FR:Paris")
        XCTAssertEqual(AssetLocation.tag(id: "t").cacheKey, "tag:t")
        XCTAssertEqual(AssetLocation.favorite.cacheKey, "favorites")
    }

    // assetItemID(_:) must produce an identifier that parses back to the same
    // location — this is what keeps an item's identity stable across the
    // build (ImmichItem) and parse (ItemID) sides.
    func testAssetItemIDParsesBackToSameLocation() {
        for location in all {
            let parsed = ItemID(location.assetItemID("AST").identifier).assetRef
            XCTAssertEqual(parsed?.assetID, "AST")
            XCTAssertEqual(parsed?.location.cacheKey, location.cacheKey)
        }
    }

    func testParentItemID() {
        XCTAssertEqual(AssetLocation.album(id: "a").parentItemID.identifier.rawValue, "album:a")
        XCTAssertEqual(AssetLocation.place(country: "FR", city: "Paris").parentItemID.identifier.rawValue, "city:FR:Paris")
        // Favorites assets are direct children of the section — no folder level.
        XCTAssertEqual(AssetLocation.favorite.parentItemID.identifier.rawValue, "section:favorites")
    }
}
