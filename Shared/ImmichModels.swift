import Foundation

enum AssetType: String, Decodable, Sendable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case other = "OTHER"
}

struct ExifInfo: Decodable, Sendable {
    let fileSizeInByte: Int64?
}

struct Asset: Decodable, Sendable {
    let assetID: String
    let type: AssetType
    let originalFileName: String
    let checksum: String?
    let fileCreatedAt: String
    let fileModifiedAt: String?
    let exifInfo: ExifInfo?

    enum CodingKeys: String, CodingKey {
        case assetID = "id"
        case type
        case originalFileName
        case checksum
        case fileCreatedAt
        case fileModifiedAt
        case exifInfo
    }
}

struct AlbumSummary: Decodable, Sendable {
    let albumID: String
    let albumName: String
    let assetCount: Int

    enum CodingKeys: String, CodingKey {
        case albumID = "id"
        case albumName
        case assetCount
    }
}

struct Album: Decodable, Sendable {
    let albumID: String
    let albumName: String
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case albumID = "id"
        case albumName
        case assets
    }
}

struct SearchResponse: Decodable, Sendable {
    let assets: SearchAssets
}

struct SearchAssets: Decodable, Sendable {
    let items: [Asset]
    let nextPage: String?
}

struct MetadataSearchRequest: Encodable, Sendable {
    let takenAfter: String?
    let takenBefore: String?
    let page: Int
    let size: Int
    let order: String
}
