import Foundation

// When a folder holds more than `size` assets, the extension splits it into
// fixed-size sub-folders ("chunks") of `size` assets each, so a very large album
// shows as a handful of folders that each paint independently instead of one
// folder that must fully materialize before Finder draws anything. Opt-in:
// absent (first run) means disabled, and behavior matches the flat folders.
// How a large folder is divided. `pages` is the flat numbered slices; `date`
// groups by year then month (collapsing single-value levels), splitting a month
// into pages only when it itself exceeds the page size.
enum ChunkStrategy: String, Sendable, CaseIterable {
    case pages
    case date
}

struct ChunkingSettings: Sendable, Equatable {
    var enabled: Bool
    var size: Int
    var strategy: ChunkStrategy = .pages

    static let `default` = ChunkingSettings(enabled: false, size: 1000, strategy: .pages)

    static func load() -> ChunkingSettings {
        guard let defaults = AppGroup.defaults else {
            return .default
        }
        guard defaults.object(forKey: AppGroup.DefaultsKey.chunkingEnabled) != nil else {
            return .default
        }
        let storedSize = defaults.integer(forKey: AppGroup.DefaultsKey.chunkSize)
        let size: Int = if storedSize > 0 { storedSize } else { ChunkingSettings.default.size }
        let storedStrategy = defaults.string(forKey: AppGroup.DefaultsKey.chunkStrategy)
        let strategy = storedStrategy.flatMap(ChunkStrategy.init(rawValue:)) ?? .pages
        return ChunkingSettings(
            enabled: defaults.bool(forKey: AppGroup.DefaultsKey.chunkingEnabled),
            size: size,
            strategy: strategy
        )
    }

    // Allowed page sizes. The Options stepper uses this, and the app clamps the
    // free-form size field to it before saving, so a typed value can't persist
    // out of range and then read back as the default (which looks like the field
    // is being ignored).
    static let sizeRange = 100...10_000

    func clampedToValidSize() -> ChunkingSettings {
        var copy = self
        copy.size = min(max(size, ChunkingSettings.sizeRange.lowerBound), ChunkingSettings.sizeRange.upperBound)
        return copy
    }

    static func save(_ settings: ChunkingSettings) {
        guard let defaults = AppGroup.defaults else {
            return
        }
        defaults.set(settings.enabled, forKey: AppGroup.DefaultsKey.chunkingEnabled)
        defaults.set(settings.size, forKey: AppGroup.DefaultsKey.chunkSize)
        defaults.set(settings.strategy.rawValue, forKey: AppGroup.DefaultsKey.chunkStrategy)
    }

    // A folder count this large is never a real library; it only happens when a
    // hostile or buggy server reports a huge total. Capping it keeps the page
    // arithmetic from overflowing and stops enumeration from allocating unbounded
    // folder items.
    static let maxChunkFolders = 50_000

    // Number of chunk folders a container of `count` assets splits into, and the
    // 0-based index of the chunk holding the asset at global position `assetIndex`.
    // Both halves of the design (listing folders, resolving an asset's parent) go
    // through this so they can never disagree on the boundaries. The count comes
    // from the server, so the math is done by division (never `count + size`,
    // which can overflow) and the result is capped.
    func chunkCount(for count: Int) -> Int {
        guard size > 0, count > 0 else {
            return 1
        }
        let folders = (count - 1) / size + 1
        return min(folders, ChunkingSettings.maxChunkFolders)
    }

    // Clamped so an asset never maps to a chunk folder that was not listed, even
    // if the statistics count and the fetched membership drift by a few items.
    func chunkIndex(forAssetIndex assetIndex: Int, count: Int) -> Int {
        guard size > 0 else {
            return 0
        }
        return min(assetIndex / size, chunkCount(for: count) - 1)
    }

    // A folder is split only when it spans more than one page, so a folder of
    // `size` or fewer stays flat and there is never a lone single-page sub-folder.
    func isChunked(count: Int) -> Bool {
        return enabled && count > size
    }
}
