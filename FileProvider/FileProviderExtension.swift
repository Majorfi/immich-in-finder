import Foundation
import FileProvider
import CoreGraphics

enum ItemID {
    case root
    case albumsSection
    case timelineSection
    case album(String)
    case asset(albumID: String, assetID: String)
    case year(String)
    case month(String)
    case timelineAsset(yearMonth: String, assetID: String)
    case other

    init(_ identifier: NSFileProviderItemIdentifier) {
        if identifier == .rootContainer {
            self = .root
            return
        }
        let raw = identifier.rawValue
        if raw == "section:albums" {
            self = .albumsSection
            return
        }
        if raw == "section:timeline" {
            self = .timelineSection
            return
        }
        if raw.hasPrefix("album:") {
            self = .album(String(raw.dropFirst("album:".count)))
            return
        }
        if raw.hasPrefix("year:") {
            self = .year(String(raw.dropFirst("year:".count)))
            return
        }
        if raw.hasPrefix("month:") {
            self = .month(String(raw.dropFirst("month:".count)))
            return
        }
        if raw.hasPrefix("asset:") {
            let parts = raw.dropFirst("asset:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                self = .asset(albumID: parts[0], assetID: parts[1])
                return
            }
        }
        if raw.hasPrefix("tasset:") {
            let parts = raw.dropFirst("tasset:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                self = .timelineAsset(yearMonth: parts[0], assetID: parts[1])
                return
            }
        }
        self = .other
    }

    // An asset identifier carries both its id and where it lives, so the album
    // and timeline cases share one resolution path.
    var assetRef: (assetID: String, location: AssetLocation)? {
        switch self {
        case .asset(let albumID, let assetID):
            return (assetID, .album(id: albumID))
        case .timelineAsset(let yearMonth, let assetID):
            return (assetID, .month(yearMonth: yearMonth))
        default:
            return nil
        }
    }
}

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let client: ImmichClient?
    private let cache: ImmichCache?

    required init(domain: NSFileProviderDomain) {
        if let credentials = CredentialStore.load() {
            let immichClient = ImmichClient(baseURL: credentials.baseURL, apiKey: credentials.apiKey)
            self.client = immichClient
            self.cache = ImmichCache(client: immichClient)
        } else {
            self.client = nil
            self.cache = nil
        }
        super.init()
        fileProviderLog.log("init — credentials present: \(self.client != nil, privacy: .public)")
    }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        let parsed = ItemID(identifier)

        if let ref = parsed.assetRef {
            guard let cache else {
                completionHandler(nil, error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    guard let resolved = try await resolve(ref, cache: cache) else {
                        completionHandler(nil, error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    completionHandler(ImmichItem(asset: resolved.asset, location: ref.location, filename: resolved.filename), nil)
                } catch {
                    completionHandler(nil, error)
                }
                progress.completedUnitCount = 1
            }
            return progress
        }

        switch parsed {
        case .root:
            completionHandler(RootItem(), nil)
        case .albumsSection:
            completionHandler(SectionItem(id: "section:albums", name: "Albums"), nil)
        case .timelineSection:
            completionHandler(SectionItem(id: "section:timeline", name: "Timeline"), nil)
        case .year(let year):
            completionHandler(YearItem(year: year), nil)
        case .month(let yearMonth):
            completionHandler(MonthItem(yearMonth: yearMonth), nil)
        case .album(let albumID):
            guard let cache else {
                completionHandler(nil, error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let albums = try await cache.albumList()
                    guard let summary = albums.first(where: { $0.albumID == albumID }) else {
                        completionHandler(nil, error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    let counts = nameCounts(albums.map { $0.albumName })
                    let filename = disambiguatedName(base: summary.albumName, id: summary.albumID, counts: counts)
                    completionHandler(AlbumItem(album: summary, filename: filename), nil)
                } catch {
                    completionHandler(nil, error)
                }
                progress.completedUnitCount = 1
            }
            return progress
        case .asset, .timelineAsset, .other:
            completionHandler(nil, error(.noSuchItem))
        }
        progress.completedUnitCount = 1
        return progress
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        let progress = Progress(totalUnitCount: 1)
        guard let client, let cache else {
            completionHandler(nil, nil, error(.notAuthenticated))
            return progress
        }
        guard let ref = ItemID(itemIdentifier).assetRef else {
            completionHandler(nil, nil, error(.noSuchItem))
            return progress
        }
        Task {
            do {
                guard let resolved = try await resolve(ref, cache: cache) else {
                    completionHandler(nil, nil, error(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                let data = try await client.downloadOriginal(assetID: ref.assetID)
                fileProviderLog.log("fetchContents \(ref.assetID, privacy: .public) — \(data.count, privacy: .public) bytes")
                let url = try Self.writeTemporary(data: data, filename: resolved.filename)
                completionHandler(url, ImmichItem(asset: resolved.asset, location: ref.location, filename: resolved.filename), nil)
            } catch {
                fileProviderLog.error("fetchContents failed for \(ref.assetID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, nil, error)
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let client, let cache else {
            throw error(.notAuthenticated)
        }
        fileProviderLog.log("enumerator for: \(containerItemIdentifier.rawValue, privacy: .public)")
        switch ItemID(containerItemIdentifier) {
        case .root, .other:
            return ItemEnumerator(client: client, cache: cache, container: .sections)
        case .albumsSection:
            return ItemEnumerator(client: client, cache: cache, container: .albums)
        case .timelineSection:
            return ItemEnumerator(client: client, cache: cache, container: .years)
        case .album(let id):
            return ItemEnumerator(client: client, cache: cache, container: .album(id: id))
        case .year(let year):
            return ItemEnumerator(client: client, cache: cache, container: .months(year: year))
        case .month(let yearMonth):
            return ItemEnumerator(client: client, cache: cache, container: .month(yearMonth: yearMonth))
        case .asset, .timelineAsset:
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

    private func resolve(_ ref: (assetID: String, location: AssetLocation), cache: ImmichCache) async throws -> (asset: Asset, filename: String)? {
        let siblings = try await ref.location.siblings(from: cache)
        return resolveAsset(ref.assetID, in: siblings)
    }

    private func error(_ code: NSFileProviderError.Code) -> NSError {
        NSError(domain: NSFileProviderErrorDomain, code: code.rawValue)
    }

    private func readOnlyError() -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError)
    }

    private static func writeTemporary(data: Data, filename: String) throws -> URL {
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
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
            await withTaskGroup(of: Void.self) { group in
                for identifier in itemIdentifiers {
                    guard let assetID = ItemID(identifier).assetRef?.assetID else {
                        perThumbnailCompletionHandler(identifier, nil, error(.noSuchItem))
                        continue
                    }
                    group.addTask {
                        do {
                            let data = try await client.downloadThumbnail(assetID: assetID, size: nil)
                            perThumbnailCompletionHandler(identifier, data, nil)
                        } catch {
                            perThumbnailCompletionHandler(identifier, nil, error)
                        }
                    }
                }
            }
            progress.completedUnitCount = Int64(itemIdentifiers.count)
            completionHandler(nil)
        }
        return progress
    }
}
