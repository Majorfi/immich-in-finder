import Foundation
import FileProvider
import UniformTypeIdentifiers

enum AssetLocation {
    case album(id: String)
    case month(yearMonth: String)
}

// Keeps a name intact unless it collides with another in the same container,
// in which case a short id fragment is inserted before the extension. The rule
// is deterministic given the sibling list, so enumeration and item(for:) agree.
func disambiguatedName(base: String, id: String, among allNames: [String]) -> String {
    let occurrences = allNames.filter { $0 == base }.count
    if occurrences <= 1 {
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
        [.allowsReading, .allowsEvicting]
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

    static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
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
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
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
        [.allowsContentEnumerating, .allowsReading]
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

    var filename: String { String(yearMonth.suffix(2)) }
    var contentType: UTType { .folder }
    var capabilities: NSFileProviderItemCapabilities { [.allowsContentEnumerating, .allowsReading] }
    var itemVersion: NSFileProviderItemVersion {
        let version = Data("month:\(yearMonth)".utf8)
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
