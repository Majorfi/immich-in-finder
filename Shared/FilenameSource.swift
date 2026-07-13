import Foundation

// Which of an asset's two names Finder shows. Immich keeps the upload-time
// `originalFileName` in metadata, while `originalPath` is where the file lives on
// the server after its Storage Template is applied; a library with a custom
// template wants that name instead. Opt-in: absent (first run) means
// `originalName`, matching the long-standing behavior.
enum FilenameSource: String, Sendable, CaseIterable {
    case originalName
    case storagePath

    static let `default` = FilenameSource.originalName

    static func load() -> FilenameSource {
        guard let defaults = AppGroup.defaults else {
            return .default
        }
        let stored = defaults.string(forKey: AppGroup.DefaultsKey.filenameSource)
        return stored.flatMap(FilenameSource.init(rawValue:)) ?? .default
    }

    static func save(_ source: FilenameSource) {
        guard let defaults = AppGroup.defaults else {
            return
        }
        defaults.set(source.rawValue, forKey: AppGroup.DefaultsKey.filenameSource)
    }

    // The base filename for an asset under this source. Falls back to the upload
    // name when the storage path is missing or has no final component, so a photo
    // always has a name.
    func baseName(for asset: Asset) -> String {
        switch self {
        case .originalName:
            return asset.originalFileName
        case .storagePath:
            guard let path = asset.originalPath, path.isEmpty == false else {
                return asset.originalFileName
            }
            let component = (path as NSString).lastPathComponent
            if component.isEmpty {
                return asset.originalFileName
            }
            return component
        }
    }
}
