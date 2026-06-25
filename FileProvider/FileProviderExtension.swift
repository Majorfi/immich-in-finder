import Foundation
import FileProvider
import CoreGraphics
import UniformTypeIdentifiers

enum ItemID {
    case root
    case albumsSection
    case timelineSection
    case album(String)
    case asset(albumID: String, assetID: String)
    case year(String)
    case month(String)
    case timelineAsset(yearMonth: String, assetID: String)
    case peopleSection
    case person(String)
    case personAsset(personID: String, assetID: String)
    case placesSection
    case country(String)
    case city(country: String, city: String)
    case placeAsset(country: String, city: String, assetID: String)
    case tagsSection
    case tag(String)
    case tagAsset(tagID: String, assetID: String)
    case favoritesSection
    case favoriteAsset(assetID: String)
    // A synthetic sub-folder of a large asset container, holding one fixed-size
    // slice of its assets. The location it slices is encoded inline so the chunk
    // can both enumerate its page and report the right parent folder.
    case chunk(location: AssetLocation, index: Int)
    // The date strategy's folders: a year, a month, or one page of a large month.
    // Each carries the location it groups so it can enumerate and parent itself.
    case dateYear(location: AssetLocation, year: String)
    case dateMonth(location: AssetLocation, yearMonth: String)
    case datePage(location: AssetLocation, yearMonth: String, page: Int)
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
        if raw == "section:people" {
            self = .peopleSection
            return
        }
        if raw.hasPrefix("person:") {
            self = .person(String(raw.dropFirst("person:".count)))
            return
        }
        if raw == "section:places" {
            self = .placesSection
            return
        }
        if raw == "section:tags" {
            self = .tagsSection
            return
        }
        if raw.hasPrefix("tag:") {
            self = .tag(String(raw.dropFirst("tag:".count)))
            return
        }
        if raw == "section:favorites" {
            self = .favoritesSection
            return
        }
        if raw.hasPrefix("fasset:") {
            self = .favoriteAsset(assetID: String(raw.dropFirst("fasset:".count)))
            return
        }
        if raw.hasPrefix("country:") {
            self = .country(String(raw.dropFirst("country:".count)))
            return
        }
        if raw.hasPrefix("city:") {
            let parts = raw.dropFirst("city:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                self = .city(country: parts[0], city: parts[1])
                return
            }
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
        if raw.hasPrefix("passet:") {
            let parts = raw.dropFirst("passet:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                self = .personAsset(personID: parts[0], assetID: parts[1])
                return
            }
        }
        if raw.hasPrefix("qasset:") {
            // country (no colons) first, assetID (a UUID, no colons) last, so the
            // city in between may contain anything without breaking the parse.
            let parts = raw.dropFirst("qasset:".count).split(separator: ":").map(String.init)
            if parts.count >= 3 {
                let city = parts[1..<(parts.count - 1)].joined(separator: ":")
                self = .placeAsset(country: parts[0], city: city, assetID: parts[parts.count - 1])
                return
            }
        }
        if raw.hasPrefix("tagasset:") {
            let parts = raw.dropFirst("tagasset:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                self = .tagAsset(tagID: parts[0], assetID: parts[1])
                return
            }
        }
        if raw.hasPrefix("chunk:") {
            // index (digits, no colons) first, then the location code (which may
            // itself contain colons for a place), so split only once.
            let parts = raw.dropFirst("chunk:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let index = Int(parts[0]), index >= 0, let location = AssetLocation(code: parts[1]) {
                self = .chunk(location: location, index: index)
                return
            }
        }
        if raw.hasPrefix("dyear:") {
            let parts = raw.dropFirst("dyear:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let location = AssetLocation(code: parts[1]) {
                self = .dateYear(location: location, year: parts[0])
                return
            }
        }
        if raw.hasPrefix("dmonth:") {
            let parts = raw.dropFirst("dmonth:".count).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2, let location = AssetLocation(code: parts[1]) {
                self = .dateMonth(location: location, yearMonth: parts[0])
                return
            }
        }
        if raw.hasPrefix("dpage:") {
            // page (digits) then yearMonth ("YYYY-MM", no bare colon) then the code.
            let parts = raw.dropFirst("dpage:".count).split(separator: ":", maxSplits: 2).map(String.init)
            if parts.count == 3, let page = Int(parts[0]), page >= 0, let location = AssetLocation(code: parts[2]) {
                self = .datePage(location: location, yearMonth: parts[1], page: page)
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
        case .personAsset(let personID, let assetID):
            return (assetID, .person(id: personID))
        case .placeAsset(let country, let city, let assetID):
            return (assetID, .place(country: country, city: city))
        case .tagAsset(let tagID, let assetID):
            return (assetID, .tag(id: tagID))
        case .favoriteAsset(let assetID):
            return (assetID, .favorite)
        default:
            return nil
        }
    }

    // The inverse of init(_:). Keeping construction here, next to the parser,
    // is what keeps the two halves of the identifier grammar from drifting:
    // every item and signal builds its identifier through this, not by hand.
    var identifier: NSFileProviderItemIdentifier {
        switch self {
        case .root:
            return .rootContainer
        case .albumsSection:
            return NSFileProviderItemIdentifier(rawValue: "section:albums")
        case .timelineSection:
            return NSFileProviderItemIdentifier(rawValue: "section:timeline")
        case .album(let id):
            return NSFileProviderItemIdentifier(rawValue: "album:\(id)")
        case .asset(let albumID, let assetID):
            return NSFileProviderItemIdentifier(rawValue: "asset:\(albumID):\(assetID)")
        case .year(let year):
            return NSFileProviderItemIdentifier(rawValue: "year:\(year)")
        case .month(let yearMonth):
            return NSFileProviderItemIdentifier(rawValue: "month:\(yearMonth)")
        case .timelineAsset(let yearMonth, let assetID):
            return NSFileProviderItemIdentifier(rawValue: "tasset:\(yearMonth):\(assetID)")
        case .peopleSection:
            return NSFileProviderItemIdentifier(rawValue: "section:people")
        case .person(let id):
            return NSFileProviderItemIdentifier(rawValue: "person:\(id)")
        case .personAsset(let personID, let assetID):
            return NSFileProviderItemIdentifier(rawValue: "passet:\(personID):\(assetID)")
        case .placesSection:
            return NSFileProviderItemIdentifier(rawValue: "section:places")
        case .country(let name):
            return NSFileProviderItemIdentifier(rawValue: "country:\(name)")
        case .city(let country, let city):
            return NSFileProviderItemIdentifier(rawValue: "city:\(country):\(city)")
        case .placeAsset(let country, let city, let assetID):
            return NSFileProviderItemIdentifier(rawValue: "qasset:\(country):\(city):\(assetID)")
        case .tagsSection:
            return NSFileProviderItemIdentifier(rawValue: "section:tags")
        case .tag(let id):
            return NSFileProviderItemIdentifier(rawValue: "tag:\(id)")
        case .tagAsset(let tagID, let assetID):
            return NSFileProviderItemIdentifier(rawValue: "tagasset:\(tagID):\(assetID)")
        case .favoritesSection:
            return NSFileProviderItemIdentifier(rawValue: "section:favorites")
        case .favoriteAsset(let assetID):
            return NSFileProviderItemIdentifier(rawValue: "fasset:\(assetID)")
        case .chunk(let location, let index):
            return NSFileProviderItemIdentifier(rawValue: "chunk:\(index):\(location.code)")
        case .dateYear(let location, let year):
            return NSFileProviderItemIdentifier(rawValue: "dyear:\(year):\(location.code)")
        case .dateMonth(let location, let yearMonth):
            return NSFileProviderItemIdentifier(rawValue: "dmonth:\(yearMonth):\(location.code)")
        case .datePage(let location, let yearMonth, let page):
            return NSFileProviderItemIdentifier(rawValue: "dpage:\(page):\(yearMonth):\(location.code)")
        case .other:
            return NSFileProviderItemIdentifier(rawValue: "")
        }
    }
}

// Maps a thrown error to the closest NSFileProviderError so the Finder shows a
// sane message and retries appropriately, instead of an opaque failure. Unknown
// errors pass through unchanged.
func fileProviderError(from error: Error) -> Error {
    let code: NSFileProviderError.Code?
    if let immich = error as? ImmichError, case .httpStatus(_, let status) = immich {
        switch status {
        case 401, 403: code = .notAuthenticated
        case 404: code = .noSuchItem
        case 413, 507: code = .insufficientQuota
        default: code = nil
        }
    } else if let urlError = error as? URLError {
        switch urlError.code {
        case .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
             .timedOut, .networkConnectionLost, .dnsLookupFailed:
            code = .serverUnreachable
        default: code = nil
        }
    } else {
        code = nil
    }
    guard let code else { return error }
    return NSError(domain: NSFileProviderErrorDomain, code: code.rawValue)
}

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let client: ImmichClient?
    private let cache: ImmichCache?
    private let domain: NSFileProviderDomain

