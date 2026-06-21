import XCTest
import FileProvider
import UniformTypeIdentifiers

// A minimal NSFileProviderItem for create/modify templates.
final class TemplateItem: NSObject, NSFileProviderItem {
    let itemIdentifier: NSFileProviderItemIdentifier
    let parentItemIdentifier: NSFileProviderItemIdentifier
    let filename: String
    let contentType: UTType
    init(id: String = "temp", parent: String, filename: String, contentType: UTType) {
        self.itemIdentifier = NSFileProviderItemIdentifier(rawValue: id)
        self.parentItemIdentifier = NSFileProviderItemIdentifier(rawValue: parent)
        self.filename = filename
        self.contentType = contentType
    }
}

// Sendable snapshot of a completion result — NSFileProviderItem/Error can't
// cross a continuation under Swift 6, so the completions extract what we assert.
private struct Outcome: Sendable {
    let filename: String?
    let error: String?
    var ok: Bool { error == nil }
}

// Drives the extension's protocol methods with an injected mock client, so the
// real create/modify/delete/fetch flows run with no server or Finder.
final class FileProviderExtensionTests: XCTestCase {
    private let domain = NSFileProviderDomain(identifier: .init(rawValue: "test"), displayName: "Test")
    private let request = NSFileProviderRequest()

    override func tearDown() { MockURLProtocol.handler = nil }

