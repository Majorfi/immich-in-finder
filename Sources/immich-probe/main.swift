import Foundation

func optionalEnv(_ name: String) -> String? {
    guard let value = ProcessInfo.processInfo.environment[name], value.isEmpty == false else {
        return nil
    }
    return value
}

func requiredEnv(_ name: String) throws -> String {
    guard let value = optionalEnv(name) else {
        throw ProbeError.missingEnv(name)
    }
    return value
}

func humanBytes(_ count: Int) -> String {
    ByteCountFormatter().string(fromByteCount: Int64(count))
}

func sanitizedFileName(_ name: String) -> String {
    name.replacingOccurrences(of: "/", with: "_")
}

do {
    let baseURLString = try requiredEnv("IMMICH_BASE_URL")
    let apiKey = try requiredEnv("IMMICH_API_KEY")
    guard let baseURL = URL(string: baseURLString) else {
        throw ProbeError.badURL(baseURLString)
    }
    let client = ImmichClient(baseURL: baseURL, apiKey: apiKey)
    print("→ Server: \(baseURLString)")

    let albumID: String
    if let pinned = optionalEnv("IMMICH_ALBUM_ID") {
        albumID = pinned
        print("→ Album: pinned \(pinned)")
    } else {
        let albums = try await client.listAlbums()
        print("✓ Auth OK — \(albums.count) album(s) visible")
        guard let first = albums.first else {
            print("✗ No albums on this account. Create one in Immich or set IMMICH_ALBUM_ID.")
            exit(1)
        }
        albumID = first.albumID
        print("→ Album: \"\(first.albumName)\" — \(first.assetCount) asset(s)")
    }

    let album = try await client.album(id: albumID)
    print("✓ Enumerated album \"\(album.albumName)\" — \(album.assets.count) asset(s)")
    guard let asset = album.assets.first else {
        print("✗ Album has no assets. Add a photo and re-run.")
        exit(1)
    }
    print("→ Asset: \(asset.originalFileName) [\(asset.type.rawValue)] id=\(asset.assetID)")

    let (original, originalType) = try await client.downloadOriginal(assetID: asset.assetID)
    let originalPath = "/tmp/immich-probe-original-\(sanitizedFileName(asset.originalFileName))"
    try original.write(to: URL(fileURLWithPath: originalPath))
    print("✓ Original: \(humanBytes(original.count)) [\(originalType ?? "?")] -> \(originalPath)")

    let thumbSize = optionalEnv("IMMICH_THUMB_SIZE")
    let (thumb, thumbType) = try await client.downloadThumbnail(assetID: asset.assetID, size: thumbSize)
    let thumbPath = "/tmp/immich-probe-thumb-\(asset.assetID).bin"
    try thumb.write(to: URL(fileURLWithPath: thumbPath))
    print("✓ Thumbnail: \(humanBytes(thumb.count)) [\(thumbType ?? "?")] -> \(thumbPath)")

    print("\n✅ Probe passed — auth, enumeration, original + thumbnail all work.")
} catch {
    FileHandle.standardError.write(Data("✗ \(error)\n".utf8))
    exit(1)
}
