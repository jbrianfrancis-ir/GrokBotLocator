import Foundation
import Security
import Testing
@testable import GrokBotLocator

/// Exercises the real Keychain through `KeychainCredentialStore` -- round-trip, overwrite,
/// absence, and the header-name default -- never against the app's own items. Every test
/// builds its own store on a unique throwaway `service` ("test." + a fresh UUID) and clears
/// it when done, so a failed run never leaves synthetic fixtures behind and never touches
/// what a real user has saved.
@Suite
struct KeychainCredentialStoreTests {

    /// `example.invalid` never resolves; the sender key and header name are equally
    /// non-resolving fixtures. Distinct from the "2" set so overwrite tests can tell which
    /// generation of values came back.
    private static let fixtureURL = URL(string: "https://example.invalid/webhook")!
    private static let fixtureSenderKey = "dummy-sender-key-fixture-one"
    private static let fixtureHeaderName = "X-Test-Header-One"

    private static let fixtureURL2 = URL(string: "https://example2.invalid/webhook")!
    private static let fixtureSenderKey2 = "dummy-sender-key-fixture-two"
    private static let fixtureHeaderName2 = "X-Test-Header-Two"

    private static func throwawayService() -> String {
        "test." + UUID().uuidString
    }

    /// Number of `kSecClassGenericPassword` items matching `service`/`account`, independent
    /// of `KeychainCredentialStore` -- used to prove overwrite never leaves a duplicate.
    private static func itemCount(service: String, account: String) -> Int {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecMatchLimit as String: kSecMatchLimitAll,
            kSecReturnAttributes as String: true,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return (result as? [[String: Any]])?.count ?? 1
        case errSecItemNotFound:
            return 0
        default:
            return -1
        }
    }

    /// Deletes a single account's item directly, bypassing `KeychainCredentialStore.clear()`
    /// (which removes all three), so a test can simulate "url saved, sender key never was"
    /// without a store API that allows partial saves.
    private static func deleteRawItem(service: String, account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    @Test
    func saveThenLoadRoundTrips() throws {
        let store = KeychainCredentialStore(service: Self.throwawayService())
        defer { try? store.clear() }

        let saved = WebhookCredentials(
            url: Self.fixtureURL, senderKey: Self.fixtureSenderKey,
            headerName: Self.fixtureHeaderName)
        try store.save(saved)

        let loaded = try store.load()
        #expect(loaded == saved)
    }

    @Test
    func secondSaveOverwritesWithoutDuplicate() throws {
        let service = Self.throwawayService()
        let store = KeychainCredentialStore(service: service)
        defer { try? store.clear() }

        try store.save(
            WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureSenderKey,
                headerName: Self.fixtureHeaderName))
        let overwrite = WebhookCredentials(
            url: Self.fixtureURL2, senderKey: Self.fixtureSenderKey2,
            headerName: Self.fixtureHeaderName2)
        try store.save(overwrite)

        let loaded = try store.load()
        #expect(loaded == overwrite)

        for account in ["webhook.url", "webhook.senderKey", "webhook.headerName"] {
            #expect(Self.itemCount(service: service, account: account) == 1)
        }
    }

    @Test
    func loadOnFreshServiceReturnsNil() throws {
        let store = KeychainCredentialStore(service: Self.throwawayService())
        defer { try? store.clear() }

        #expect(try store.load() == nil)
    }

    @Test
    func clearThenLoadReturnsNil() throws {
        let store = KeychainCredentialStore(service: Self.throwawayService())
        defer { try? store.clear() }

        try store.save(
            WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureSenderKey,
                headerName: Self.fixtureHeaderName))
        try store.clear()

        #expect(try store.load() == nil)
    }

    /// Store tolerance on READ is deliberate: an empty saved header falls back to the
    /// default rather than failing load. 01-11 rejects an empty header on input -- a
    /// different layer, not a contradiction to "fix" here.
    @Test
    func emptyHeaderNameFallsBackToDefault() throws {
        let store = KeychainCredentialStore(service: Self.throwawayService())
        defer { try? store.clear() }

        try store.save(
            WebhookCredentials(url: Self.fixtureURL, senderKey: Self.fixtureSenderKey, headerName: ""))

        let loaded = try store.load()
        #expect(loaded?.headerName == WebhookCredentials.defaultHeaderName)
        #expect(loaded?.url == Self.fixtureURL)
        #expect(loaded?.senderKey == Self.fixtureSenderKey)
    }

    @Test
    func missingUrlOrSenderKeyReturnsNilOnLoad() throws {
        let service = Self.throwawayService()
        let store = KeychainCredentialStore(service: service)
        defer { try? store.clear() }

        try store.save(
            WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureSenderKey,
                headerName: Self.fixtureHeaderName))
        Self.deleteRawItem(service: service, account: "webhook.url")
        #expect(try store.load() == nil)

        try store.clear()
        try store.save(
            WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureSenderKey,
                headerName: Self.fixtureHeaderName))
        Self.deleteRawItem(service: service, account: "webhook.senderKey")
        #expect(try store.load() == nil)
    }
}
