import Foundation
import FileProvider
import UniformTypeIdentifiers

enum AssetLocation {
    case album(id: String)
    case month(yearMonth: String)
    case person(id: String)
    case place(country: String, city: String)
    case tag(id: String)
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
// enumeration and single-item resolution name files identically.
func immichItems(from assets: [Asset], location: AssetLocation) -> [ImmichItem] {
    let counts = nameCounts(assets.map { $0.originalFileName })
    return assets.map {
        ImmichItem(asset: $0, location: location, filename: disambiguatedName(base: $0.originalFileName, id: $0.assetID, counts: counts))
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

    init(asset: Asset, location: AssetLocation, filename: String) {
        self.asset = asset
        self.location = location
        self.displayName = filename
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        switch location {
        case .album(let id):
            return ItemID.asset(albumID: id, assetID: asset.assetID).identifier
        case .month(let yearMonth):
            return ItemID.timelineAsset(yearMonth: yearMonth, assetID: asset.assetID).identifier
        case .person(let id):
            return ItemID.personAsset(personID: id, assetID: asset.assetID).identifier
        case .place(let country, let city):
            return ItemID.placeAsset(country: country, city: city, assetID: asset.assetID).identifier
        case .tag(let id):
            return ItemID.tagAsset(tagID: id, assetID: asset.assetID).identifier
        }
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        switch location {
        case .album(let id):
            return ItemID.album(id).identifier
        case .month(let yearMonth):
            return ItemID.month(yearMonth).identifier
        case .person(let id):
            return ItemID.person(id).identifier
        case .place(let country, let city):
            return ItemID.city(country: country, city: city).identifier
        case .tag(let id):
            return ItemID.tag(id).identifier
        }
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
            return [.allowsReading, .allowsEvicting, .allowsDeleting, .allowsReparenting]
        case .month, .person, .place, .tag:
            return [.allowsReading, .allowsEvicting, .allowsDeleting]
        }
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
    private let id: String
    private let name: String

    init(id: String, name: String) {
        self.id = id
        self.name = name
    }

    var itemIdentifier: NSFileProviderItemIdentifier { NSFileProviderItemIdentifier(rawValue: id) }
    var parentItemIdentifier: NSFileProviderItemIdentifier { .rootContainer }
    var filename: String { name }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities {
        // Only the Albums section accepts new folders (creating an Immich album);
        // the Timeline section is read-only.
        if id == "section:albums" {
            return [.allowsContentEnumerating, .allowsReading, .allowsAddingSubItems]
        }
        return [.allowsContentEnumerating, .allowsReading]
    }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("section:\(id)".utf8)
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

final class PersonItem: NSObject, NSFileProviderItem {
    private let id: String
    private let displayName: String

    init(id: String, filename: String) {
        self.id = id
        self.displayName = filename
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        ItemID.person(id).identifier
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        ItemID.peopleSection.identifier
    }

    var filename: String { displayName }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("person:\(id):\(displayName)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class TagItem: NSObject, NSFileProviderItem {
    private let id: String
    private let displayName: String

    init(id: String, filename: String) {
        self.id = id
        self.displayName = filename
    }

    var itemIdentifier: NSFileProviderItemIdentifier { ItemID.tag(id).identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { ItemID.tagsSection.identifier }
    var filename: String { displayName }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("tag:\(id):\(displayName)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class CountryItem: NSObject, NSFileProviderItem {
    private let name: String

    init(name: String) {
        self.name = name
    }

    var itemIdentifier: NSFileProviderItemIdentifier { ItemID.country(name).identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { ItemID.placesSection.identifier }
    var filename: String { name }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("country:\(name)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class CityItem: NSObject, NSFileProviderItem {
    private let country: String
    private let city: String

    init(country: String, city: String) {
        self.country = country
        self.city = city
    }

    var itemIdentifier: NSFileProviderItemIdentifier { ItemID.city(country: country, city: city).identifier }
    var parentItemIdentifier: NSFileProviderItemIdentifier { ItemID.country(country).identifier }
    var filename: String { city }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("city:\(country):\(city)".utf8)
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

    private static let monthNames: [String] = DateFormatter().standaloneMonthSymbols ?? []

    var filename: String {
        let monthNumber = Int(yearMonth.suffix(2)) ?? 0
        if monthNumber >= 1, monthNumber <= MonthItem.monthNames.count {
            return String(format: "%02d — %@", monthNumber, MonthItem.monthNames[monthNumber - 1].capitalized)
        }
        return String(yearMonth.suffix(2))
    }

    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("month:\(yearMonth):named".utf8)
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