    private func mockClient() -> ImmichClient {
        let asset = Fixtures.assetJSON()
        return MockClient.make { req in
            let path = req.url?.path ?? ""
            let method = req.httpMethod ?? "GET"
            switch (path, method) {
            case ("/api/albums", "GET"): return (200, Data(#"[{"id":"a","albumName":"Trip","assetCount":1}]"#.utf8))
            case ("/api/albums", "POST"): return (200, Data(#"{"id":"newAL","albumName":"New","assetCount":0}"#.utf8))
            case ("/api/assets", "POST"): return (200, Data(#"{"id":"x","status":"created"}"#.utf8))
            case ("/api/search/metadata", _): return (200, Data("{\"assets\":{\"items\":[\(asset)],\"nextPage\":null}}".utf8))
            case ("/api/people", _): return (200, Data(#"{"people":[{"id":"p","name":"Al","isHidden":false}],"hasNextPage":false}"#.utf8))
            case ("/api/search/cities", _): return (200, Data("[]".utf8))
            case ("/api/tags", _): return (200, Data(#"[{"id":"t","name":"T","value":"T"}]"#.utf8))
            default:
                if path.hasSuffix("/original") || path.hasSuffix("/thumbnail") { return (200, Data([0xFF, 0xD8])) }
                if path.hasPrefix("/api/albums/") && method == "PATCH" { return (200, Data(#"{"id":"a","albumName":"Renamed","assetCount":0}"#.utf8)) }
                return (200, Data("".utf8)) // album/asset mutations: 200, no body
            }
        }
    }

    private func makeExtension() -> FileProviderExtension {
        let client = mockClient()
        return FileProviderExtension(domain: domain, client: client, cache: ImmichCache(client: client))
    }

    private func id(_ raw: String) -> NSFileProviderItemIdentifier { .init(rawValue: raw) }

    // MARK: item(for:)

    private func item(_ ext: FileProviderExtension, _ raw: String) async -> Outcome {
        await withCheckedContinuation { cont in
            _ = ext.item(for: id(raw), request: request) { item, error in
                cont.resume(returning: Outcome(filename: item?.filename, error: error.map { String(describing: $0) }))
            }
        }
    }

    func testItemForSynchronousContainers() async {
        let ext = makeExtension()
        for raw in ["section:albums", "section:timeline", "section:people", "section:places",
                    "section:tags", "section:favorites", "year:2024", "month:2024-03",
                    "country:France", "city:France:Paris", NSFileProviderItemIdentifier.rootContainer.rawValue] {
            let outcome = await item(ext, raw)
            XCTAssertTrue(outcome.ok, "\(raw) errored")
            XCTAssertNotNil(outcome.filename, "\(raw) returned no item")
        }
    }

    func testItemForAlbumPersonTagAndAsset() async {
        let ext = makeExtension()
        let expected = ["album:a": "Trip", "person:p": "Al", "tag:t": "T", "asset:a:x": "f.jpg"]
        for (raw, filename) in expected {
            let outcome = await item(ext, raw)
            XCTAssertTrue(outcome.ok, "\(raw) errored: \(outcome.error ?? "")")
            XCTAssertEqual(outcome.filename, filename, "\(raw)")
        }
    }

    // MARK: enumerator(for:)

    func testEnumeratorForEveryContainer() {
        let ext = makeExtension()
        for raw in ["section:albums", "section:timeline", "section:people", "section:places",
                    "section:tags", "section:favorites", "album:a", "year:2024", "month:2024-03",
                    "person:p", "country:France", "city:France:Paris", "tag:t",
                    NSFileProviderItemIdentifier.rootContainer.rawValue] {
            XCTAssertNoThrow(try ext.enumerator(for: id(raw), request: request))
        }
    }

    // MARK: fetchContents

    func testFetchContentsDownloadsAsset() async {
        let ext = makeExtension()
        let result: (hasURL: Bool, error: String?) = await withCheckedContinuation { cont in
            _ = ext.fetchContents(for: id("asset:a:x"), version: nil, request: request) { url, _, error in
                cont.resume(returning: (url != nil, error.map { String(describing: $0) }))
            }
        }
        XCTAssertNil(result.error)
        XCTAssertTrue(result.hasURL)
    }

    // MARK: createItem

    private func create(_ ext: FileProviderExtension, template: NSFileProviderItem, contents: URL?) async -> Outcome {
        await withCheckedContinuation { cont in
            _ = ext.createItem(basedOn: template, fields: [], contents: contents, options: [], request: request) { item, _, _, error in
                cont.resume(returning: Outcome(filename: item?.filename, error: error.map { String(describing: $0) }))
            }
        }
    }

    func testCreateAlbumFolder() async {
        let template = TemplateItem(parent: "section:albums", filename: "New", contentType: .folder)
        let outcome = await create(makeExtension(), template: template, contents: nil)
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(outcome.filename, "New")
    }

    func testCreateRejectsFolderOutsideAlbums() async {
        let template = TemplateItem(parent: "section:people", filename: "X", contentType: .folder)
        let outcome = await create(makeExtension(), template: template, contents: nil)
        XCTAssertNil(outcome.filename)
        XCTAssertNotNil(outcome.error)
    }

    func testUploadFileIntoAlbum() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).png")
        try Data([0x1, 0x2, 0x3]).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let template = TemplateItem(parent: "album:a", filename: "f.jpg", contentType: .jpeg)
        let outcome = await create(makeExtension(), template: template, contents: url)
        XCTAssertTrue(outcome.ok, "upload errored: \(outcome.error ?? "")")
        // The returned item is resolved from the album after upload+add, so the
        // filename proves the whole chain ran (upload -> add -> refetch -> resolve).
        XCTAssertEqual(outcome.filename, "f.jpg")
    }

    // MARK: modifyItem

    private func modify(_ ext: FileProviderExtension, item: NSFileProviderItem, fields: NSFileProviderItemFields) async -> Outcome {
        await withCheckedContinuation { cont in
            _ = ext.modifyItem(item, baseVersion: NSFileProviderItemVersion(), changedFields: fields, contents: nil, options: [], request: request) { item, _, _, error in
                cont.resume(returning: Outcome(filename: item?.filename, error: error.map { String(describing: $0) }))
            }
        }
    }

    func testRenameAlbum() async {
        let item = TemplateItem(id: "album:a", parent: "section:albums", filename: "Renamed", contentType: .folder)
        let outcome = await modify(makeExtension(), item: item, fields: [.filename])
        XCTAssertTrue(outcome.ok)
        XCTAssertEqual(outcome.filename, "Renamed", "rename should return the new album name")
    }

    func testMoveAssetBetweenAlbums() async {
        let item = TemplateItem(id: "asset:a:x", parent: "album:b", filename: "f.jpg", contentType: .jpeg)
        let outcome = await modify(makeExtension(), item: item, fields: [.parentItemIdentifier])
        XCTAssertTrue(outcome.ok, "move errored: \(outcome.error ?? "")")
        XCTAssertEqual(outcome.filename, "f.jpg")
    }

    func testModifyUnsupportedIsNoOp() async {
        let item = TemplateItem(id: "asset:a:x", parent: "album:a", filename: "f.jpg", contentType: .jpeg)
        let outcome = await modify(makeExtension(), item: item, fields: [.contents])
        XCTAssertTrue(outcome.ok)
        XCTAssertNotNil(outcome.filename, "unsupported change should be accepted as a no-op")
    }

    // MARK: deleteItem

    private func delete(_ ext: FileProviderExtension, _ raw: String) async -> String? {
        await withCheckedContinuation { cont in
            _ = ext.deleteItem(identifier: id(raw), baseVersion: NSFileProviderItemVersion(), options: [], request: request) { error in
                cont.resume(returning: error.map { String(describing: $0) })
            }
        }
    }

    func testDeleteAssetTrashes() async {
        let error = await delete(makeExtension(), "asset:a:x")
        XCTAssertNil(error)
    }

    func testDeleteNonAssetRejected() async {
        let error = await delete(makeExtension(), "album:a")
        XCTAssertNotNil(error)
    }

    // MARK: fetchThumbnails

    func testFetchThumbnails() async {
        let ext = makeExtension()
        let count: Int = await withCheckedContinuation { cont in
            let counter = AtomicInt()
            _ = ext.fetchThumbnails(for: [id("asset:a:x")], requestedSize: CGSize(width: 64, height: 64)) { _, data, _ in
                if data != nil { _ = counter.next() }
            } completionHandler: { _ in
                cont.resume(returning: counter.count)
            }
        }
        XCTAssertEqual(count, 1)
    }

    // MARK: unauthenticated guards

    func testUnauthenticatedExtensionRejects() async {
        let ext = FileProviderExtension(domain: domain, client: nil, cache: nil)
        let outcome = await item(ext, "asset:a:x")
        XCTAssertNil(outcome.filename)
        XCTAssertNotNil(outcome.error)
        XCTAssertThrowsError(try ext.enumerator(for: id("section:albums"), request: request))
    }
}
