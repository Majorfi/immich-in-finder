import Foundation
import os

let fileProviderLog = Logger(subsystem: "app.quub.immichdrive", category: "FileProvider")

enum AppGroup {
    static let identifier = "QZSF4W9PK3.app.quub.immichdrive"
    static let keychainAccessGroup = "QZSF4W9PK3.app.quub.immichdrive"

    static let domainIdentifier = "app.quub.immichdrive.primary"
    static let domainDisplayName = "Immich"

    enum DefaultsKey {
        static let baseURL = "immich.baseURL"
        static let albumID = "immich.albumID"
    }

    static var defaults: UserDefaults? {
        UserDefaults(suiteName: identifier)
    }
}
