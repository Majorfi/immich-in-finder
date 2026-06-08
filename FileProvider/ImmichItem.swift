import Foundation
import FileProvider
import UniformTypeIdentifiers

enum AssetLocation {
    case album(id: String)
    case month(yearMonth: String)
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
            return NSFileProviderItemIdentifier(rawValue: "asset:\(id):\(asset.assetID)")
        case .month(let yearMonth):
            return NSFileProviderItemIdentifier(rawValue: "tasset:\(yearMonth):\(asset.assetID)")
        }
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        switch location {
        case .album(let id):
            return NSFileProviderItemIdentifier(rawValue: "album:\(id)")
        case .month(let yearMonth):
            return NSFileProviderItemIdentifier(rawValue: "month:\(yearMonth)")
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
        // Deleting maps to moving the asset to the Immich trash. Renaming and
        // reparenting are not yet supported.
        [.allowsReading, .allowsEvicting, .allowsDeleting]
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
        NSFileProviderItemIdentifier(rawValue: "album:\(album.albumID)")
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawValue: "section:albums")
    }

    var filename: String { displayName }
    var contentType: UTType { .folder }

    var capabilities: NSFileProviderItemCapabilities {
        // Files can be dropped in (uploaded + added to this album). Renaming and
        // deleting the album itself are not yet supported.
        [.allowsContentEnumerating, .allowsReading, .allowsAddingSubItems]
    }

    var childItemCount: NSNumber? {
        NSNumber(value: album.assetCount)
    }

    var itemVersion: NSFileProviderItemVersion {
        let version = Data("album:\(album.albumName):\(album.assetCount)".utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }
}

final class YearItem: NSObject, NSFileProviderItem {
    private let year: String

    init(year: String) {
        self.year = year
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawValue: "year:\(year)")
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawValue: "section:timeline")
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
        NSFileProviderItemIdentifier(rawValue: "month:\(yearMonth)")
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawValue: "year:\(String(yearMonth.prefix(4)))")
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
