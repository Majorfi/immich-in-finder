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
        default:
            return nil
        }
    }

    // The inverse of init(_:). Keeping construction here, next to the parser,
    // is what keeps the two halves of the identifier grammar from drifting —
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
        case .other:
            return NSFileProviderItemIdentifier(rawValue: "")
        }
    }
}

final class FileProviderExtension: NSObject, NSFileProviderReplicatedExtension {
    private let client: ImmichClient?
    private let cache: ImmichCache?
    private let domain: NSFileProviderDomain

    required init(domain: NSFileProviderDomain) {
        self.domain = domain
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
            completionHandler(SectionItem(id: ItemID.albumsSection.identifier.rawValue, name: SectionKind.albums.displayName), nil)
        case .timelineSection:
            completionHandler(SectionItem(id: ItemID.timelineSection.identifier.rawValue, name: SectionKind.timeline.displayName), nil)
        case .peopleSection:
            completionHandler(SectionItem(id: ItemID.peopleSection.identifier.rawValue, name: SectionKind.people.displayName), nil)
        case .placesSection:
            completionHandler(SectionItem(id: ItemID.placesSection.identifier.rawValue, name: SectionKind.places.displayName), nil)
        case .year(let year):
            completionHandler(YearItem(year: year), nil)
        case .month(let yearMonth):
            completionHandler(MonthItem(yearMonth: yearMonth), nil)
        case .country(let name):
            completionHandler(CountryItem(name: name), nil)
        case .city(let country, let city):
            completionHandler(CityItem(country: country, city: city), nil)
        case .person(let personID):
            guard let cache else {
                completionHandler(nil, Self.error(.notAuthenticated))
                return progress
            }
            Task {
                do {
                    let people = try await cache.peopleList()
                    guard let person = people.first(where: { $0.id == personID }) else {
                        completionHandler(nil, Self.error(.noSuchItem))
                        progress.completedUnitCount = 1
                        return
                    }
                    completionHandler(Self.personItem(for: person, in: people), nil)
                } catch {
                    completionHandler(nil, error)
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
                    completionHandler(nil, error)
                }
                progress.completedUnitCount = 1
            }
            return progress
        case .asset, .timelineAsset, .personAsset, .placeAsset, .other:
            completionHandler(nil, Self.error(.noSuchItem))
        }
        progress.completedUnitCount = 1
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
        case .asset, .timelineAsset, .personAsset, .placeAsset:
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
                    completionHandler(nil, [], false, error)
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
                let data = try Data(contentsOf: url)
                let result = try await client.uploadAsset(filename: filename, data: data, createdAt: createdAt, modifiedAt: modifiedAt)
                try await client.addAssets(albumID: albumID, assetIDs: [result.id])
                await cache.invalidate(album: albumID)
                fileProviderLog.log("uploaded \(result.id, privacy: .public) (duplicate: \(result.isDuplicate, privacy: .public)) → album \(albumID, privacy: .public)")
                // Return the asset as the server now reports it, so the item's
                // filename is disambiguated and its content version (checksum)
                // matches enumeration — avoiding a ghost entry and an immediate
                // redundant re-download of the file we just uploaded.
                let siblings = try await cache.assets(album: albumID)
                guard let resolved = resolveAsset(result.id, in: siblings) else {
                    completionHandler(nil, [], false, Self.error(.noSuchItem))
                    progress.completedUnitCount = 1
                    return
                }
                completionHandler(ImmichItem(asset: resolved.asset, location: .album(id: albumID), filename: resolved.filename), [], false, nil)
                Self.signalChange(domain: domain, container: ItemID.album(albumID).identifier)
            } catch {
                fileProviderLog.error("upload failed for \(filename, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(nil, [], false, error)
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
                    let album = try await client.renameAlbum(id: albumID, name: newName)
                    await cache.invalidateAlbumList()
                    fileProviderLog.log("renamed album \(albumID, privacy: .public)")
                    let albums = try await cache.albumList()
                    completionHandler(Self.albumItem(for: album, in: albums), [], false, nil)
                    Self.signalChange(domain: domain, container: ItemID.albumsSection.identifier)
                } catch {
                    fileProviderLog.error("renameAlbum failed: \(error.localizedDescription, privacy: .public)")
                    completionHandler(nil, [], false, error)
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
                    await cache.invalidate(album: srcAlbum)
                    await cache.invalidate(album: destAlbum)
                    let siblings = try await cache.assets(album: destAlbum)
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
                    completionHandler(nil, [], false, error)
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
                switch ref.location {
                case .album(let id):
                    await cache.invalidate(album: id)
                case .month(let yearMonth):
                    await cache.invalidate(month: yearMonth)
                case .person(let id):
                    await cache.invalidate(person: id)
                case .place(let country, let city):
                    await cache.invalidate(country: country, city: city)
                }
                fileProviderLog.log("trashed asset \(ref.assetID, privacy: .public)")
                completionHandler(nil)
                Self.signalChange(domain: domain, container: Self.containerIdentifier(for: ref.location))
            } catch {
                fileProviderLog.error("trash failed for \(ref.assetID, privacy: .public): \(error.localizedDescription, privacy: .public)")
                completionHandler(error)
            }
            progress.completedUnitCount = 1
        }
        return progress
    }

    // Static so the async Tasks below can call it without capturing self (a
    // non-Sendable NSObject), which Swift 6 region isolation forbids.
    private static func resolve(_ ref: (assetID: String, location: AssetLocation), cache: ImmichCache) async throws -> (asset: Asset, filename: String)? {
        let siblings = try await ref.location.siblings(from: cache)
        return resolveAsset(ref.assetID, in: siblings)
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
        try data.write(to: url)
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

    private static func containerIdentifier(for location: AssetLocation) -> NSFileProviderItemIdentifier {
        switch location {
        case .album(let id):
            return ItemID.album(id).identifier
        case .month(let yearMonth):
            return ItemID.month(yearMonth).identifier
        case .person(let id):
            return ItemID.person(id).identifier
        case .place(let country, let city):
            return ItemID.city(country: country, city: city).identifier
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

    private static func personItem(for person: PersonSummary, in people: [PersonSummary]) -> PersonItem {
        let counts = nameCounts(people.map { $0.name ?? "" })
        let filename = disambiguatedName(base: person.name ?? "", id: person.id, counts: counts)
        return PersonItem(id: person.id, filename: filename)
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
