import Foundation
import FileProvider
import UniformTypeIdentifiers

enum AssetLocation {
    case album(id: String)
    case month(yearMonth: String)
    case person(id: String)
    case place(country: String, city: String)
    case tag(id: String)
    case favorite
}

extension AssetLocation {
    // One home for the three things every location must agree on, so the
    // identifier grammar, parenting, and cache keys can't drift across the many
    // switches that would otherwise each mirror AssetLocation.

    // The identifier of a specific asset living at this location.
    func assetItemID(_ assetID: String) -> ItemID {
        switch self {
        case .album(let id):                return .asset(albumID: id, assetID: assetID)
        case .month(let yearMonth):         return .timelineAsset(yearMonth: yearMonth, assetID: assetID)
        case .person(let id):               return .personAsset(personID: id, assetID: assetID)
        case .place(let country, let city): return .placeAsset(country: country, city: city, assetID: assetID)
        case .tag(let id):                  return .tagAsset(tagID: id, assetID: assetID)
        case .favorite:                     return .favoriteAsset(assetID: assetID)
        }
    }

    // The container these assets are children of. Favorites are direct children
    // of the section; every other location has an intermediate folder parent.
    var parentItemID: ItemID {
        switch self {
        case .album(let id):                return .album(id)
        case .month(let yearMonth):         return .month(yearMonth)
        case .person(let id):               return .person(id)
        case .place(let country, let city): return .city(country: country, city: city)
        case .tag(let id):                  return .tag(id)
        case .favorite:                     return .favoritesSection
        }
    }

    // Key under which this location's asset list is memoized in ImmichCache.
    var cacheKey: String {
        switch self {
        case .album(let id):                return "album:\(id)"
        case .month(let yearMonth):         return "month:\(yearMonth)"
        case .person(let id):               return "person:\(id)"
        case .place(let country, let city): return "place:\(country):\(city)"
        case .tag(let id):                  return "tag:\(id)"
        case .favorite:                     return "favorites"
        }
    }

    // A compact, reversible encoding embedded inside a chunk folder's identifier
    // (chunk:<index>:<code>), so a chunk knows which location it slices. Country
    // is assumed colon-free (the same assumption the qasset identifier makes), so
    // the city, last, may contain anything.
    var code: String {
        switch self {
        case .album(let id):                return "a:\(id)"
        case .month(let yearMonth):         return "m:\(yearMonth)"
        case .person(let id):               return "p:\(id)"
        case .place(let country, let city): return "c:\(country):\(city)"
        case .tag(let id):                  return "t:\(id)"
        case .favorite:                     return "f"
        }
    }

    init?(code: String) {
        if code == "f" {
            self = .favorite
            return
        }
        if code.hasPrefix("a:") {
            self = .album(id: String(code.dropFirst(2)))
            return
        }
        if code.hasPrefix("m:") {
            self = .month(yearMonth: String(code.dropFirst(2)))
            return
        }
        if code.hasPrefix("p:") {
            self = .person(id: String(code.dropFirst(2)))
            return
        }
        if code.hasPrefix("t:") {
            self = .tag(id: String(code.dropFirst(2)))
            return
        }
        if code.hasPrefix("c:") {
            let parts = code.dropFirst(2).split(separator: ":", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                self = .place(country: parts[0], city: parts[1])
                return
            }
        }
        return nil
    }

    // Whether the date strategy groups this location into year/month folders. The
    // grouping comes from each asset's capture date in the fetched membership, so
    // it could technically apply anywhere; it is deliberately left off for the
    // Timeline months (a month is already the finest date unit) and for Places,
    // which stay on page chunks. Albums, People, Tags, and Favorites get the tree.
    var supportsDateChunking: Bool {
        switch self {
        case .album, .person, .tag, .favorite: return true
        case .month, .place:                   return false
        }
    }

    // The paged /search/metadata query backing this location, so the one-to-one
    // location->search mapping lives here instead of being spelled out at every
    // call site that needs a page.
    var search: AssetSearch {
        switch self {
        case .album(let id):                return .album(id: id)
        case .month(let yearMonth):         return .month(yearMonth: yearMonth)
        case .person(let id):               return .person(id: id)
        case .place(let country, let city): return .place(country: country, city: city)
        case .tag(let id):                  return .tag(id: id)
        case .favorite:                     return .favorite
        }
    }
}

// Month symbol names, computed once. Read-only and value-typed, so safe to share.
private let monthSymbolNames: [String] = DateFormatter().standaloneMonthSymbols ?? []

// "2024-03" -> "03 - March", falling back to the raw month number. Shared by the
// Timeline month folders and the date strategy's month folders.
func monthDisplayName(_ yearMonth: String) -> String {
    let monthNumber = Int(yearMonth.suffix(2)) ?? 0
    if monthNumber >= 1, monthNumber <= monthSymbolNames.count {
        return String(format: "%02d - %@", monthNumber, monthSymbolNames[monthNumber - 1].capitalized)
    }
    return String(yearMonth.suffix(2))
}

