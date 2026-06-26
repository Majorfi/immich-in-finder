import Foundation
import Security

struct ImmichCredentials: Sendable {
    let baseURL: URL
    let apiKey: String
    // Empty when the server is reached directly; otherwise the user's custom
    // request headers (e.g. Cloudflare Access service-token headers).
    let customHeaders: [CustomHeader]
}

// A tiny seam over the Keychain operations CredentialStore needs, keyed by
// account so it can hold more than one secret (the API key, and the custom
// header set). Production uses SystemKeychain (the real Keychain); tests
// substitute an in-memory backing so they never touch the Keychain /
// SecurityAgent.
protocol KeychainBacking: Sendable {
    func save(_ value: String, account: String)
    func load(account: String) -> String?
    func delete(account: String)
}

// The real Keychain. Items go in the data-protection keychain so access is gated
// by the keychain access group (shared between the app and the extension) rather
// than a per-binary ACL, which would otherwise re-prompt on every signed update.
struct SystemKeychain: KeychainBacking {
    private let keychainService = "app.quub.immichdrive"

    // The [String: Any] dictionaries below are the unavoidable boundary with
    // Apple's C-level Security framework. They are confined to this file.
    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup,
            kSecUseDataProtectionKeychain as String: true
        ]
    }

    // Update the item in place (delete-then-add silently kept the previous value
    // on macOS, so an updated secret never took effect); add only if absent.
    func save(_ value: String, account: String) {
        let data = Data(value.utf8)
        // AfterFirstUnlock lets the extension read the secret in the background
        // while the screen is locked; the default (WhenUnlocked) would block that.
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        let status = SecItemUpdate(baseQuery(account: account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery(account: account)
            query[kSecValueData as String] = data
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func load(account: String) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}

// In-memory KeychainBacking for tests. NSLock-guarded to stay Sendable under
// Swift 6 strict concurrency, matching RequestLog in Tests/MockURLProtocol.swift.
final class InMemoryKeychain: KeychainBacking, @unchecked Sendable {
    private var stored: [String: String] = [:]
    private let lock = NSLock()

    func save(_ value: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        stored[account] = value
    }

    func load(account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return stored[account]
    }

    func delete(account: String) {
        lock.lock(); defer { lock.unlock() }
        stored[account] = nil
    }
}

// UserDefaults is thread-safe but not marked Sendable; the stored properties
// are immutable, so @unchecked Sendable is sound here.
struct CredentialStore: @unchecked Sendable {
    let keychain: KeychainBacking
    let defaults: UserDefaults?

    // Both secrets live in the Keychain (shared access group, AfterFirstUnlock),
    // keyed by account. Header values can be bearer tokens (e.g. a Cloudflare
    // Access client secret), so they get the same protection as the API key
    // rather than sitting in the App Group plist.
    static let apiKeyAccount = "immich-api-key"
    static let customHeadersAccount = "immich-custom-headers"

    func save(baseURL: String, apiKey: String, customHeaders: [CustomHeader] = []) {
        defaults?.set(baseURL, forKey: AppGroup.DefaultsKey.baseURL)
        keychain.save(apiKey, account: Self.apiKeyAccount)
        if customHeaders.isEmpty {
            keychain.delete(account: Self.customHeadersAccount)
        } else if let encoded = try? JSONEncoder().encode(customHeaders),
                  let json = String(data: encoded, encoding: .utf8) {
            keychain.save(json, account: Self.customHeadersAccount)
        }
    }

    func load() -> ImmichCredentials? {
        guard let baseURLString = defaults?.string(forKey: AppGroup.DefaultsKey.baseURL),
              let baseURL = URL(string: baseURLString),
              let apiKey = keychain.load(account: Self.apiKeyAccount), apiKey.isEmpty == false else {
            return nil
        }
        return ImmichCredentials(baseURL: baseURL, apiKey: apiKey, customHeaders: loadCustomHeaders())
    }

    private func loadCustomHeaders() -> [CustomHeader] {
        guard let json = keychain.load(account: Self.customHeadersAccount),
              let data = json.data(using: .utf8),
              let headers = try? JSONDecoder().decode([CustomHeader].self, from: data) else {
            return []
        }
        return headers
    }

    func clear() {
        defaults?.removeObject(forKey: AppGroup.DefaultsKey.baseURL)
        keychain.delete(account: Self.apiKeyAccount)
        keychain.delete(account: Self.customHeadersAccount)
    }

    // Static facade preserving the original call sites (App/, FileProvider/).
    static let shared = CredentialStore(keychain: SystemKeychain(), defaults: AppGroup.defaults)

    static func save(baseURL: String, apiKey: String, customHeaders: [CustomHeader] = []) {
        shared.save(baseURL: baseURL, apiKey: apiKey, customHeaders: customHeaders)
    }

    static func load() -> ImmichCredentials? {
        shared.load()
    }

    static func clear() {
        shared.clear()
    }
}
