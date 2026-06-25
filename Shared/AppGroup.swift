import Foundation
import os

let fileProviderLog = Logger(subsystem: "app.quub.immichdrive", category: "FileProvider")

enum AppGroup {
    static let identifier = "QZSF4W9PK3.app.quub.immichdrive"
    static let keychainAccessGroup = "QZSF4W9PK3.app.quub.immichdrive"

    static let domainIdentifier = "app.quub.immichdrive.primary"
    // The label shown for the Finder location. This is the app's own brand
    // (Findich), distinct from the Immich server it bridges.
    static let domainDisplayName = "Findich"

    enum DefaultsKey {
        static let baseURL = "immich.baseURL"
        static let visibleSections = "immich.visibleSections"
        static let chunkingEnabled = "immich.chunkingEnabled"
        static let chunkSize = "immich.chunkSize"
        static let chunkStrategy = "immich.chunkStrategy"
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
