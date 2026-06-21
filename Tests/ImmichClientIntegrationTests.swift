import XCTest

// Live, read-only integration tests for the API client. They hit a real Immich
// server, so they are gated on environment variables and skip cleanly when the
// server isn't configured — the key is never baked into the repo. Run with:
//
//   set -a; source .env.local; set +a
//   xcodebuild test -scheme ImmichDriveTests -destination 'platform=macOS' \
//     CODE_SIGNING_ALLOWED=NO -only-testing:ImmichDriveTests/ImmichClientIntegrationTests
//
// Everything here is read-only: no asset, album, tag, or favorite is mutated.
final class ImmichClientIntegrationTests: IntegrationTestCase {
    func testAuthAndListAlbums() async throws {
        let albums = try await client.listAlbums()
        XCTAssertFalse(albums.isEmpty, "a valid key should see at least one album")
        let first = try XCTUnwrap(albums.first)
        XCTAssertFalse(first.albumID.isEmpty)
        XCTAssertFalse(first.albumName.isEmpty)
    }

    // Paginated album enumeration must return exactly assetCount items, each
    // carrying exif (withExif) so the Finder can show file sizes.
    func testAlbumPaginationMatchesCount() async throws {
        let albums = try await client.listAlbums()
        let album = try XCTUnwrap(albums.max(by: { $0.assetCount < $1.assetCount }))
        let assets = try await client.searchAllAlbum(albumID: album.albumID)
        XCTAssertEqual(assets.count, album.assetCount)
        if let first = assets.first {
            XCTAssertNotNil(first.exifInfo?.fileSizeInByte, "withExif should populate file size")
        }
    }

    func testTimelineYearRange() async throws {
        let range = try await client.assetYearRange()
        let r = try XCTUnwrap(range, "a non-empty library should have a year range")
        XCTAssertLessThanOrEqual(r.oldest, r.newest)
    }

    func testListTags() async throws {
        let tags = try await client.listTags()
        XCTAssertFalse(tags.isEmpty)
    }

    func testListCitiesHaveCountryAndCity() async throws {
        let places = try await client.listCities()
        XCTAssertFalse(places.isEmpty)
        for place in places {
            XCTAssertFalse(place.country.isEmpty)
            XCTAssertFalse(place.city.isEmpty)
        }
    }

    func testListPeopleReturnsOnlyNamed() async throws {
        // May be empty when nobody is named, but anyone returned must be named.
        for person in try await client.listPeople() {
            XCTAssertFalse((person.name ?? "").isEmpty)
        }
    }

    func testSearchAllCityReturnsAssets() async throws {
        let places = try await client.listCities()
        let place = try XCTUnwrap(places.first)
        let assets = try await client.searchAllCity(country: place.country, city: place.city)
        XCTAssertFalse(assets.isEmpty, "the city's representative asset should be findable")
    }

    func testSearchAllTagReturnsAssets() async throws {
        let tags = try await client.listTags()
        for tag in tags.prefix(25) {
            let assets = try await client.searchAllTag(tagID: tag.id)
            if assets.isEmpty == false {
                XCTAssertFalse(try XCTUnwrap(assets.first).assetID.isEmpty)
                return
            }
        }
        throw XCTSkip("no tag with assets found in the first 25 tags")
    }

    func testDownloadOriginalAndThumbnail() async throws {
        let albums = try await client.listAlbums()
        let album = try XCTUnwrap(albums.first(where: { $0.assetCount > 0 }))
        let assets = try await client.searchAllAlbum(albumID: album.albumID)
        let asset = try XCTUnwrap(assets.first)
        let original = try await client.downloadOriginal(assetID: asset.assetID)
        XCTAssertGreaterThan(original.count, 0)
        let thumbnail = try await client.downloadThumbnail(assetID: asset.assetID, size: nil)
        XCTAssertGreaterThan(thumbnail.count, 0)
    }
}
