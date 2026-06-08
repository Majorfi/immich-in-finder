import Foundation
import FileProvider
import UniformTypeIdentifiers

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
    private let albumID: String
    private let displayName: String

    init(asset: Asset, albumID: String, filename: String) {
        self.asset = asset
        self.albumID = albumID
        self.displayName = filename
    }

    var itemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawValue: "asset:\(albumID):\(asset.assetID)")
    }

    var parentItemIdentifier: NSFileProviderItemIdentifier {
        NSFileProviderItemIdentifier(rawValue: "album:\(albumID)")
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
        ImmichItem.parseDate(asset.fileModifiedAt)
    }

    var itemVersion: NSFileProviderItemVersion {
        let version = Data(asset.checksum.utf8)
        return NSFileProviderItemVersion(contentVersion: version, metadataVersion: version)
    }

    private static func parseDate(_ string: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: string) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: string)
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
        .rootContainer
    }

    var filename: String {
        displayName
    }

    var contentType: UTType {
        .folder
    }

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
