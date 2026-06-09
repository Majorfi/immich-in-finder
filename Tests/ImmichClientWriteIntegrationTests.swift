import XCTest

// Live, MUTATING integration tests. Same env gate as the read tests. Everything
// created is torn down afterwards (even on failure) so the server is left as it
// was found: test albums are deleted and test assets are permanently purged.
// Uploads are tiny 1x1 PNGs made unique per test so they never collide with
// real library assets by checksum.
final class ImmichClientWriteIntegrationTests: XCTestCase {
    private var client: ImmichClient!
    private var albumsToDelete: [String] = []
    private var assetsToPurge: [String] = []
    private var tempFiles: [URL] = []

    // 1x1 PNG; trailing bytes are appended per-test to make the checksum unique.
    private static let basePNG = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==")!

    nonisolated(unsafe) private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    override func setUpWithError() throws {
        let env = ProcessInfo.processInfo.environment
        guard let base = env["IMMICH_BASE_URL"], let key = env["IMMICH_API_KEY"],
              let url = URL(string: base), key.isEmpty == false else {
            throw XCTSkip("Set IMMICH_BASE_URL and IMMICH_API_KEY to run live API tests")
        }
        client = ImmichClient(baseURL: url, apiKey: key)
    }

    override func tearDown() async throws {
        guard let client else { return }
        if assetsToPurge.isEmpty == false {
            try? await client.deleteAssetsPermanently(assetIDs: assetsToPurge)
        }
        for id in albumsToDelete {
            try? await client.deleteAlbum(id: id)
        }
        for url in tempFiles { try? FileManager.default.removeItem(at: url) }
        albumsToDelete = []
        assetsToPurge = []
        tempFiles = []
    }

    // A temp file holding a per-test-unique 1x1 PNG, so its checksum never
    // collides with real library assets.
    private func uniqueFile(_ tag: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try (Self.basePNG + Data(tag.utf8)).write(to: url)
        tempFiles.append(url)
        return url
    }

    // Exercises the full write surface the extension uses: create album, upload,
    // add, move (add+remove), rename, trash.
    func testUploadAddMoveRenameTrash() async throws {
        let tag = String(UUID().uuidString.prefix(8))
        let now = Self.isoFormatter.string(from: Date())

        let albumA = try await client.createAlbum(name: "FPTest A \(tag)")
        albumsToDelete.append(albumA.albumID)
        let albumB = try await client.createAlbum(name: "FPTest B \(tag)")
        albumsToDelete.append(albumB.albumID)

        let upload = try await client.uploadAsset(filename: "fptest-\(tag).png", fileURL: try uniqueFile(tag), createdAt: now, modifiedAt: now)
        assetsToPurge.append(upload.id)
        XCTAssertFalse(upload.isDuplicate)

        try await client.addAssets(albumID: albumA.albumID, assetIDs: [upload.id])
        let inA = try await client.searchAllAlbum(albumID: albumA.albumID)
        XCTAssertTrue(inA.contains { $0.assetID == upload.id }, "uploaded asset should be in album A")

        // Move A -> B (add to dest, remove from source).
        try await client.addAssets(albumID: albumB.albumID, assetIDs: [upload.id])
        try await client.removeAssets(albumID: albumA.albumID, assetIDs: [upload.id])
        let aAfter = try await client.searchAllAlbum(albumID: albumA.albumID)
        let bAfter = try await client.searchAllAlbum(albumID: albumB.albumID)
        XCTAssertFalse(aAfter.contains { $0.assetID == upload.id }, "asset should be gone from A")
        XCTAssertTrue(bAfter.contains { $0.assetID == upload.id }, "asset should be present in B")

        let newName = "FPTest Renamed \(tag)"
        let renamed = try await client.renameAlbum(id: albumB.albumID, name: newName)
        XCTAssertEqual(renamed.albumName, newName)

        // Trash = recoverable delete; the asset leaves every album view.
        try await client.trashAssets(assetIDs: [upload.id])
        let bAfterTrash = try await client.searchAllAlbum(albumID: albumB.albumID)
        XCTAssertFalse(bAfterTrash.contains { $0.assetID == upload.id }, "trashed asset should leave the album")
    }

    // Immich dedups by checksum: re-uploading the same bytes returns the
    // existing asset's id with a duplicate flag, which the extension relies on
    // to still link a dropped duplicate into the target album.
    func testDuplicateUploadReportsExistingAsset() async throws {
        let tag = String(UUID().uuidString.prefix(8))
        let now = Self.isoFormatter.string(from: Date())
        let file = try uniqueFile(tag) // same bytes reused for both uploads

        let first = try await client.uploadAsset(filename: "dup-\(tag).png", fileURL: file, createdAt: now, modifiedAt: now)
        assetsToPurge.append(first.id)
        XCTAssertFalse(first.isDuplicate, "first upload of fresh bytes is not a duplicate")

        let second = try await client.uploadAsset(filename: "dup2-\(tag).png", fileURL: file, createdAt: now, modifiedAt: now)
        XCTAssertTrue(second.isDuplicate, "identical bytes should be reported as a duplicate")
        XCTAssertEqual(second.id, first.id, "a duplicate resolves to the existing asset id")
    }
}
