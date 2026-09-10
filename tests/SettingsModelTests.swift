import Foundation
import Testing
@testable import GrokBotLocator

/// Proves `SettingsModel`'s validation and persistence with no Keychain, no device and no
/// network call -- everything routes through `FakeCredentialStore`, an in-memory stand-in
/// for the `CredentialStore` protocol. `SettingsModel` is `@MainActor`, so the whole suite
/// must be too. Every fixture is a non-resolving placeholder; none is a real credential.
@MainActor
@Suite
struct SettingsModelTests {

    /// Records the last saved value and how many times `save` was called, so a test can
    /// assert "nothing reached the fake" as well as "the fake got these exact values".
    private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
        var stored: WebhookCredentials?
        private(set) var savedCredentials: WebhookCredentials?
        private(set) var saveCallCount = 0

        init(stored: WebhookCredentials? = nil) {
            self.stored = stored
        }

        func load() throws -> WebhookCredentials? { stored }

        func save(_ credentials: WebhookCredentials) throws {
            saveCallCount += 1
            savedCredentials = credentials
            stored = credentials
        }

        func clear() throws {
            stored = nil
            savedCredentials = nil
        }
    }

    private static let fixtureURL = URL(string: "https://example.invalid/webhook")!
    private static let fixtureKey = "dummy-sender-key-settings-test"
    private static let fixtureHeader = "X-Settings-Test-Header"

    @Test
    func httpURLIsRejected() {
        let fake = FakeCredentialStore()
        let model = SettingsModel(store: fake)
        model.urlText = "http://example.invalid/webhook"
        model.senderKey = Self.fixtureKey

        model.save()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(!message.isEmpty)
        #expect(fake.saveCallCount == 0)
    }

    @Test
    func schemelessURLIsRejected() {
        let fake = FakeCredentialStore()
        let model = SettingsModel(store: fake)
        model.urlText = "example.invalid/webhook"
        model.senderKey = Self.fixtureKey

        model.save()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(!message.isEmpty)
        #expect(fake.saveCallCount == 0)
    }

    @Test
    func emptyOrWhitespaceKeyIsRejectedOnAFreshModel() {
        let fake = FakeCredentialStore()
        let model = SettingsModel(store: fake)
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = "   "

        model.save()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(message.localizedCaseInsensitiveContains("key"))
        #expect(fake.saveCallCount == 0)
    }

    @Test
    func emptyHeaderIsRejected() {
        let fake = FakeCredentialStore()
        let model = SettingsModel(store: fake)
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = Self.fixtureKey
        model.headerName = "   "

        model.save()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(message.localizedCaseInsensitiveContains("header"))
        #expect(fake.saveCallCount == 0)
    }

    @Test
    func validTrioSavesAndReachesTheStore() {
        let fake = FakeCredentialStore()
        let model = SettingsModel(store: fake)
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = Self.fixtureKey
        model.headerName = Self.fixtureHeader

        model.save()

        #expect(model.status == .saved)
        #expect(model.hasStoredKey)
        #expect(
            fake.savedCredentials
                == WebhookCredentials(
                    url: Self.fixtureURL, senderKey: Self.fixtureKey, headerName: Self.fixtureHeader))
    }

    @Test
    func loadFillsURLAndHeaderButNeverTheKey() {
        let fake = FakeCredentialStore(
            stored: WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureKey, headerName: Self.fixtureHeader))
        let model = SettingsModel(store: fake)

        model.load()

        #expect(model.urlText == Self.fixtureURL.absoluteString)
        #expect(model.headerName == Self.fixtureHeader)
        #expect(model.hasStoredKey)
        #expect(model.senderKey.isEmpty)
    }

    @Test
    func savingAnUntouchedKeyRereadsAndPreservesIt() {
        let fake = FakeCredentialStore(
            stored: WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureKey, headerName: Self.fixtureHeader))
        let model = SettingsModel(store: fake)
        model.load()

        // senderKey is left untouched (D-10 never populates it); only the url changes.
        let newURL = URL(string: "https://example2.invalid/webhook")!
        model.urlText = newURL.absoluteString

        model.save()

        #expect(model.status == .saved)
        #expect(fake.savedCredentials?.senderKey == Self.fixtureKey)
        #expect(fake.savedCredentials?.url == newURL)
    }

    @Test
    func clearEmptiesEverythingAndClearsHasStoredKey() throws {
        let fake = FakeCredentialStore(
            stored: WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureKey, headerName: Self.fixtureHeader))
        let model = SettingsModel(store: fake)
        model.load()
        #expect(model.hasStoredKey)

        model.clear()

        #expect(model.urlText.isEmpty)
        #expect(model.senderKey.isEmpty)
        #expect(model.headerName == WebhookCredentials.defaultHeaderName)
        #expect(!model.hasStoredKey)
        #expect(try fake.load() == nil)
    }

    @Test
    func freshModelHeaderNameDefaultsToAuthorization() {
        let model = SettingsModel(store: FakeCredentialStore())
        #expect(model.headerName == WebhookCredentials.defaultHeaderName)
        #expect(!model.hasStoredKey)
    }
}
