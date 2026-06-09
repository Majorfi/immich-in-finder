import Foundation
import FileProvider

// Per-container asset cache. Memoizes the in-flight Task (not just the result)
// so concurrent first-time requests for the same container share one fetch
// instead of each hitting the network. Failed fetches are not cached.
actor ImmichCache {
    private let client: ImmichClient
    private var albumListTask: Task<[AlbumSummary], Error>?
    private var peopleListTask: Task<[PersonSummary], Error>?
    private var assetTasks: [String: Task<[Asset], Error>] = [:]

    init(client: ImmichClient) {
        self.client = client
    }

    func albumList() async throws -> [AlbumSummary] {
        if let existing = albumListTask {
            return try await existing.value
        }
        let client = self.client
        let task = Task { try await client.listAlbums() }
        albumListTask = task
        do {
            return try await task.value
        } catch {
            albumListTask = nil
            throw error
        }
    }

    func peopleList() async throws -> [PersonSummary] {
        if let existing = peopleListTask {
            return try await existing.value
        }
        let client = self.client
        let task = Task { try await client.listPeople() }
        peopleListTask = task
        do {
            return try await task.value
        } catch {
            peopleListTask = nil
            throw error
        }
    }

    func assets(album albumID: String) async throws -> [Asset] {
        let client = self.client
        return try await cachedAssets(key: "album:\(albumID)") {
            try await client.searchAllAlbum(albumID: albumID)
        }
    }

    func assets(month yearMonth: String) async throws -> [Asset] {
        let client = self.client
        return try await cachedAssets(key: "month:\(yearMonth)") {
            try await client.searchAllMonth(yearMonth: yearMonth)
        }
    }

    func assets(person personID: String) async throws -> [Asset] {
        let client = self.client
        return try await cachedAssets(key: "person:\(personID)") {
            try await client.searchAllPerson(personID: personID)
        }
    }

    // Write operations drop the memoized fetch for the affected container so the
    // next enumeration re-reads it from the server instead of stale data.
    func invalidateAlbumList() {
        albumListTask = nil
    }

    func invalidate(album albumID: String) {
        assetTasks["album:\(albumID)"] = nil
    }

    func invalidate(month yearMonth: String) {
        assetTasks["month:\(yearMonth)"] = nil
    }

    func invalidate(person personID: String) {
        assetTasks["person:\(personID)"] = nil
    }

    private func cachedAssets(key: String, fetch: @Sendable @escaping () async throws -> [Asset]) async throws -> [Asset] {
        if let existing = assetTasks[key] {
            return try await existing.value
        }
        let task = Task { try await fetch() }
        assetTasks[key] = task
        do {
            return try await task.value
        } catch {
            assetTasks[key] = nil
            throw error
        }
    }
}

extension AssetLocation {
    func siblings(from cache: ImmichCache) async throws -> [Asset] {
        switch self {
        case .album(let id):
            return try await cache.assets(album: id)
        case .month(let yearMonth):
            return try await cache.assets(month: yearMonth)
        case .person(let id):
            return try await cache.assets(person: id)
        }
    }
}

extension SectionKind {
    // SectionKind lives in Shared (no FileProvider import), so the mapping to the
    // identifier grammar is defined here, next to ItemID.
    var itemID: ItemID {
        switch self {
        case .albums: return .albumsSection
        case .timeline: return .timelineSection
        case .people: return .peopleSection
        }
    }
}

enum EnumeratedContainer {
    case sections
    case albums
    case album(id: String)
    case years
    case months(year: String)
    case month(yearMonth: String)
    case people
    case person(id: String)
}

final class ItemEnumerator: NSObject, NSFileProviderEnumerator {
    private let client: ImmichClient
    private let cache: ImmichCache
    private let container: EnumeratedContainer

    init(client: ImmichClient, cache: ImmichCache, container: EnumeratedContainer) {
        self.client = client
        self.cache = cache
        self.container = container
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        // Bind the Sendable stored properties to locals so the Task does not
        // capture self (a non-Sendable NSObject), per Swift 6 region isolation.
        let container = self.container
        let cache = self.cache
        let client = self.client
        // The system's enumeration observer is not Sendable but is documented to
        // accept callbacks from any thread, so crossing into the Task is safe.
        nonisolated(unsafe) let observer = observer
        Task {
            do {
                switch container {
                case .sections:
                    let visible = VisibleSections.load()
                    let items = SectionKind.allCases
                        .filter { visible.contains($0) }
                        .map { SectionItem(id: $0.itemID.identifier.rawValue, name: $0.displayName) }
                    observer.didEnumerate(items)
                    observer.finishEnumerating(upTo: nil)
                case .albums:
                    let albums = try await cache.albumList()
                    let counts = nameCounts(albums.map { $0.albumName })
                    fileProviderLog.log("enumerated \(albums.count, privacy: .public) albums")
                    observer.didEnumerate(albums.map {
                        AlbumItem(album: $0, filename: disambiguatedName(base: $0.albumName, id: $0.albumID, counts: counts))
                    })
                    observer.finishEnumerating(upTo: nil)
                case .album(let id):
                    let assets = try await cache.assets(album: id)
                    fileProviderLog.log("enumerated \(assets.count, privacy: .public) assets in album")
                    observer.didEnumerate(immichItems(from: assets, location: .album(id: id)))
                    observer.finishEnumerating(upTo: nil)
                case .years:
                    guard let range = try await client.assetYearRange() else {
                        observer.didEnumerate([])
                        observer.finishEnumerating(upTo: nil)
                        return
                    }
                    let years = await client.nonEmptyYears(oldest: range.oldest, newest: range.newest)
                    fileProviderLog.log("enumerated \(years.count, privacy: .public) timeline years")
                    observer.didEnumerate(years.map { YearItem(year: String($0)) })
                    observer.finishEnumerating(upTo: nil)
                case .months(let year):
                    let months = await client.nonEmptyMonths(year: year)
                    fileProviderLog.log("enumerated \(months.count, privacy: .public) months in \(year, privacy: .public)")
                    observer.didEnumerate(months.map { MonthItem(yearMonth: $0) })
                    observer.finishEnumerating(upTo: nil)
                case .month(let yearMonth):
                    let assets = try await cache.assets(month: yearMonth)
                    fileProviderLog.log("timeline \(yearMonth, privacy: .public): \(assets.count, privacy: .public) assets")
                    observer.didEnumerate(immichItems(from: assets, location: .month(yearMonth: yearMonth)))
                    observer.finishEnumerating(upTo: nil)
                case .people:
                    let people = try await cache.peopleList()
                    let counts = nameCounts(people.map { $0.name ?? "" })
                    fileProviderLog.log("enumerated \(people.count, privacy: .public) named people")
                    observer.didEnumerate(people.map {
                        PersonItem(id: $0.id, filename: disambiguatedName(base: $0.name ?? "", id: $0.id, counts: counts))
                    })
                    observer.finishEnumerating(upTo: nil)
                case .person(let id):
                    let assets = try await cache.assets(person: id)
                    fileProviderLog.log("person \(id, privacy: .public): \(assets.count, privacy: .public) assets")
                    observer.didEnumerate(immichItems(from: assets, location: .person(id: id)))
                    observer.finishEnumerating(upTo: nil)
                }
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("anchor-v1".utf8)))
    }
}
