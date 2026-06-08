import Foundation
import FileProvider
import CoreGraphics

enum ItemID {
    case root
    case album(String)
    case asset(albumID: String, assetID: String)
    case other

    init(_ identifier: NSFileProviderItemIdentifier) {
        if identifier == .rootContainer {
            self = .root
            return
        }
        let raw = identifier.rawValue
        if raw.hasPrefix("album:") {
            self = .album(String(raw.dropFirst(6)))
            return
        }
        if raw.hasPrefix("asset:") {
            let parts = raw.dropFirst(6).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                self = .asset(albumID: parts[0], assetID: parts[1])
                return
            }
        }
        self = .other
    }
}

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let client: ImmichClient?

    required init(domain: NSFileProviderDomain) {
        if let credentials = CredentialStore.load() {
            self.client = ImmichClient(baseURL: credentials.baseURL, apiKey: credentials.apiKey)
        } else {
            self.client = nil
        }
        super.init()
        fileProviderLog.log("init — credentials present: \(self.client != nil, privacy: .public)")
    }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        switch ItemID(identifier) {
        case .root:
            completionHandler(RootItem(), nil)
        case .other:
            completionHandler(nil, error(.noSuchItem))
        case .album(let albumID):
            guard let client else {
                completionHandler(nil, error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let albums = try await client.listAlbums()
                    guard let summary = albums.first(where: { $0.albumID == albumID }) else {
                        completionHandler(nil, error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    let names = albums.map { $0.albumName }
                    let filename = disambiguatedName(base: summary.albumName, id: summary.albumID, among: names)
                    completionHandler(AlbumItem(album: summary, filename: filename), nil)
                } catch {
                    completionHandler(nil, error)
                }
                progress.completedUnitCount = 1
            }
            return progress
        case .asset(let albumID, let assetID):
            guard let client else {
                completionHandler(nil, error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let assets = try await client.album(id: albumID).assets
                    guard let asset = assets.first(where: { $0.assetID == assetID }) else {
                        completionHandler(nil, error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    let names = assets.map { $0.originalFileName }
                    let filename = disambiguatedName(base: asset.originalFileName, id: assetID, among: names)
                    completionHandler(ImmichItem(asset: asset, albumID: albumID, filename: filename), nil)
                } catch {
                    completionHandler(nil, error)
                }
                progress.completedUnitCount = 1
            }
            return progress
        }
        progress.completedUnitCount = 1
        return progress
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        guard let client else {
            completionHandler(nil, nil, error(.notAuthenticated))
            return progress
        }
        guard case .asset(let albumID, let assetID) = ItemID(itemIdentifier) else {
            completionHandler(nil, nil, error(.noSuchItem))
            return progress
        }
        Task {
            do {
                let assets = try await client.album(id: albumID).assets
                guard let asset = assets.first(where: { $0.assetID == assetID }) else {
                    completionHandler(nil, nil, error(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                let names = assets.map { $0.originalFileName }
                let filename = disambiguatedName(base: asset.originalFileName, id: assetID, among: names)
                let data = try await client.downloadOriginal(assetID: assetID)
                fileProviderLog.log("fetchContents \(assetID, privacy: .public) — \(data.count, privacy: .public) bytes")
                let url = try Self.writeTemporary(data: data, filename: filename)
                completionHandler(url, ImmichItem(asset: asset, albumID: albumID, filename: filename), nil)
            } catch {
                fileProviderLog.error("fetchContents failed for \(assetID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, nil, error)
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let client else {
            throw error(.notAuthenticated)
        }
        fileProviderLog.log("enumerator for: \(containerItemIdentifier.rawValue, privacy: .public)")
        switch ItemID(containerItemIdentifier) {
        case .root, .other:
            return ItemEnumerator(client: client, container: .albums)
        case .album(let id):
            return ItemEnumerator(client: client, container: .album(id: id))
        case .asset:
            throw error(.noSuchItem)
        }
    }

    // Read-only: write operations are rejected. Item capabilities also exclude
    // them, so the system should not normally reach these.
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, readOnlyError())
        return Progress()
    }

    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        completionHandler(nil, [], false, readOnlyError())
        return Progress()
    }

    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        completionHandler(readOnlyError())
        return Progress()
    }

    private func error(_ code: NSFileProviderError.Code) -> NSError {
        NSError(domain: NSFileProviderErrorDomain, code: code.rawValue)
    }

    private func readOnlyError() -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError)
    }

    private static func writeTemporary(data: Data, filename: String) throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent(filename)
        try data.write(to: url)
        return url
    }
}

extension FileProviderExtension: NSFileProviderThumbnailing {
    func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))
        guard let client else {
            completionHandler(error(.notAuthenticated))
            return progress
        }
        Task {
            for identifier in itemIdentifiers {
                guard case .asset(_, let assetID) = ItemID(identifier) else {
                    perThumbnailCompletionHandler(identifier, nil, error(.noSuchItem))
                    progress.completedUnitCount += 1
                    continue
                }
                do {
                    let data = try await client.downloadThumbnail(assetID: assetID, size: nil)
                    perThumbnailCompletionHandler(identifier, data, nil)
                } catch {
                    perThumbnailCompletionHandler(identifier, nil, error)
                }
                progress.completedUnitCount += 1
            }
            completionHandler(nil)
        }
        return progress
    }
}
