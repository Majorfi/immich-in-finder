import Foundation
import FileProvider

// Per-container asset cache. Memoizes the in-flight Task (not just the result)
// so concurrent first-time requests for the same container share one fetch
// instead of each hitting the network. Failed fetches are not cached.
actor ImmichCache {
    private let client: ImmichClient
    private var albumListTask: Task<[AlbumSummary], Error>?
    private var peopleListTask: Task<[PersonSummary], Error>?
    private var cityListTask: Task<[PlaceSummary], Error>?
    private var tagListTask: Task<[TagSummary], Error>?
    private var assetTasks: [String: Task<[Asset], Error>] = [:]
    private var timelineYearsTask: Task<[Int], Never>?
    private var timelineMonthsTasks: [String: Task<[String], Never>] = [:]

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

    // One fetch path for every asset container; the location decides both the
    // cache key and which server query backs it.
    func assets(for location: AssetLocation) async throws -> [Asset] {
        let client = self.client
        return try await cachedAssets(key: location.cacheKey) {
            switch location {
            case .album(let id):                return try await client.searchAllAlbum(albumID: id)
            case .month(let yearMonth):         return try await client.searchAllMonth(yearMonth: yearMonth)
            case .person(let id):               return try await client.searchAllPerson(personID: id)
            case .place(let country, let city): return try await client.searchAllCity(country: country, city: city)
            case .tag(let id):                  return try await client.searchAllTag(tagID: id)
            case .favorite:                     return try await client.searchAllFavorites()
            }
        }
    }

    func cityList() async throws -> [PlaceSummary] {
        if let existing = cityListTask {
            return try await existing.value
        }
        let client = self.client
        let task = Task { try await client.listCities() }
        cityListTask = task
        do {
            return try await task.value
        } catch {
            cityListTask = nil
            throw error
        }
    }

    func tagList() async throws -> [TagSummary] {
        if let existing = tagListTask {
            return try await existing.value
        }
        let client = self.client
        let task = Task { try await client.listTags() }
        tagListTask = task
        do {
            return try await task.value
        } catch {
            tagListTask = nil
            throw error
        }
    }

    // The timeline year/month lists come from the shared bucket fetch, so
    // memoize them like the other containers instead of re-fetching every pass.
    func timelineYears() async -> [Int] {
        if let existing = timelineYearsTask {
            return await existing.value
        }
        let client = self.client
        let task = Task { await client.nonEmptyYears() }
        timelineYearsTask = task
        return await task.value
    }

    func timelineMonths(year: String) async -> [String] {
        if let existing = timelineMonthsTasks[year] {
            return await existing.value
        }
        let client = self.client
        let task = Task { await client.nonEmptyMonths(year: year) }
        timelineMonthsTasks[year] = task
        return await task.value
    }

    // Write operations drop the memoized fetch for the affected container so the
    // next enumeration re-reads it from the server instead of stale data.
    func invalidateAlbumList() {
        albumListTask = nil
    }

    func invalidate(_ location: AssetLocation) {
        assetTasks[location.cacheKey] = nil
    }

    func invalidateTimeline() {
        timelineYearsTask = nil
        timelineMonthsTasks = [:]
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
        try await cache.assets(for: self)
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
        case .places: return .placesSection
        case .tags: return .tagsSection
        case .favorites: return .favoritesSection
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
    case countries
    case cities(country: String)
    case place(country: String, city: String)
    case tags
    case tag(id: String)
    case favorites
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
                        .map { SectionItem(kind: $0) }
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
                    let assets = try await cache.assets(for: .album(id: id))
                    fileProviderLog.log("enumerated \(assets.count, privacy: .public) assets in album")
                    observer.didEnumerate(immichItems(from: assets, location: .album(id: id)))
                    observer.finishEnumerating(upTo: nil)
                case .years:
                    let years = await cache.timelineYears()
                    fileProviderLog.log("enumerated \(years.count, privacy: .public) timeline years")
                    observer.didEnumerate(years.map { YearItem(year: String($0)) })
                    observer.finishEnumerating(upTo: nil)
                case .months(let year):
                    let months = await cache.timelineMonths(year: year)
                    fileProviderLog.log("enumerated \(months.count, privacy: .public) months in \(year, privacy: .public)")
                    observer.didEnumerate(months.map { MonthItem(yearMonth: $0) })
                    observer.finishEnumerating(upTo: nil)
                case .month(let yearMonth):
                    let assets = try await cache.assets(for: .month(yearMonth: yearMonth))
                    fileProviderLog.log("timeline \(yearMonth, privacy: .public): \(assets.count, privacy: .public) assets")
                    observer.didEnumerate(immichItems(from: assets, location: .month(yearMonth: yearMonth)))
                    observer.finishEnumerating(upTo: nil)
                case .people:
                    let people = try await cache.peopleList()
                    let counts = nameCounts(people.map { $0.name ?? "" })
                    fileProviderLog.log("enumerated \(people.count, privacy: .public) named people")
                    observer.didEnumerate(people.map {
                        FolderItem(id: .person($0.personID), parent: .peopleSection,
                                   filename: disambiguatedName(base: $0.name ?? "", id: $0.personID, counts: counts))
                    })
                    observer.finishEnumerating(upTo: nil)
                case .person(let id):
                    let assets = try await cache.assets(for: .person(id: id))
                    fileProviderLog.log("person \(id, privacy: .public): \(assets.count, privacy: .public) assets")
                    observer.didEnumerate(immichItems(from: assets, location: .person(id: id)))
                    observer.finishEnumerating(upTo: nil)
                case .countries:
                    let places = try await cache.cityList()
                    let countries = Set(places.map { $0.country }).sorted()
                    fileProviderLog.log("enumerated \(countries.count, privacy: .public) countries")
                    observer.didEnumerate(countries.map { FolderItem(id: .country($0), parent: .placesSection, filename: $0) })
                    observer.finishEnumerating(upTo: nil)
                case .cities(let country):
                    let places = try await cache.cityList()
                    let cities = places.filter { $0.country == country }.map { $0.city }.sorted()
                    fileProviderLog.log("enumerated \(cities.count, privacy: .public) cities in \(country, privacy: .public)")
                    observer.didEnumerate(cities.map { FolderItem(id: .city(country: country, city: $0), parent: .country(country), filename: $0) })
                    observer.finishEnumerating(upTo: nil)
                case .place(let country, let city):
                    let assets = try await cache.assets(for: .place(country: country, city: city))
                    fileProviderLog.log("place \(city, privacy: .public): \(assets.count, privacy: .public) assets")
                    observer.didEnumerate(immichItems(from: assets, location: .place(country: country, city: city)))
                    observer.finishEnumerating(upTo: nil)
                case .tags:
                    let tags = try await cache.tagList()
                    let counts = nameCounts(tags.map { $0.name })
                    fileProviderLog.log("enumerated \(tags.count, privacy: .public) tags")
                    observer.didEnumerate(tags.map {
                        FolderItem(id: .tag($0.tagID), parent: .tagsSection,
                                   filename: disambiguatedName(base: $0.name, id: $0.tagID, counts: counts))
                    })
                    observer.finishEnumerating(upTo: nil)
                case .tag(let id):
                    let assets = try await cache.assets(for: .tag(id: id))
                    fileProviderLog.log("tag \(id, privacy: .public): \(assets.count, privacy: .public) assets")
                    observer.didEnumerate(immichItems(from: assets, location: .tag(id: id)))
                    observer.finishEnumerating(upTo: nil)
                case .favorites:
                    let assets = try await cache.assets(for: .favorite)
                    fileProviderLog.log("enumerated \(assets.count, privacy: .public) favorites")
                    observer.didEnumerate(immichItems(from: assets, location: .favorite))
                    observer.finishEnumerating(upTo: nil)
                }
            } catch {
                fileProviderLog.error("enumeration failed for \(String(describing: container), privacy: .public): \(String(describing: error), privacy: .public)")
                observer.finishEnumeratingWithError(fileProviderError(from: error))
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
