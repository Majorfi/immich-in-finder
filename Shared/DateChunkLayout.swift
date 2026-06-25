import Foundation

// A node in the date strategy's folder tree. A year or month folder, or one page
// of a month that is itself too large. The enumerator maps these to identifiers
// and folder items; the layout stays free of FileProvider so it is unit-testable.
enum DateChunkNode: Sendable, Hashable {
    case year(String)                    // "2024"
    case month(String)                   // "2024-03"
    case page(month: String, index: Int) // page `index` within a month
}

// What a container shows: either sub-folders, or the assets of a single month
// directly (when that level collapsed down to one non-paged month).
enum DateChunkChildren: Sendable, Equatable {
    case folders([DateChunkNode])
    case assets(month: String)
}

// Pure, deterministic shape of the date tree for one container: given each
// month's count and the page size, it decides which levels exist (collapsing any
// level that has a single value) and where every asset's parent folder is. The
// enumerator (listing folders) and the resolver (an asset's parent) both ask the
// same layout, so they cannot disagree on the structure.
struct DateChunkLayout: Sendable, Equatable {
    let monthCounts: [String: Int]
    let size: Int

    // "YYYY-MM" of an asset, taken straight from the stored capture date. Using
    // one source for grouping and resolution avoids any timezone divergence a
    // server-side date bucket could introduce.
    static func month(of asset: Asset) -> String {
        String(asset.fileCreatedAt.prefix(7))
    }

    static func counts(of assets: [Asset]) -> [String: Int] {
        var counts: [String: Int] = [:]
        for asset in assets {
            counts[month(of: asset), default: 0] += 1
        }
        return counts
    }

    private func year(of month: String) -> String {
        String(month.prefix(4))
    }

    var years: [String] {
        Set(monthCounts.keys.map { String($0.prefix(4)) }).sorted(by: >)
    }

    func months(in year: String) -> [String] {
        monthCounts.keys.filter { $0.hasPrefix("\(year)-") }.sorted(by: >)
    }

    var hasYearLevel: Bool {
        years.count > 1
    }

    func hasMonthLevel(year: String) -> Bool {
        months(in: year).count > 1
    }

    func count(month: String) -> Int {
        monthCounts[month] ?? 0
    }

    func isPaged(month: String) -> Bool {
        count(month: month) > size
    }

    func pageCount(month: String) -> Int {
        let monthCount = count(month: month)
        guard size > 0, monthCount > 0 else {
            return 1
        }
        return (monthCount - 1) / size + 1
    }

    // What the top container (album/person/tag/favorite) shows, after collapsing
    // single-value levels: years, or a single year's months, or a single month's
    // pages or assets.
    func rootChildren() -> DateChunkChildren {
        if hasYearLevel {
            return .folders(years.map { .year($0) })
        }
        guard let onlyYear = years.first else {
            return .folders([])
        }
        return yearChildren(onlyYear)
    }

    func yearChildren(_ year: String) -> DateChunkChildren {
        let ms = months(in: year)
        if ms.count > 1 {
            return .folders(ms.map { .month($0) })
        }
        guard let onlyMonth = ms.first else {
            return .folders([])
        }
        return monthChildren(onlyMonth)
    }

    func monthChildren(_ month: String) -> DateChunkChildren {
        if isPaged(month: month) {
            return .folders((0..<pageCount(month: month)).map { .page(month: month, index: $0) })
        }
        return .assets(month: month)
    }

    // The folder a node lives under, or nil for the top container. A node's parent
    // is the deepest level that still exists after collapsing.
    func parentNode(of node: DateChunkNode) -> DateChunkNode? {
        switch node {
        case .year:
            return nil
        case .month(let month):
            if hasYearLevel {
                return .year(year(of: month))
            }
            return nil
        case .page(let month, _):
            if hasMonthLevel(year: year(of: month)) {
                return .month(month)
            }
            if hasYearLevel {
                return .year(year(of: month))
            }
            return nil
        }
    }

    // The folder an asset reports as its parent, given its month and its position
    // within that month (0-based). nil means the asset hangs directly off the top
    // container. Mirrors monthChildren/parentNode so listing and resolution agree.
    func assetParentNode(month: String, indexInMonth: Int) -> DateChunkNode? {
        if isPaged(month: month) {
            return .page(month: month, index: indexInMonth / max(1, size))
        }
        if hasMonthLevel(year: year(of: month)) {
            return .month(month)
        }
        if hasYearLevel {
            return .year(year(of: month))
        }
        return nil
    }
}