    required convenience init(domain: NSFileProviderDomain) {
        let client = CredentialStore.load().map { ImmichClient(baseURL: $0.baseURL, apiKey: $0.apiKey) }
        self.init(domain: domain, client: client, cache: client.map(ImmichCache.init(client:)))
        fileProviderLog.log("init, credentials present: \(client != nil, privacy: .public)")
    }

    // Designated initializer; also the seam tests use to inject a mocked client.
    init(domain: NSFileProviderDomain, client: ImmichClient?, cache: ImmichCache?) {
        self.domain = domain
        self.client = client
        self.cache = cache
        super.init()
    }

    func invalidate() {}

    func item(for identifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        // The system completion handler is not Sendable but is meant to be
        // invoked asynchronously from any thread, so the Tasks below may call it.
        nonisolated(unsafe) let completionHandler = completionHandler
        let progress = Progress(totalUnitCount: 1)
        let parsed = ItemID(identifier)

        if let ref = parsed.assetRef {
            guard let cache else {
                completionHandler(nil, Self.error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    guard let resolved = try await Self.resolve(ref, cache: cache) else {
                        completionHandler(nil, Self.error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    completionHandler(ImmichItem(asset: resolved.asset, location: ref.location, filename: resolved.filename, parent: resolved.parent), nil)
                } catch {
                    completionHandler(nil, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        }

        switch parsed {
        case .root:
            completionHandler(RootItem(), nil)
        case .albumsSection:
            completionHandler(SectionItem(kind: .albums), nil)
        case .timelineSection:
            completionHandler(SectionItem(kind: .timeline), nil)
        case .peopleSection:
            completionHandler(SectionItem(kind: .people), nil)
        case .placesSection:
            completionHandler(SectionItem(kind: .places), nil)
        case .tagsSection:
            completionHandler(SectionItem(kind: .tags), nil)
        case .favoritesSection:
            completionHandler(SectionItem(kind: .favorites), nil)
        case .year(let year):
            completionHandler(YearItem(year: year), nil)
        case .month(let yearMonth):
            completionHandler(MonthItem(yearMonth: yearMonth), nil)
        case .country(let name):
            completionHandler(FolderItem(id: .country(name), parent: .placesSection, filename: name), nil)
        case .city(let country, let city):
            completionHandler(FolderItem(id: .city(country: country, city: city), parent: .country(country), filename: city), nil)
        case .person(let personID):
            guard let cache else {
                completionHandler(nil, Self.error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let people = try await cache.peopleList()
                    guard let person = people.first(where: { $0.personID == personID }) else {
                        completionHandler(nil, Self.error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    completionHandler(Self.personItem(for: person, in: people), nil)
                } catch {
                    completionHandler(nil, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        case .tag(let tagID):
            guard let cache else {
                completionHandler(nil, Self.error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let tags = try await cache.tagList()
                    guard let tag = tags.first(where: { $0.tagID == tagID }) else {
                        completionHandler(nil, Self.error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    completionHandler(Self.tagItem(for: tag, in: tags), nil)
                } catch {
                    completionHandler(nil, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        case .album(let albumID):
            guard let cache else {
                completionHandler(nil, Self.error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let albums = try await cache.albumList()
                    guard let summary = albums.first(where: { $0.albumID == albumID }) else {
                        completionHandler(nil, Self.error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    completionHandler(Self.albumItem(for: summary, in: albums), nil)
                } catch {
                    completionHandler(nil, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        case .chunk(let location, let index):
            guard let cache else {
                completionHandler(nil, Self.error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let count = try await cache.assetCount(for: location)
                    let settings = ChunkingSettings.load()
                    completionHandler(ChunkFolderItem(location: location, index: index, size: settings.size, totalCount: count), nil)
                } catch {
                    completionHandler(nil, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        case .dateYear(let location, let year):
            return dateFolder(.year(year), location: location, cache: cache, progress: progress, completionHandler: completionHandler)
        case .dateMonth(let location, let yearMonth):
            return dateFolder(.month(yearMonth), location: location, cache: cache, progress: progress, completionHandler: completionHandler)
        case .datePage(let location, let yearMonth, let page):
            return dateFolder(.page(month: yearMonth, index: page), location: location, cache: cache, progress: progress, completionHandler: completionHandler)
        case .asset, .timelineAsset, .personAsset, .placeAsset, .tagAsset, .favoriteAsset, .other:
            completionHandler(nil, Self.error(.noSuchItem))
        }
        progress.completedUnitCount = 1
        return progress
    }

    // Shared body for the three date-folder item(for:) cases: builds the folder
    // from the current layout, or reports notAuthenticated without a client.
    private func dateFolder(_ node: DateChunkNode, location: AssetLocation, cache: ImmichCache?, progress: Progress, completionHandler: @escaping (NSFileProviderItem?, Error?) -> Void) -> Progress {
        nonisolated(unsafe) let completionHandler = completionHandler
        guard let cache else {
            completionHandler(nil, Self.error(.notAuthenticated))
            return progress
        }
        Task {
            do {
                completionHandler(try await Self.dateFolderItem(node, location: location, cache: cache), nil)
            } catch {
                completionHandler(nil, fileProviderError(from: error))
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    func fetchContents(for itemIdentifier: NSFileProviderItemIdentifier, version requestedVersion: NSFileProviderItemVersion?, request: NSFileProviderRequest, completionHandler: @escaping (URL?, NSFileProviderItem?, Error?) -> Void) -> Progress {
        nonisolated(unsafe) let completionHandler = completionHandler
        let progress = Progress(totalUnitCount: 1)
        guard let client, let cache else {
            completionHandler(nil, nil, Self.error(.notAuthenticated))
            return progress
        }
        guard let ref = ItemID(itemIdentifier).assetRef else {
            completionHandler(nil, nil, Self.error(.noSuchItem))
            return progress
        }
        Task {
            do {
                guard let resolved = try await Self.resolve(ref, cache: cache) else {
                    completionHandler(nil, nil, Self.error(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                let data = try await client.downloadOriginal(assetID: ref.assetID)
                fileProviderLog.log("fetchContents \(ref.assetID, privacy: .public): \(data.count, privacy: .public) bytes")
                let url = try Self.writeTemporary(data: data, filename: resolved.filename)
                completionHandler(url, ImmichItem(asset: resolved.asset, location: ref.location, filename: resolved.filename, parent: resolved.parent), nil)
            } catch {
                fileProviderLog.error("fetchContents failed for \(ref.assetID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, nil, fileProviderError(from: error))
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    func enumerator(for containerItemIdentifier: NSFileProviderItemIdentifier, request: NSFileProviderRequest) throws -> NSFileProviderEnumerator {
        guard let client, let cache else {
            throw Self.error(.notAuthenticated)
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
        case .peopleSection:
            return ItemEnumerator(client: client, cache: cache, container: .people)
        case .person(let id):
            return ItemEnumerator(client: client, cache: cache, container: .person(id: id))
        case .placesSection:
            return ItemEnumerator(client: client, cache: cache, container: .countries)
        case .country(let name):
            return ItemEnumerator(client: client, cache: cache, container: .cities(country: name))
        case .city(let country, let city):
            return ItemEnumerator(client: client, cache: cache, container: .place(country: country, city: city))
        case .tagsSection:
            return ItemEnumerator(client: client, cache: cache, container: .tags)
        case .tag(let id):
            return ItemEnumerator(client: client, cache: cache, container: .tag(id: id))
        case .favoritesSection:
            return ItemEnumerator(client: client, cache: cache, container: .favorites)
        case .chunk(let location, let index):
            return ItemEnumerator(client: client, cache: cache, container: .chunk(location: location, index: index))
        case .dateYear(let location, let year):
            return ItemEnumerator(client: client, cache: cache, container: .dateYear(location: location, year: year))
        case .dateMonth(let location, let yearMonth):
            return ItemEnumerator(client: client, cache: cache, container: .dateMonth(location: location, yearMonth: yearMonth))
        case .datePage(let location, let yearMonth, let page):
            return ItemEnumerator(client: client, cache: cache, container: .datePage(location: location, yearMonth: yearMonth, page: page))
        case .asset, .timelineAsset, .personAsset, .placeAsset, .tagAsset, .favoriteAsset:
            throw Self.error(.noSuchItem)
        }
    }

    // Creating a folder under the Albums section makes a new Immich album;
    // dropping a file into an album folder uploads it and adds it to that album.
    // Everywhere else (Timeline, root) is read-only.
    func createItem(basedOn itemTemplate: NSFileProviderItem, fields: NSFileProviderItemFields, contents url: URL?, options: NSFileProviderCreateItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        nonisolated(unsafe) let completionHandler = completionHandler
        // domain is an immutable reference set once in init and only used to
        // build a thread-safe NSFileProviderManager, so it is safe to cross into
        // the Tasks below; the annotation just opts out of region-isolation.
        nonisolated(unsafe) let domain = self.domain
        let progress = Progress(totalUnitCount: 1)
        guard let client, let cache else {
            completionHandler(nil, [], false, Self.error(.notAuthenticated))
            return progress
        }
        let parent = ItemID(itemTemplate.parentItemIdentifier)
        let filename = itemTemplate.filename

        if itemTemplate.contentType?.conforms(to: .folder) == true {
            guard case .albumsSection = parent else {
                completionHandler(nil, [], false, Self.readOnlyError())
                return progress
            }
            Task {
                do {
                    let album = try await client.createAlbum(name: filename)
                    await cache.invalidateAlbumList()
                    fileProviderLog.log("created album \(album.albumID, privacy: .public)")
                    // Name it against the refreshed list so the returned filename
                    // matches what enumeration will report for the same album.
                    let albums = try await cache.albumList()
                    completionHandler(Self.albumItem(for: album, in: albums), [], false, nil)
                    Self.signalChange(domain: domain, container: ItemID.albumsSection.identifier)
                } catch {
                    fileProviderLog.error("createAlbum failed: \(error.localizedDescription, privacy: .public)")
                    completionHandler(nil, [], false, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        }

        guard case .album(let albumID) = parent, let url else {
            completionHandler(nil, [], false, Self.readOnlyError())
            return progress
        }
        let createdAt = Self.isoString(itemTemplate.creationDate ?? nil)
        let modifiedAt = Self.isoString(itemTemplate.contentModificationDate ?? nil)
        Task {
            do {
                let result = try await client.uploadAsset(filename: filename, fileURL: url, createdAt: createdAt, modifiedAt: modifiedAt)
                try await client.addAssets(albumID: albumID, assetIDs: [result.ID])
                await cache.invalidate(.album(id: albumID))
                await cache.invalidateTimeline()
                fileProviderLog.log("uploaded \(result.ID, privacy: .public) (duplicate: \(result.isDuplicate, privacy: .public)) → album \(albumID, privacy: .public)")
                // Return the asset as the server now reports it, so the item's
                // filename is disambiguated and its content version (checksum)
                // matches enumeration, avoiding a ghost entry and an immediate
                // redundant re-download of the file we just uploaded.
                let siblings = try await cache.assets(for: .album(id: albumID))
                guard let resolved = resolveAsset(result.ID, in: siblings) else {
                    completionHandler(nil, [], false, Self.error(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                let parent = await Self.assetParent(for: .album(id: albumID), asset: resolved.asset, in: siblings, cache: cache)
                completionHandler(ImmichItem(asset: resolved.asset, location: .album(id: albumID), filename: resolved.filename, parent: parent), [], false, nil)
                Self.signalChange(domain: domain, container: ItemID.album(albumID).identifier)
            } catch {
                fileProviderLog.error("upload failed for \(filename, privacy: .private): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, [], false, fileProviderError(from: error))
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    // Renaming an album folder renames the Immich album; moving an album asset
    // to another album folder re-links it (add to destination, remove from
    // source). Other field changes are accepted as no-ops so the system does
    // not keep retrying metadata it cannot push to Immich.
    func modifyItem(_ item: NSFileProviderItem, baseVersion version: NSFileProviderItemVersion, changedFields: NSFileProviderItemFields, contents newContents: URL?, options: NSFileProviderModifyItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (NSFileProviderItem?, NSFileProviderItemFields, Bool, Error?) -> Void) -> Progress {
        nonisolated(unsafe) let completionHandler = completionHandler
        nonisolated(unsafe) let domain = self.domain
        let progress = Progress(totalUnitCount: 1)
        guard let client, let cache else {
            completionHandler(nil, [], false, Self.error(.notAuthenticated))
            return progress
        }
        let parsed = ItemID(item.itemIdentifier)

        if changedFields.contains(.filename), case .album(let albumID) = parsed {
            let newName = item.filename
            Task {
                do {
                    let album = try await client.renameAlbum(ID: albumID, name: newName)
                    await cache.invalidateAlbumList()
                    fileProviderLog.log("renamed album \(albumID, privacy: .public)")
                    let albums = try await cache.albumList()
                    completionHandler(Self.albumItem(for: album, in: albums), [], false, nil)
                    Self.signalChange(domain: domain, container: ItemID.albumsSection.identifier)
                } catch {
                    fileProviderLog.error("renameAlbum failed: \(error.localizedDescription, privacy: .public)")
                    completionHandler(nil, [], false, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        }

        if changedFields.contains(.parentItemIdentifier), let ref = parsed.assetRef, case .album(let srcAlbum) = ref.location {
            guard case .album(let destAlbum) = ItemID(item.parentItemIdentifier) else {
                completionHandler(nil, [], false, Self.readOnlyError())
                return progress
            }
            let assetID = ref.assetID
            Task {
                do {
                    // Add before remove: if the second call fails the asset is in
                    // both albums (recoverable) rather than lost from both.
                    try await client.addAssets(albumID: destAlbum, assetIDs: [assetID])
                    try await client.removeAssets(albumID: srcAlbum, assetIDs: [assetID])
                    await cache.invalidate(.album(id: srcAlbum))
                    await cache.invalidate(.album(id: destAlbum))
                    let siblings = try await cache.assets(for: .album(id: destAlbum))
                    guard let resolved = resolveAsset(assetID, in: siblings) else {
                        completionHandler(nil, [], false, Self.error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    fileProviderLog.log("moved asset \(assetID, privacy: .public): \(srcAlbum, privacy: .public) -> \(destAlbum, privacy: .public)")
                    completionHandler(ImmichItem(asset: resolved.asset, location: .album(id: destAlbum), filename: resolved.filename), [], false, nil)
                    Self.signalChange(domain: domain, container: ItemID.album(srcAlbum).identifier)
                    Self.signalChange(domain: domain, container: ItemID.album(destAlbum).identifier)
                } catch {
                    fileProviderLog.error("move failed for \(assetID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    completionHandler(nil, [], false, fileProviderError(from: error))
                }
                progress.completedUnitCount = 1
            }
            return progress
        }

        // Unsupported field change (content edit, metadata, Timeline reparent):
        // accept as a no-op rather than erroring.
        completionHandler(item, [], false, nil)
        return progress
    }

    // Deleting an asset moves it to the Immich trash (recoverable for 30 days).
    // Only assets are deletable; album/section folders are read-only here.
    func deleteItem(identifier: NSFileProviderItemIdentifier, baseVersion version: NSFileProviderItemVersion, options: NSFileProviderDeleteItemOptions = [], request: NSFileProviderRequest, completionHandler: @escaping (Error?) -> Void) -> Progress {
        nonisolated(unsafe) let completionHandler = completionHandler
        nonisolated(unsafe) let domain = self.domain
        let progress = Progress(totalUnitCount: 1)
        guard let client, let cache else {
            completionHandler(Self.error(.notAuthenticated))
            return progress
        }
        guard let ref = ItemID(identifier).assetRef else {
            completionHandler(Self.readOnlyError())
            return progress
        }
        Task {
            do {
                try await client.trashAssets(assetIDs: [ref.assetID])
                await cache.invalidate(ref.location)
                await cache.invalidateTimeline()
                fileProviderLog.log("trashed asset \(ref.assetID, privacy: .public)")
                completionHandler(nil)
                Self.signalChange(domain: domain, container: ref.location.parentItemID.identifier)
            } catch {
                fileProviderLog.error("trash failed for \(ref.assetID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(fileProviderError(from: error))
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    // Static so the async Tasks below can call it without capturing self (a
    // non-Sendable NSObject), which Swift 6 region isolation forbids.
    private static func resolve(_ ref: (assetID: String, location: AssetLocation), cache: ImmichCache) async throws -> (asset: Asset, filename: String, parent: ItemID?)? {
        let siblings = try await ref.location.siblings(from: cache)
        guard let resolved = resolveAsset(ref.assetID, in: siblings) else {
            return nil
        }
        let parent = await assetParent(for: ref.location, asset: resolved.asset, in: siblings, cache: cache)
        return (resolved.asset, resolved.filename, parent)
    }

    // The sub-folder an asset reports as its parent, or nil when its container is
    // not chunked. The position comes from the same order:.asc membership
    // enumeration pages over, so the parent reported here matches the folder that
    // listed it. The count falls back to the fetched membership if the statistics
    // call fails, so resolution never breaks just because the count is briefly
    // unavailable.
    private static func assetParent(for location: AssetLocation, asset: Asset, in siblings: [Asset], cache: ImmichCache) async -> ItemID? {
        let settings = ChunkingSettings.load()
        guard settings.enabled else {
            return nil
        }
        if settings.strategy == .date, location.supportsDateChunking {
            guard siblings.count > settings.size else {
                return nil
            }
            let layout = DateChunkLayout(monthCounts: DateChunkLayout.counts(of: siblings), size: settings.size)
            let month = DateChunkLayout.month(of: asset)
            let monthAssets = siblings.filter { DateChunkLayout.month(of: $0) == month }
            guard let indexInMonth = monthAssets.firstIndex(where: { $0.assetID == asset.assetID }),
                  let node = layout.assetParentNode(month: month, indexInMonth: indexInMonth) else {
                return nil
            }
            return dateNodeID(node, location: location)
        }
        guard let position = siblings.firstIndex(where: { $0.assetID == asset.assetID }) else {
            return nil
        }
        let count = (try? await cache.assetCount(for: location)) ?? siblings.count
        guard settings.isChunked(count: count) else {
            return nil
        }
        return ItemID.chunk(location: location, index: settings.chunkIndex(forAssetIndex: position, count: count))
    }

    // Builds the folder item for a date node out of context: fetches the
    // membership, rebuilds the same layout the enumerator used, and reports the
    // node's identifier, parent, and name from it.
    private static func dateFolderItem(_ node: DateChunkNode, location: AssetLocation, cache: ImmichCache) async throws -> NSFileProviderItem {
        let size = ChunkingSettings.load().size
        let siblings = try await cache.assets(for: location)
        let layout = DateChunkLayout(monthCounts: DateChunkLayout.counts(of: siblings), size: size)
        return FolderItem(id: dateNodeID(node, location: location), parent: dateParentID(of: node, location: location, layout: layout), filename: dateNodeName(node, layout: layout))
    }

    private static func error(_ code: NSFileProviderError.Code) -> NSError {
        NSError(domain: NSFileProviderErrorDomain, code: code.rawValue)
    }

    private static func readOnlyError() -> NSError {
        NSError(domain: NSCocoaErrorDomain, code: NSFeatureUnsupportedError)
    }

    private static func writeTemporary(data: Data, filename: String) throws -> URL {
        let safeName = filename.replacingOccurrences(of: "/", with: "_")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(safeName)")
        // Owner-only from creation: the decoded original is a private photo, so keep
        // it out of reach of other same-user processes while it sits in the temp dir.
        guard FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        return url
    }

    nonisolated(unsafe) private static let uploadDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func isoString(_ date: Date?) -> String {
        uploadDateFormatter.string(from: date ?? Date())
    }

    // Tells the system a container's contents changed so it re-enumerates and
    // a currently-open Finder window refreshes right after a local write.
    private static func signalChange(domain: NSFileProviderDomain, container: NSFileProviderItemIdentifier) {
        NSFileProviderManager(for: domain)?.signalEnumerator(for: container) { error in
            if let error {
                fileProviderLog.error("signalEnumerator failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // Names an album folder the same way enumeration does, so the item returned
    // by item(for:)/createItem/rename always matches what the Albums listing
    // reports for the same identifier.
    private static func albumItem(for album: AlbumSummary, in albums: [AlbumSummary]) -> AlbumItem {
        let counts = nameCounts(albums.map { $0.albumName })
        let filename = disambiguatedName(base: album.albumName, id: album.albumID, counts: counts)
        return AlbumItem(album: album, filename: filename)
    }

    private static func personItem(for person: PersonSummary, in people: [PersonSummary]) -> FolderItem {
        let counts = nameCounts(people.map { $0.name ?? "" })
        let filename = disambiguatedName(base: person.name ?? "", id: person.personID, counts: counts)
        return FolderItem(id: .person(person.personID), parent: .peopleSection, filename: filename)
    }

    private static func tagItem(for tag: TagSummary, in tags: [TagSummary]) -> FolderItem {
        let counts = nameCounts(tags.map { $0.name })
        let filename = disambiguatedName(base: tag.name, id: tag.tagID, counts: counts)
        return FolderItem(id: .tag(tag.tagID), parent: .tagsSection, filename: filename)
    }
}

extension FileProviderExtension: NSFileProviderThumbnailing {
    func fetchThumbnails(for itemIdentifiers: [NSFileProviderItemIdentifier], requestedSize size: CGSize, perThumbnailCompletionHandler: @escaping (NSFileProviderItemIdentifier, Data?, Error?) -> Void, completionHandler: @escaping (Error?) -> Void) -> Progress {
        nonisolated(unsafe) let perThumbnailCompletionHandler = perThumbnailCompletionHandler
        nonisolated(unsafe) let completionHandler = completionHandler
        let progress = Progress(totalUnitCount: Int64(itemIdentifiers.count))
        guard let client else {
            completionHandler(Self.error(.notAuthenticated))
            return progress
        }
        Task {
            await withTaskGroup(of: Void.self) { group in
                for identifier in itemIdentifiers {
                    guard let assetID = ItemID(identifier).assetRef?.assetID else {
                        perThumbnailCompletionHandler(identifier, nil, Self.error(.noSuchItem))
                        continue
                    }
                    group.addTask {
                        do {
                            let data = try await client.downloadThumbnail(assetID: assetID, size: nil)
                            perThumbnailCompletionHandler(identifier, data, nil)
                        } catch {
                            perThumbnailCompletionHandler(identifier, nil, fileProviderError(from: error))
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
