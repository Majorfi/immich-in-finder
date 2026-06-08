import Foundation

enum AssetType: String, Decodable, Sendable {
    case image = "IMAGE"
    case video = "VIDEO"
    case audio = "AUDIO"
    case other = "OTHER"
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

struct Asset: Decodable, Sendable {
    let assetID: String
    let type: AssetType
    let originalFileName: String

    enum CodingKeys: String, CodingKey {
        case assetID = "id"
        case type
        case originalFileName
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
