import Foundation
import FileProvider

enum EnumeratedContainer {
    case sections
    case albums
    case album(id: String)
    case years
    case months(year: String)
    case month(yearMonth: String)
}

final class ItemEnumerator: NSObject, NSFileProviderEnumerator {
    private let client: ImmichClient
    private let container: EnumeratedContainer

    init(client: ImmichClient, container: EnumeratedContainer) {
        self.client = client
        self.container = container
    }

    func invalidate() {}

    func enumerateItems(for observer: NSFileProviderEnumerationObserver, startingAt page: NSFileProviderPage) {
        Task {
            do {
                switch container {
                case .sections:
                    observer.didEnumerate([
                        SectionItem(id: "section:albums", name: "Albums"),
                        SectionItem(id: "section:timeline", name: "Timeline")
                    ])
                    observer.finishEnumerating(upTo: nil)
                case .albums:
                    let albums = try await client.listAlbums()
                    let names = albums.map { $0.albumName }
                    fileProviderLog.log("enumerated \(albums.count, privacy: .public) albums")
                    observer.didEnumerate(albums.map {
                        AlbumItem(album: $0, filename: disambiguatedName(base: $0.albumName, id: $0.albumID, among: names))
                    })
                    observer.finishEnumerating(upTo: nil)
                case .album(let id):
                    let assets = try await client.album(id: id).assets
                    let names = assets.map { $0.originalFileName }
                    fileProviderLog.log("enumerated \(assets.count, privacy: .public) assets in album")
                    observer.didEnumerate(assets.map {
                        ImmichItem(asset: $0, location: .album(id: id), filename: disambiguatedName(base: $0.originalFileName, id: $0.assetID, among: names))
                    })
                    observer.finishEnumerating(upTo: nil)
                case .years:
                    guard let range = try await client.assetYearRange() else {
                        observer.didEnumerate([])
                        observer.finishEnumerating(upTo: nil)
                        return
                    }
                    let years = try await client.nonEmptyYears(oldest: range.oldest, newest: range.newest)
                    fileProviderLog.log("enumerated \(years.count, privacy: .public) timeline years")
                    observer.didEnumerate(years.map { YearItem(year: String($0)) })
                    observer.finishEnumerating(upTo: nil)
                case .months(let year):
                    let months = try await client.nonEmptyMonths(year: year)
                    fileProviderLog.log("enumerated \(months.count, privacy: .public) months in \(year, privacy: .public)")
                    observer.didEnumerate(months.map { MonthItem(yearMonth: $0) })
                    observer.finishEnumerating(upTo: nil)
                case .month(let yearMonth):
                    let apiPage = ItemEnumerator.pageNumber(from: page)
                    let result = try await client.searchMonth(yearMonth: yearMonth, page: apiPage)
                    fileProviderLog.log("timeline \(yearMonth, privacy: .public) page \(apiPage, privacy: .public): \(result.assets.count, privacy: .public) assets")
                    observer.didEnumerate(result.assets.map {
                        ImmichItem(asset: $0, location: .month(yearMonth: yearMonth), filename: $0.originalFileName)
                    })
                    if let next = result.nextPage {
                        observer.finishEnumerating(upTo: NSFileProviderPage(Data("p:\(next)".utf8)))
                    } else {
                        observer.finishEnumerating(upTo: nil)
                    }
                }
            } catch {
                observer.finishEnumeratingWithError(error)
            }
        }
    }

    func enumerateChanges(for observer: NSFileProviderChangeObserver, from anchor: NSFileProviderSyncAnchor) {
        observer.finishEnumeratingChanges(upTo: anchor, moreComing: false)
    }

    func currentSyncAnchor(completionHandler: @escaping (NSFileProviderSyncAnchor?) -> Void) {
        completionHandler(NSFileProviderSyncAnchor(Data("anchor-v1".utf8)))
    }

    private static func pageNumber(from page: NSFileProviderPage) -> Int {
        guard let string = String(data: page.rawValue, encoding: .utf8), string.hasPrefix("p:"), let number = Int(string.dropFirst(2)) else {
            return 1
        }
        return number
    }
}
