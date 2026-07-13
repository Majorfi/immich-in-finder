import XCTest

// The filename source picks which of an asset's two names Finder shows, falling
// back to the upload name whenever the storage path can't yield one.
final class FilenameSourceTests: XCTestCase {
    private func asset(name: String, path: String?) -> Asset {
        Asset(assetID: "a", type: .image, originalFileName: name, originalPath: path, checksum: nil,
              fileCreatedAt: "2024-01-01T00:00:00.000Z", fileModifiedAt: nil, exifInfo: nil)
    }

    func testOriginalNameUsesUploadName() {
        let a = asset(name: "IMG_1.jpg", path: "/data/library/2024/renamed.jpg")
        XCTAssertEqual(FilenameSource.originalName.baseName(for: a), "IMG_1.jpg")
    }

    func testStoragePathUsesFinalPathComponent() {
        let a = asset(name: "IMG_1.jpg", path: "/data/library/2024/2024-03-15_IMG_1.jpg")
        XCTAssertEqual(FilenameSource.storagePath.baseName(for: a), "2024-03-15_IMG_1.jpg")
    }

    func testStoragePathFallsBackWhenPathMissing() {
        XCTAssertEqual(FilenameSource.storagePath.baseName(for: asset(name: "IMG_1.jpg", path: nil)), "IMG_1.jpg")
    }

    func testStoragePathFallsBackWhenPathEmpty() {
        XCTAssertEqual(FilenameSource.storagePath.baseName(for: asset(name: "IMG_1.jpg", path: "")), "IMG_1.jpg")
    }

    func testDecodesOriginalPath() throws {
        let json = Data(#"{"id":"x","type":"IMAGE","originalFileName":"f.jpg","originalPath":"/srv/upload/2024/f.jpg","fileCreatedAt":"2024-01-01T00:00:00.000Z"}"#.utf8)
        let asset = try JSONDecoder().decode(Asset.self, from: json)
        XCTAssertEqual(asset.originalPath, "/srv/upload/2024/f.jpg")
    }

    func testMissingOriginalPathDecodesToNil() throws {
        let json = Data(#"{"id":"x","type":"IMAGE","originalFileName":"f.jpg","fileCreatedAt":"2024-01-01T00:00:00.000Z"}"#.utf8)
        let asset = try JSONDecoder().decode(Asset.self, from: json)
        XCTAssertNil(asset.originalPath)
    }

    func testRoundTripThroughAppGroupDefaults() {
        let original = FilenameSource.load()
        defer { FilenameSource.save(original) }
        FilenameSource.save(.storagePath)
        XCTAssertEqual(FilenameSource.load(), .storagePath)
    }

    func testDefaultsToOriginalNameWhenUnset() {
        let original = FilenameSource.load()
        defer { FilenameSource.save(original) }
        AppGroup.defaults?.removeObject(forKey: AppGroup.DefaultsKey.filenameSource)
        XCTAssertEqual(FilenameSource.load(), .originalName)
    }

    // The naming chokepoint must honor the stored source, so enumeration renames
    // files by the storage path when that is chosen.
    func testImmichItemsUseStoragePathWhenChosen() {
        let original = FilenameSource.load()
        defer { FilenameSource.save(original) }
        FilenameSource.save(.storagePath)
        let items = immichItems(from: [asset(name: "IMG_1.jpg", path: "/data/2024/vacation-01.jpg")], location: .favorite)
        XCTAssertEqual(items.first?.filename, "vacation-01.jpg")
    }
}
