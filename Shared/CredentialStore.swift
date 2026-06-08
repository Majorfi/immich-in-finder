import Foundation
import Security

struct ImmichCredentials: Sendable {
    let baseURL: URL
    let apiKey: String
}

enum CredentialStore {
    private static let keychainService = "app.quub.immichdrive"
    private static let keychainAccount = "immich-api-key"

    static func save(baseURL: String, apiKey: String) {
        AppGroup.defaults?.set(baseURL, forKey: AppGroup.DefaultsKey.baseURL)
        saveAPIKey(apiKey)
    }

    static func load() -> ImmichCredentials? {
        guard let baseURLString = AppGroup.defaults?.string(forKey: AppGroup.DefaultsKey.baseURL),
              let baseURL = URL(string: baseURLString),
              let apiKey = loadAPIKey(), apiKey.isEmpty == false else {
            return nil
        }
        return ImmichCredentials(baseURL: baseURL, apiKey: apiKey)
    }

    static func clear() {
        AppGroup.defaults?.removeObject(forKey: AppGroup.DefaultsKey.baseURL)
        deleteAPIKey()
    }

    // The [String: Any] dictionaries below are the unavoidable boundary with
    // Apple's C-level Security framework. They are confined to this file.
    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup
        ]
    }

    private static func saveAPIKey(_ apiKey: String) {
        deleteAPIKey()
        guard let data = apiKey.data(using: .utf8) else { return }
        var query = baseQuery()
        query[kSecValueData as String] = data
        SecItemAdd(query as CFDictionary, nil)
    }

    private static func loadAPIKey() -> String? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    private static func deleteAPIKey() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}
