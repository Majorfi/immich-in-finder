import XCTest

final class CredentialStoreTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!
    private var store: CredentialStore!

    override func setUp() {
        super.setUp()
        suiteName = "test.credentialstore.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        store = CredentialStore(keychain: InMemoryKeychain(), defaults: defaults)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        store = nil
        suiteName = nil
        super.tearDown()
    }

    func testSaveThenLoadRoundTripsBothFields() {
        store.save(baseURL: "https://immich.example.com", apiKey: "secret-key")

        let loaded = store.load()
        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.baseURL.absoluteString, "https://immich.example.com")
        XCTAssertEqual(loaded?.apiKey, "secret-key")
    }

    func testClearRemovesBothFields() {
        store.save(baseURL: "https://immich.example.com", apiKey: "secret-key")
        XCTAssertNotNil(store.load())

        store.clear()

        XCTAssertNil(store.load())
        XCTAssertNil(defaults.string(forKey: AppGroup.DefaultsKey.baseURL))
    }

    func testSaveTwiceOverwritesBothFields() {
        store.save(baseURL: "https://first.example.com", apiKey: "first-key")
        store.save(baseURL: "https://second.example.com", apiKey: "second-key")

        let loaded = store.load()
        XCTAssertEqual(loaded?.baseURL.absoluteString, "https://second.example.com")
        XCTAssertEqual(loaded?.apiKey, "second-key")
    }

    func testLoadWithNothingStoredReturnsNil() {
        XCTAssertNil(store.load())
    }

    func testLoadReturnsNilWhenAPIKeyIsEmpty() {
        // Pins CredentialStore behavior: an empty apiKey is treated as absent.
        store.save(baseURL: "https://immich.example.com", apiKey: "")
        XCTAssertNil(store.load())
    }

    func testLoadReturnsNilWhenBaseURLIsInvalid() {
        // An empty string is not a valid URL, so URL(string:) returns nil and
        // load() bails even though a key is present in the keychain.
        store.save(baseURL: "https://immich.example.com", apiKey: "secret-key")
        defaults.set("", forKey: AppGroup.DefaultsKey.baseURL)
        XCTAssertNil(store.load())
    }

    func testLoadReturnsNilWhenBaseURLMissingButKeyPresent() {
        store.save(baseURL: "https://immich.example.com", apiKey: "secret-key")
        defaults.removeObject(forKey: AppGroup.DefaultsKey.baseURL)
        XCTAssertNil(store.load())
    }

    // MARK: custom headers

    func testCustomHeadersRoundTrip() {
        let headers = [
            CustomHeader(name: "CF-Access-Client-Id", value: "id"),
            CustomHeader(name: "CF-Access-Client-Secret", value: "secret")
        ]
        store.save(baseURL: "https://immich.example.com", apiKey: "k", customHeaders: headers)
        XCTAssertEqual(store.load()?.customHeaders, headers)
    }

    func testNoCustomHeadersLoadsAsEmpty() {
        store.save(baseURL: "https://immich.example.com", apiKey: "k")
        XCTAssertEqual(store.load()?.customHeaders, [])
    }

    // Saving an empty set clears a previously-stored header item rather than
    // leaving stale headers behind.
    func testSavingEmptyHeadersClearsPreviousHeaders() {
        store.save(baseURL: "https://immich.example.com", apiKey: "k", customHeaders: [CustomHeader(name: "X", value: "1")])
        XCTAssertEqual(store.load()?.customHeaders.count, 1)

        store.save(baseURL: "https://immich.example.com", apiKey: "k", customHeaders: [])
        XCTAssertEqual(store.load()?.customHeaders, [])
    }

    // clear() must remove the header item too, so a later save with no headers
    // doesn't resurrect the old ones.
    func testClearRemovesCustomHeaders() {
        store.save(baseURL: "https://immich.example.com", apiKey: "k", customHeaders: [CustomHeader(name: "X", value: "1")])
        store.clear()

        store.save(baseURL: "https://immich.example.com", apiKey: "k")
        XCTAssertEqual(store.load()?.customHeaders, [])
    }
}
