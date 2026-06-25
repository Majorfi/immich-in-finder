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
    private var assetCountTasks: [String: Task<Int, Error>] = [:]
    private var timelineYearsTask: Task<[Int], Error>?
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

    // Fetches and memoizes the full membership of an asset container. Backs
    // single-asset resolution (item lookup, fetchContents); enumeration paginates
    // separately so it never holds the whole folder at once.
    func assets(for location: AssetLocation) async throws -> [Asset] {
        let key = location.cacheKey
        if let existing = assetTasks[key] {
            return try await existing.value
        }
        let client = self.client
        let search = location.search
        let task = Task { try await client.searchAllViaPage(for: search, size: 1000) }
        assetTasks[key] = task
        do {
            return try await task.value
        } catch {
            assetTasks[key] = nil
            throw error
        }
    }

    // Total asset count for a container, memoized like the asset lists. Backs the
    // chunk-folder split: cheap (one /search/statistics call) so opening a large
    // folder can list its chunk sub-folders without fetching every asset.
    func assetCount(for location: AssetLocation) async throws -> Int {
        let key = location.cacheKey
        if let existing = assetCountTasks[key] {
            return try await existing.value
        }
        let client = self.client
        let search = location.search
        let task = Task { try await client.searchStatistics(for: search) }
        assetCountTasks[key] = task
        do {
            return try await task.value
        } catch {
            assetCountTasks[key] = nil
            throw error
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
    // Years evict on failure rather than caching an empty list, so a transient
    // bucket-fetch error retries on the next pass instead of sticking.
    func timelineYears() async throws -> [Int] {
        if let existing = timelineYearsTask {
            return try await existing.value
        }
        let client = self.client
        let task = Task { try await client.nonEmptyYears() }
        timelineYearsTask = task
        do {
            return try await task.value
        } catch {
            timelineYearsTask = nil
            throw error
        }
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
        assetCountTasks[location.cacheKey] = nil
    }

    func invalidateTimeline() {
        timelineYearsTask = nil
        timelineMonthsTasks = [:]
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
    case chunk(location: AssetLocation, index: Int)
    case dateYear(location: AssetLocation, year: String)
    case dateMonth(location: AssetLocation, yearMonth: String)
    case datePage(location: AssetLocation, yearMonth: String, page: Int)
}

// Decodes the 1-based page number from a File Provider page cursor. The two
// system sentinels and an empty cursor both mean the first page.
func immichPageNumber(from page: NSFileProviderPage) -> Int {
    let raw = page.rawValue
    let isInitial = raw == NSFileProviderPage.initialPageSortedByName as Data
        || raw == NSFileProviderPage.initialPageSortedByDate as Data
    if isInitial || raw.isEmpty {
        return 1
    }
    return Int(String(decoding: raw, as: UTF8.self)) ?? 1
}

// Fetches one /search/metadata page for a container and hands it to the observer,
// finishing with the next page cursor while pages remain. The system re-enters
// enumerateItems with that cursor, so the extension only ever holds one page,
// which keeps memory bounded even for very large folders. A free function so the
// enclosing Task never captures the non-Sendable ItemEnumerator.
func enumerateAssetPage(_ location: AssetLocation, client: ImmichClient, page: NSFileProviderPage, observer: NSFileProviderEnumerationObserver) async throws {
    let pageNumber = immichPageNumber(from: page)
    let result = try await client.searchPage(for: location.search, page: pageNumber, size: 1000)
    observer.didEnumerate(immichItems(from: result.assets, location: location))
    if result.hasMore {
        observer.finishEnumerating(upTo: NSFileProviderPage(Data(String(pageNumber + 1).utf8)))
    } else {
        observer.finishEnumerating(upTo: nil)
    }
}

// Enumerates an asset container under the active chunking strategy. The date
// strategy (for locations that support it) groups by year/month; otherwise the
// page strategy splits into fixed-size slices when over the size; otherwise the
// assets page directly. Listing page chunks needs only the count; the date
// strategy needs the full membership, which it reuses for grouping and slicing.
func enumerateAssetContainer(_ location: AssetLocation, cache: ImmichCache, client: ImmichClient, page: NSFileProviderPage, observer: NSFileProviderEnumerationObserver) async throws {
    let settings = ChunkingSettings.load()
    if settings.enabled, settings.strategy == .date, location.supportsDateChunking {
        try await enumerateDateContainer(location, node: nil, cache: cache, observer: observer)
        return
    }
    if settings.enabled {
        let count = try await cache.assetCount(for: location)
        if settings.isChunked(count: count) {
            let chunks = settings.chunkCount(for: count)
            fileProviderLog.log("chunking \(location.cacheKey, privacy: .public): \(count, privacy: .public) assets into \(chunks, privacy: .public) folders")
            let items = (0..<chunks).map { ChunkFolderItem(location: location, index: $0, size: settings.size, totalCount: count) }
            observer.didEnumerate(items)
            observer.finishEnumerating(upTo: nil)
            return
        }
    }
    try await enumerateAssetPage(location, client: client, page: page, observer: observer)
}

// The ItemID and display name a layout node maps to for this location.
func dateNodeID(_ node: DateChunkNode, location: AssetLocation) -> ItemID {
    switch node {
    case .year(let year):           return .dateYear(location: location, year: year)
    case .month(let yearMonth):     return .dateMonth(location: location, yearMonth: yearMonth)
    case .page(let yearMonth, let index): return .datePage(location: location, yearMonth: yearMonth, page: index)
    }
}

// The ItemID a date node reports as its parent: its parent node, or the
// container itself when that node sits at the top after collapsing.
func dateParentID(of node: DateChunkNode, location: AssetLocation, layout: DateChunkLayout) -> ItemID {
    guard let parent = layout.parentNode(of: node) else {
        return location.parentItemID
    }
    return dateNodeID(parent, location: location)
}

func dateNodeName(_ node: DateChunkNode, layout: DateChunkLayout) -> String {
    switch node {
    case .year(let year):       return year
    case .month(let yearMonth): return monthDisplayName(yearMonth)
    case .page(let yearMonth, let index):
        return chunkRangeLabel(index: index, size: layout.size, total: layout.count(month: yearMonth))
    }
}

// Enumerates one node of the date tree (nil = the container itself). The whole
// membership is fetched once and reused for both grouping and slicing, so every
// level reads the same order:.asc list the resolver also sees.
func enumerateDateContainer(_ location: AssetLocation, node: DateChunkNode?, cache: ImmichCache, observer: NSFileProviderEnumerationObserver) async throws {
    let size = ChunkingSettings.load().size
    let siblings = try await cache.assets(for: location)
    let layout = DateChunkLayout(monthCounts: DateChunkLayout.counts(of: siblings), size: size)

    // A page node is a leaf: deliver its month slice directly.
    if case .page(let yearMonth, let index) = node {
        let monthAssets = siblings.filter { DateChunkLayout.month(of: $0) == yearMonth }
        let slice = Array(monthAssets[chunkSlice(index: index, size: size, total: monthAssets.count)])
        observer.didEnumerate(immichItems(from: slice, location: location, parent: dateNodeID(.page(month: yearMonth, index: index), location: location)))
        observer.finishEnumerating(upTo: nil)
        return
    }

    // The container's own identifier, used as the parent of whatever it emits.
    let containerID: ItemID
    let children: DateChunkChildren
    switch node {
    case .year(let year):
        containerID = .dateYear(location: location, year: year)
        children = layout.yearChildren(year)
    case .month(let yearMonth):
        containerID = .dateMonth(location: location, yearMonth: yearMonth)
        children = layout.monthChildren(yearMonth)
    default:
        containerID = location.parentItemID
        if siblings.count <= size {
            observer.didEnumerate(immichItems(from: siblings, location: location))
            observer.finishEnumerating(upTo: nil)
            return
        }
        children = layout.rootChildren()
    }

    switch children {
    case .folders(let nodes):
        fileProviderLog.log("date chunking \(location.cacheKey, privacy: .public): \(nodes.count, privacy: .public) folders under \(containerID.identifier.rawValue, privacy: .public)")
        observer.didEnumerate(nodes.map { FolderItem(id: dateNodeID($0, location: location), parent: containerID, filename: dateNodeName($0, layout: layout)) })
    case .assets(let yearMonth):
        let monthAssets = siblings.filter { DateChunkLayout.month(of: $0) == yearMonth }
        observer.didEnumerate(immichItems(from: monthAssets, location: location, parent: containerID))
    }
    observer.finishEnumerating(upTo: nil)
}

// Enumerates one chunk: a single /search/metadata page sized to the chunk size,
// so the chunk holds exactly its slice. The page boundary matches the index math
// the resolver uses (both over order:.asc), so an asset always lands in the chunk
// folder that was listed for it.
func enumerateChunkPage(_ location: AssetLocation, index: Int, client: ImmichClient, observer: NSFileProviderEnumerationObserver) async throws {
    let size = ChunkingSettings.load().size
    let result = try await client.searchPage(for: location.search, page: index + 1, size: size)
    observer.didEnumerate(immichItems(from: result.assets, location: location, parent: ItemID.chunk(location: location, index: index)))
    observer.finishEnumerating(upTo: nil)
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
        // Asset containers paginate: each call fetches one page and finishes with
        // the next cursor, so the system re-enters with it. Finder paints the
        // folder only at the final finishEnumerating, but memory stays bounded to
        // one page, which is what lets very large folders load at all.
        let container = self.container
        let cache = self.cache
        let client = self.client
        let page = page
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
                    try await enumerateAssetContainer(.album(id: id), cache: cache, client: client, page: page, observer: observer)
                case .years:
                    let years = try await cache.timelineYears()
                    fileProviderLog.log("enumerated \(years.count, privacy: .public) timeline years")
                    observer.didEnumerate(years.map { YearItem(year: String($0)) })
                    observer.finishEnumerating(upTo: nil)
                case .months(let year):
                    let months = await cache.timelineMonths(year: year)
                    fileProviderLog.log("enumerated \(months.count, privacy: .public) months in \(year, privacy: .public)")
                    observer.didEnumerate(months.map { MonthItem(yearMonth: $0) })
                    observer.finishEnumerating(upTo: nil)
                case .month(let yearMonth):
                    try await enumerateAssetContainer(.month(yearMonth: yearMonth), cache: cache, client: client, page: page, observer: observer)
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
                    try await enumerateAssetContainer(.person(id: id), cache: cache, client: client, page: page, observer: observer)
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
                    try await enumerateAssetContainer(.place(country: country, city: city), cache: cache, client: client, page: page, observer: observer)
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
                    try await enumerateAssetContainer(.tag(id: id), cache: cache, client: client, page: page, observer: observer)
                case .favorites:
                    try await enumerateAssetContainer(.favorite, cache: cache, client: client, page: page, observer: observer)
                case .chunk(let location, let index):
                    try await enumerateChunkPage(location, index: index, client: client, observer: observer)
                case .dateYear(let location, let year):
                    try await enumerateDateContainer(location, node: .year(year), cache: cache, observer: observer)
                case .dateMonth(let location, let yearMonth):
                    try await enumerateDateContainer(location, node: .month(yearMonth), cache: cache, observer: observer)
                case .datePage(let location, let yearMonth, let pageIndex):
                    try await enumerateDateContainer(location, node: .page(month: yearMonth, index: pageIndex), cache: cache, observer: observer)
                }
            } catch {
                fileProviderLog.error("enumeration failed for \(String(describing: container), privacy: .public): \(String(describing: error), privacy: .public)")
                observer.finishEnumeratingWithError(fileProviderError(from: error))
            }
        }
    }

    // Findich does not drive a per-folder change feed. In the replicated model the
    // system only honors working-set signals and paints a folder only at its final
    // finishEnumerating, so a change round reports nothing against the same anchor.
    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    // No sync anchor: Findich has no incremental change feed. A nil anchor makes
    // the system re-run the full enumerateItems on every reopen and after every
    // signalEnumerator, instead of calling the no-op enumerateChanges. A constant
    // non-nil anchor (what this used to return) wrongly told the system the
    // container never changes, so it stopped re-enumerating and served a stale or
    // empty snapshot (folders not painting until you left and came back).
    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(nil)
    }
}