func nameCounts(_ names: [String]) -> [String: Int] {
    var counts: [String: Int] = [:]
    for name in names {
        counts[name, default: 0] += 1
    }
    return counts
}

// Keeps a name intact unless it collides with another in the same container,
// in which case a short id fragment is inserted before the extension. The rule
// is deterministic given the sibling counts, so enumeration and item(for:) agree.
func disambiguatedName(base: String, id: String, counts: [String: Int]) -> String {
    if (counts[base] ?? 0) <= 1 {
        return base
    }
    let fragment = String(id.prefix(8))
    let nsBase = base as NSString
    let ext = nsBase.pathExtension
    let stem = nsBase.deletingPathExtension
    if ext.isEmpty {
        return "\(stem) (\(fragment))"
    }
    return "\(stem) (\(fragment)).\(ext)"
}

// The single chokepoint that turns a container's asset list into items, so
// enumeration and single-item resolution name files identically. When `parent` is
// set, the items report that sub-folder as their parent instead of the container
// itself (a page folder, or a date folder for the date strategy).
func immichItems(from assets: [Asset], location: AssetLocation, parent: ItemID? = nil) -> [ImmichItem] {
    let counts = nameCounts(assets.map { $0.originalFileName })
    return assets.map {
        ImmichItem(asset: $0, location: location, filename: disambiguatedName(base: $0.originalFileName, id: $0.assetID, counts: counts), parent: parent)
    }
}

func resolveAsset(_ assetID: String, in assets: [Asset]) -> (asset: Asset, filename: String)? {
    guard let asset = assets.first(where: { $0.assetID == assetID }) else {
        return nil
    }
    let counts = nameCounts(assets.map { $0.originalFileName })
    let filename = disambiguatedName(base: asset.originalFileName, id: assetID, counts: counts)
    return (asset, filename)
}

final class ImmichItem: NSObject, NSFileProviderItem {
    private let asset: Asset
    private let location: AssetLocation
    private let displayName: String
    private let parentOverride: ItemID?

    init(asset: Asset, location: AssetLocation, filename: String, parent: ItemID? = nil) {
        self.asset = asset
        self.location = location
        self.displayName = filename
        self.parentOverride = parent
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        location.assetItemID(asset.assetID).identifier
    }

    // When the asset lives in a chunked container its parent is the sub-folder it
    // was enumerated under (a page folder, or a year/month folder for the date
    // strategy); the asset's own identity is unchanged so every write path keeps
    // resolving it the same way.
    var parentItemIdentifier: NSFileProviderItemIdentifier {
        if let parentOverride {
            return parentOverride.identifier
        }
        return location.parentItemID.identifier
    }

    var filename: String {
        displayName
    }

    var contentType: UTType {
        let ext = (asset.originalFileName as NSString).pathExtension
        if ext.isEmpty == false, let type = UTType(filenameExtension: ext) {
            return type
        }
        switch asset.type {
        case .image: return .image
        case .video: return .movie
        case .audio: return .audio
        case .other: return .data
        }
    }

    var capabilities: NSFileProviderItemCapabilities {
        // Deleting maps to moving the asset to the Immich trash. Assets in an
        // album can be moved to another album; Timeline assets cannot (their
        // month is derived from the capture date, not a real membership).
        switch location {
        case .album:
            return [.allowsReading, .allowsDeleting, .allowsReparenting]
        case .month, .person, .place, .tag, .favorite:
            return [.allowsReading, .allowsDeleting]
        }
    }

    // Modern replacement for the deprecated `.allowsEvicting` capability
    // (deprecated macOS 13): originals are placeholders fetched on demand via
    // fetchContents and may be evicted to reclaim space, evicting the local
    // copy when the remote version changes.
    var contentPolicy: NSFileProviderContentPolicy {
        .downloadLazilyAndEvictOnRemoteUpdate
    }

    var documentSize: NSNumber? {
        guard let size = asset.exifInfo?.fileSizeInByte else { return nil }
        return NSNumber(value: size)
    }

    var creationDate: Date? {
        ImmichItem.parseDate(asset.fileCreatedAt)
    }

    var contentModificationDate: Date? {
        guard let modified = asset.fileModifiedAt else { return nil }
        return ImmichItem.parseDate(modified)
    }

    var itemVersion: NSFileProviderItemVersion {
        let version = Data((asset.checksum ?? asset.assetID).utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }

    // Configured once and only ever read from (date(from:)), which Foundation's
    // date formatters support concurrently. They are reference types and thus
    // not Sendable, so the shared-mutable-state check needs an explicit opt-out.
    nonisolated(unsafe) private static let fractionalDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    nonisolated(unsafe) private static let plainDateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func parseDate(_ string: String) -> Date? {
        if let date = fractionalDateFormatter.date(from: string) {
            return date
        }
        return plainDateFormatter.date(from: string)
    }
}

final class SectionItem: NSObject, NSFileProviderItem {
    private let kind: SectionKind

    init(kind: SectionKind) {
        self.kind = kind
    }

