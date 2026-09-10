import Foundation
import Testing
@testable import GrokBotLocator

/// Proves the two leak paths ARCHITECTURE.md forbids stay closed: saving a credential must
/// never spill into `UserDefaults`, and an accidental `"\(credentials)"` interpolation must
/// never surface the url, sender key, or header name. Nothing here writes to the app's real
/// Keychain items -- storage checks use a throwaway `service` and clear it when done.
@Suite
struct CredentialLeakTests {

    private static let fixtureURL = URL(string: "https://example.invalid/webhook-leak-check")!
    private static let fixtureSenderKey = "dummy-sender-key-leak-check"
    private static let fixtureHeaderName = "X-Leak-Check-Header"

    private static func throwawayService() -> String {
        "test." + UUID().uuidString
    }

    /// Every key/value in `UserDefaults.standard`, flattened to one searchable string --
    /// a full dump, not a guess at which key a leak might use.
    private static func flattenedUserDefaultsDump() -> String {
        UserDefaults.standard.dictionaryRepresentation()
            .map { key, value in "\(key)=\(String(describing: value))" }
            .joined(separator: "\n")
    }

    @Test
    func savingNeverTouchesUserDefaults() throws {
        let store = KeychainCredentialStore(service: Self.throwawayService())
        defer { try? store.clear() }

        try store.save(
            WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureSenderKey,
                headerName: Self.fixtureHeaderName))

        let dump = Self.flattenedUserDefaultsDump()
        #expect(!dump.contains(Self.fixtureURL.absoluteString))
        #expect(!dump.contains(Self.fixtureSenderKey))
        #expect(!dump.contains(Self.fixtureHeaderName))
    }

    @Test
    func descriptionAndDebugDescriptionRedactAllFields() {
        let credentials = WebhookCredentials(
            url: Self.fixtureURL, senderKey: Self.fixtureSenderKey,
            headerName: Self.fixtureHeaderName)

        let described = String(describing: credentials)
        let reflected = String(reflecting: credentials)

        for text in [described, reflected] {
            #expect(!text.contains(Self.fixtureURL.absoluteString))
            #expect(!text.contains(Self.fixtureSenderKey))
            #expect(!text.contains(Self.fixtureHeaderName))
        }
    }
}
