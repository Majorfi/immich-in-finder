import Foundation

enum AssetType: String, Decodable, Sendable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case other = "OTHER"
}

struct ExifInfo: Decodable, Sendable {
    let fileSizeInByte: Int64?
    let city: String?
    let country: String?
    let state: String?
}

// A distinct (country, city) place, derived from /api/search/cities.
struct PlaceSummary: Sendable, Hashable {
    let country: String
    let city: String
}

struct TagSummary: Decodable, Sendable {
    let id: String
    let name: String
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

struct SearchResponse: Decodable, Sendable {
    let assets: SearchAssets
}

struct SearchAssets: Decodable, Sendable {
    let items: [Asset]
    let nextPage: String?
}

struct PersonSummary: Decodable, Sendable {
    let id: String
    let name: String?
    let isHidden: Bool?
}

struct PeopleResponse: Decodable, Sendable {
    let people: [PersonSummary]
    let hasNextPage: Bool?
}

struct MetadataSearchRequest: Encodable, Sendable {
    let takenAfter: String?
    let takenBefore: String?
    let albumIds: [String]?
    let personIds: [String]?
    let tagIds: [String]?
    let city: String?
    let country: String?
    let page: Int
    let size: Int
    let order: String
    // Required for the server to include exifInfo (file size) in the results;
    // without it documentSize is unavailable on enumerated items.
    let withExif: Bool
}

// POST /api/assets returns the new id plus whether the server recognised the
// upload as a checksum duplicate of an asset it already holds.
struct UploadResponse: Decodable, Sendable {
    let id: String
    let status: String
}

struct AssetIDsRequest: Encodable, Sendable {
    let ids: [String]
}

struct CreateAlbumRequest: Encodable, Sendable {
    let albumName: String
    let assetIds: [String]
}

struct UpdateAlbumRequest: Encodable, Sendable {
    let albumName: String
}

// force=false moves assets to the Immich trash (recoverable for 30 days)
// rather than deleting them permanently.
struct TrashRequest: Encodable, Sendable {
    let ids: [String]
    let force: Bool
}