    var itemIdentifier: NSFileProviderItemIdentifier { kind.itemID.identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { kind.displayName }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities {
        // Only the Albums section accepts new folders (creating an Immich album);
        // every other section is read-only.
        switch kind {
        case .albums:
            return [.allowsContentEnumerating, .allowsReading, .allowsAddingSubItems]
        default:
            return [.allowsContentEnumerating, .allowsReading]
        }
    }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("section:\(kind.rawValue)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class AlbumItem: NSObject, NSFileProviderItem {
    private let album: AlbumSummary
    private let displayName: String

    init(album: AlbumSummary, filename: String) {
        self.album = album
        self.displayName = filename
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        ItemID.album(album.albumID).identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        ItemID.albumsSection.identifier
    }

    var filename: String { displayName }
    var contentType: UTType { .folder }

    var capabilities: NSFileProviderItemCapabilities {
        // Files can be dropped in (uploaded + added to this album) and the album
        // can be renamed. Deleting the album itself is not yet supported.
        [.allowsContentEnumerating, .allowsReading, .allowsAddingSubItems, .allowsRenaming]
    }

    var childItemCount: NSNumber? {
        NSNumber(value: album.assetCount)
    }

    var itemVersion: NSFileProviderItemVersion {
        let version = Data("album:\(album.albumName):\(album.assetCount)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

// A read-only enumerable folder identified by an ItemID. Backs every
// smart-view folder (person, tag, country, city). The identifier and parent
// are passed in as ItemIDs so construction goes through the one grammar.
final class FolderItem: NSObject, NSFileProviderItem {
    private let id: ItemID
    private let parent: ItemID
    private let displayName: String

    init(id: ItemID, parent: ItemID, filename: String) {
        self.id = id
        self.parent = parent
        self.displayName = filename
    }

    var itemIdentifier: NSFileProviderItemIdentifier { id.identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { parent.identifier }
    var filename: String { displayName }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("\(id.identifier.rawValue):\(displayName)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class YearItem: NSObject, NSFileProviderItem {
    private let year: String

    init(year: String) {
        self.year = year
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        ItemID.year(year).identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        ItemID.timelineSection.identifier
    }

    var filename: String { year }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("year:\(year)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class MonthItem: NSObject, NSFileProviderItem {
    private let yearMonth: String

    init(yearMonth: String) {
        self.yearMonth = yearMonth
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        ItemID.month(yearMonth).identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        ItemID.year(String(yearMonth.prefix(4))).identifier
    }

    var filename: String {
        monthDisplayName(yearMonth)
    }

    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("month:\(yearMonth):named".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

// Overflow-safe 0-based half-open slice bounds for page `index` of `total` items
// at `size` per page. `index` can arrive from a crafted or stale identifier, so it
// is clamped into the valid page range before any multiplication (the multiply
// would otherwise trap on a huge index, before any later min could bound it).
func chunkSlice(index: Int, size: Int, total: Int) -> Range<Int> {
    let bounded = max(0, total)
    guard size > 0 else {
        return 0..<0
    }
    let pages = max(0, bounded - 1) / size + 1
    let clampedIndex = min(max(0, index), pages - 1)
    let start = clampedIndex * size
    let end = min(start + size, bounded)
    return start..<end
}

// Zero-padded "first-last" label for page `index` of `total` items at `size` per
// page, so the page folders sort in order in Finder. Shared by the flat page
// folders and the date strategy's per-month page folders.
func chunkRangeLabel(index: Int, size: Int, total: Int) -> String {
    let slice = chunkSlice(index: index, size: size, total: total)
    let width = String(max(0, total)).count
    return String(format: "%0\(width)d-%0\(width)d", slice.lowerBound + 1, slice.upperBound)
}

// One slice of a large asset container, shown as a sub-folder. Its name is a
// zero-padded "first-last" range so the folders sort in order in Finder, and its
// parent is the container the slice belongs to (album, month, person, ...).
final class ChunkFolderItem: NSObject, NSFileProviderItem {
    private let location: AssetLocation
    private let index: Int
    private let size: Int
    private let totalCount: Int

    init(location: AssetLocation, index: Int, size: Int, totalCount: Int) {
        self.location = location
        self.index = index
        self.size = size
        self.totalCount = totalCount
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        ItemID.chunk(location: location, index: index).identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        location.parentItemID.identifier
    }

    var filename: String {
        chunkRangeLabel(index: index, size: size, total: totalCount)
    }

    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }

    var childItemCount: NSNumber? {
        NSNumber(value: chunkSlice(index: index, size: size, total: totalCount).count)
    }

    var itemVersion: NSFileProviderItemVersion {
        let version = Data("chunk:\(location.code):\(index):\(totalCount)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class RootItem: NSObject, NSFileProviderItem {
    var itemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { AppGroup.domainDisplayName }
    var contentType: UTType { .folder }

    var capabilities: NSFileProviderItemCapabilities {
        [.allowsContentEnumerating, .allowsReading]
    }

    var itemVersion: NSFileProviderItemVersion {
        let version = Data("root-v1".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}
