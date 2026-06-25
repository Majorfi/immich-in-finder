import Foundation
import FileProvider

// Drives "Free up space": reverts downloaded originals to placeholders so they
// stop taking disk. Lives in the App target next to DomainManager, which already
// owns the NSFileProviderManager(for:) pattern. The system refuses to evict files
// that are open or have unsynced edits, so per-item failures are skipped.
enum SpaceManager {
    private static var domain: NSFileProviderDomain {
        NSFileProviderDomain(
            identifier: NSFileProviderDomainIdentifier(rawValue: AppGroup.domainIdentifier),
            displayName: AppGroup.domainDisplayName
        )
    }

    static func freeUpSpace() async -> Int {
        guard let manager = NSFileProviderManager(for: domain) else {
            return 0
        }
        let identifiers = await materializedAssetIdentifiers(manager: manager)
        var evicted = 0
        for identifier in identifiers {
            let didEvict = await evict(identifier, manager: manager)
            if didEvict {
                evicted += 1
            }
        }
        fileProviderLog.log("freeUpSpace evicted \(evicted, privacy: .public) of \(identifiers.count, privacy: .public) candidates")
        return evicted
    }

    private static func materializedAssetIdentifiers(manager: NSFileProviderManager) async -> [NSFileProviderItemIdentifier] {
        let items = await enumerateMaterialized(manager: manager)
        return items.compactMap { item in
            guard isAssetIdentifier(item.itemIdentifier.rawValue) else {
                return nil
            }
            return item.itemIdentifier
        }
    }

    // Asset identifier prefixes, mirroring the ItemID grammar in the extension
    // target (which the app cannot import). Folders never materialize, so this is
    // a guard against ever evicting a container identifier by mistake.
    private static func isAssetIdentifier(_ raw: String) -> Bool {
        let prefixes = ["asset:", "tasset:", "passet:", "qasset:", "tagasset:", "fasset:"]
        return prefixes.contains { raw.hasPrefix($0) }
    }

    // Drives the materialized-items enumerator manually: the starting page is
    // Data() per the SDK, the app plays the observer role, and the observer pages
    // to the end before calling back once with everything on disk.
    private static func enumerateMaterialized(manager: NSFileProviderManager) async -> [NSFileProviderItem] {
        let enumerator = manager.enumeratorForMaterializedItems()
        return await withCheckedContinuation { continuation in
            let observer = MaterializedObserver(enumerator: enumerator) { items in
                enumerator.invalidate()
                continuation.resume(returning: items)
            }
            enumerator.enumerateItems(for: observer, startingAt: NSFileProviderPage(Data()))
        }
    }

    private static func evict(_ identifier: NSFileProviderItemIdentifier, manager: NSFileProviderManager) async -> Bool {
        await withCheckedContinuation { continuation in
            manager.evictItem(identifier: identifier) { error in
                if let error {
                    fileProviderLog.error("evict failed for \(identifier.rawValue, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    continuation.resume(returning: false)
                    return
                }
                continuation.resume(returning: true)
            }
        }
    }
}

// Accumulates the materialized items across pages, then reports them once the
// enumeration finishes (upTo nil). On error it reports whatever it gathered so a
// partial enumeration still frees what it found.
final class MaterializedObserver: NSObject, NSFileProviderEnumerationObserver {
    private var items: [NSFileProviderItem] = []
    private let enumerator: NSFileProviderEnumerator
    private let completion: ([NSFileProviderItem]) -> Void

    init(enumerator: NSFileProviderEnumerator, completion: @escaping ([NSFileProviderItem]) -> Void) {
        self.enumerator = enumerator
        self.completion = completion
    }

    func didEnumerate(_ updatedItems: [any NSFileProviderItemProtocol]) {
        items.append(contentsOf: updatedItems)
    }

    func finishEnumerating(upTo nextPage: NSFileProviderPage?) {
        if let nextPage {
            enumerator.enumerateItems(for: self, startingAt: nextPage)
            return
        }
        completion(items)
    }

    func finishEnumeratingWithError(_ error: any Error) {
        fileProviderLog.error("materialized enumeration error: \(error.localizedDescription, privacy: .public)")
        completion(items)
    }
}
