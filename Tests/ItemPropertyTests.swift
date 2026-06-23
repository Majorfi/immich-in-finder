import XCTest
import FileProvider
import UniformTypeIdentifiers

// Every NSFileProviderItem the extension hands the system, exercising the
// property getters (filename, contentType, capabilities, version, sizes, dates).
final class ItemPropertyTests: XCTestCase {
    private func asset(id: String = "a", type: AssetType = .image, name: String = "f.jpg",
                       checksum: String? = "ck", created: String = "2024-01-01T00:00:00.000Z",
                       modified: String? = "2024-01-02T00:00:00.000Z", size: Int64? = 100) -> Asset {
        Asset(assetID: id, type: type, originalFileName: name, checksum: checksum,
              fileCreatedAt: created, fileModifiedAt: modified,
              exifInfo: size.map { ExifInfo(fileSizeInByte: $0, city: nil, country: nil) })
    }

    func testImmichItemCore() {
        let item = ImmichItem(asset: asset(), location: .album(id: "AL"), filename: "f.jpg")
        XCTAssertEqual(item.itemIdentifier.rawValue, "asset:AL:a")
        XCTAssertEqual(item.parentItemIdentifier.rawValue, "album:AL")
        XCTAssertEqual(item.filename, "f.jpg")
        XCTAssertTrue(item.contentType.conforms(to: .image))
        XCTAssertEqual(item.documentSize, NSNumber(value: 100))
        XCTAssertNotNil(item.creationDate)
        XCTAssertNotNil(item.contentModificationDate)
    }

    func testImmichItemCapabilitiesByLocation() {
        let album = ImmichItem(asset: asset(), location: .album(id: "x"), filename: "f")
        XCTAssertTrue(album.capabilities.contains(.allowsReparenting))
        let person = ImmichItem(asset: asset(), location: .person(id: "p"), filename: "f")
        XCTAssertFalse(person.capabilities.contains(.allowsReparenting))
        XCTAssertTrue(person.capabilities.contains(.allowsDeleting))
    }

    func testImmichItemContentTypeFallsBackToAssetType() {
        let video = ImmichItem(asset: asset(type: .video, name: "noext"), location: .favorite, filename: "noext")
        XCTAssertTrue(video.contentType.conforms(to: .movie))
    }

    func testImmichItemMissingExifAndDates() {
        let item = ImmichItem(asset: asset(checksum: nil, modified: nil, size: nil), location: .favorite, filename: "f")
        XCTAssertNil(item.documentSize)
        XCTAssertNil(item.contentModificationDate)
        // itemVersion falls back to the asset id when there's no checksum.
        XCTAssertFalse(item.itemVersion.contentVersion.isEmpty)
    }

    func testParseDateBothFormats() {
        XCTAssertNotNil(ImmichItem.parseDate("2024-01-01T00:00:00.000Z"))
        XCTAssertNotNil(ImmichItem.parseDate("2024-01-01T00:00:00Z"))
        XCTAssertNil(ImmichItem.parseDate("not a date"))
    }

    func testSectionItem() {
        let albums = SectionItem(kind: .albums)
        XCTAssertEqual(albums.itemIdentifier.rawValue, "section:albums")
        XCTAssertEqual(albums.parentItemIdentifier, .rootContainer)
        XCTAssertEqual(albums.filename, "Albums")
        XCTAssertTrue(albums.capabilities.contains(.allowsAddingSubItems))
        XCTAssertFalse(SectionItem(kind: .timeline).capabilities.contains(.allowsAddingSubItems))
    }

    func testFolderItem() {
        let item = FolderItem(id: .person("P"), parent: .peopleSection, filename: "Alice")
        XCTAssertEqual(item.itemIdentifier.rawValue, "person:P")
        XCTAssertEqual(item.parentItemIdentifier.rawValue, "section:people")
        XCTAssertEqual(item.filename, "Alice")
        XCTAssertEqual(item.contentType, .folder)
        XCTAssertTrue(item.capabilities.contains(.allowsContentEnumerating))
    }

    func testAlbumItem() {
        let item = AlbumItem(album: AlbumSummary(albumID: "AL", albumName: "Trip", assetCount: 7), filename: "Trip")
        XCTAssertEqual(item.itemIdentifier.rawValue, "album:AL")
        XCTAssertEqual(item.parentItemIdentifier.rawValue, "section:albums")
        XCTAssertEqual(item.childItemCount, NSNumber(value: 7))
        XCTAssertTrue(item.capabilities.contains(.allowsRenaming))
    }

    func testYearAndMonthItems() {
        let year = YearItem(year: "2024")
        XCTAssertEqual(year.itemIdentifier.rawValue, "year:2024")
        XCTAssertEqual(year.parentItemIdentifier.rawValue, "section:timeline")
        XCTAssertEqual(year.filename, "2024")

        let month = MonthItem(yearMonth: "2024-03")
        XCTAssertEqual(month.itemIdentifier.rawValue, "month:2024-03")
        XCTAssertEqual(month.parentItemIdentifier.rawValue, "year:2024")
        XCTAssertTrue(month.filename.hasPrefix("03 - "), "got \(month.filename)")
    }

    func testRootItem() {
        let root = RootItem()
        XCTAssertEqual(root.itemIdentifier, .rootContainer)
        XCTAssertEqual(root.parentItemIdentifier, .rootContainer)
        XCTAssertEqual(root.contentType, .folder)
        XCTAssertFalse(root.filename.isEmpty)
    }
}
