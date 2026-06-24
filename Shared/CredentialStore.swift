import Foundation
import Security

struct ImmichCredentials: Sendable {
    let baseURL: URL
    let apiKey: String
}

// A tiny seam over the three Keychain operations CredentialStore needs.
// Production uses SystemKeychain (the real Keychain); tests substitute an
// in-memory backing so they never touch the Keychain / SecurityAgent.
protocol KeychainBacking: Sendable {
    func save(_ apiKey: String)
    func load() -> String?
    func delete()
}

// The real Keychain. The SecItem* logic is preserved verbatim from the
// previous CredentialStore so production reads/writes the exact same item.
struct SystemKeychain: KeychainBacking {
    private let keychainService = "app.quub.immichdrive"
    private let keychainAccount = "immich-api-key"

    // The [String: Any] dictionaries below are the unavoidable boundary with
    // Apple's C-level Security framework. They are confined to this file.
    private func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: keychainAccount,
            kSecAttrAccessGroup as String: AppGroup.keychainAccessGroup
        ]
    }

    // Update the item in place (delete-then-add silently kept the previous key
    // on macOS, so an updated key never took effect); add only if absent.
    func save(_ apiKey: String) {
        let data = Data(apiKey.utf8)
        let attributes: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery() as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var query = baseQuery()
            query[kSecValueData as String] = data
            SecItemAdd(query as CFDictionary, nil)
        }
    }

    func load() -> String? {
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

    func delete() {
        SecItemDelete(baseQuery() as CFDictionary)
    }
}

// In-memory KeychainBacking for tests. NSLock-guarded to stay Sendable under
// Swift 6 strict concurrency, matching RequestLog in Tests/MockURLProtocol.swift.
final class InMemoryKeychain: KeychainBacking, @unchecked Sendable {
    private var stored: String?
    private let lock = NSLock()

    func save(_ apiKey: String) {
        lock.lock(); defer { lock.unlock() }
        stored = apiKey
    }

    func load() -> String? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    func delete() {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}

// UserDefaults is thread-safe but not marked Sendable; the stored properties
// are immutable, so @unchecked Sendable is sound here.
struct CredentialStore: @unchecked Sendable {
    let keychain: KeychainBacking
    let defaults: UserDefaults?

    func save(baseURL: String, apiKey: String) {
        defaults?.set(baseURL, forKey: AppGroup.DefaultsKey.baseURL)
        keychain.save(apiKey)
    }

    func load() -> ImmichCredentials? {
        guard let baseURLString = defaults?.string(forKey: AppGroup.DefaultsKey.baseURL),
              let baseURL = URL(string: baseURLString),
              let apiKey = keychain.load(), apiKey.isEmpty == false else {
            return nil
        }
        return ImmichCredentials(baseURL: baseURL, apiKey: apiKey)
    }

    func clear() {
        defaults?.removeObject(forKey: AppGroup.DefaultsKey.baseURL)
        keychain.delete()
    }

    // Static facade preserving the original call sites (App/, FileProvider/).
    static let shared = CredentialStore(keychain: SystemKeychain(), defaults: AppGroup.defaults)

    static func save(baseURL: String, apiKey: String) {
        shared.save(baseURL: baseURL, apiKey: apiKey)
    }

    static func load() -> ImmichCredentials? {
        shared.load()
    }

    static func clear() {
        shared.clear()
    }
}
