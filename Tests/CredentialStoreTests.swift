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
        defaults.set("", forKey: AppGroup.DefaultsKey.baseURL)
        store.keychain.save("secret-key")
        XCTAssertNil(store.load())
    }

    func testLoadReturnsNilWhenBaseURLMissingButKeyPresent() {
        store.keychain.save("secret-key")
        XCTAssertNil(store.load())
    }
}
