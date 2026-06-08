import Foundation
import FileProvider

enum EnumeratedContainer {
    case albums
    case album(id: String)
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
                case .albums:
                    let albums = try await client.listAlbums()
                    let names = albums.map { $0.albumName }
                    fileProviderLog.log("enumerated \(albums.count, privacy: .public) albums")
                    observer.didEnumerate(albums.map {
                        AlbumItem(album: $0, filename: disambiguatedName(base: $0.albumName, id: $0.albumID, among: names))
                    })
                case .album(let id):
                    let assets = try await client.album(id: id).assets
                    let names = assets.map { $0.originalFileName }
                    fileProviderLog.log("enumerated \(assets.count, privacy: .public) assets in album")
                    observer.didEnumerate(assets.map {
                        ImmichItem(asset: $0, albumID: id, filename: disambiguatedName(base: $0.originalFileName, id: $0.assetID, among: names))
                    })
                }
                observer.finishEnumerating(upTo: nil)
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
}
