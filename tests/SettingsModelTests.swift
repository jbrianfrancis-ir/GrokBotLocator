import Foundation
import Testing
@testable import GrokBotLocator

/// Proves `SettingsModel`'s validation, persistence and test connection with no Keychain, no
/// device and no network call -- everything routes through `FakeCredentialStore` and
/// `FakeSender`, in-memory stand-ins for the `CredentialStore` and `PingSending` protocols.
/// `SettingsModel` is `@MainActor`, so the whole suite must be too. Every fixture is a
/// non-resolving placeholder; none is a real credential.
@MainActor
@Suite
struct SettingsModelTests {

    /// Records the last saved value and how many times `save` was called, so a test can
    /// assert "nothing reached the fake" as well as "the fake got these exact values".
    private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
        var stored: WebhookCredentials?
        private(set) var savedCredentials: WebhookCredentials?
        private(set) var saveCallCount = 0
        /// Set to make the Keychain fail. Without these, every one of `SettingsModel`'s Keychain
        /// failure arms was unreachable by this suite, and a mutation turning "could not save"
        /// into `.saved` passed the whole gate -- the user told "Saved" while nothing was stored.
        var loadErrorToThrow: Error?
        var saveErrorToThrow: Error?
        var clearErrorToThrow: Error?

        init(stored: WebhookCredentials? = nil) {
            self.stored = stored
        }

        func load() throws -> WebhookCredentials? {
            if let loadErrorToThrow { throw loadErrorToThrow }
            return stored
        }

        func save(_ credentials: WebhookCredentials) throws {
            saveCallCount += 1
            if let saveErrorToThrow { throw saveErrorToThrow }
            savedCredentials = credentials
            stored = credentials
        }

        func clear() throws {
            if let clearErrorToThrow { throw clearErrorToThrow }
            stored = nil
            savedCredentials = nil
        }
    }

    private struct KeychainFailure: Error {}

    /// Replays a caller-set `PingAttempt` and, when `suspends` is true, parks inside
    /// `send(label:)` until the test calls `release()` -- so the in-flight window is directly
    /// observable. An `actor` rather than a plain `@unchecked Sendable` class because `send` is
    /// **async**: a non-isolated async method runs off the main actor (SE-0338), so counters it
    /// writes would be read by this `@MainActor` suite with no ordering between the two.
    /// `waitUntilEntered()` exists for the same reason -- the actor orders the handshake, so no
    /// test here has to poll a racily-read counter to find out when the send started.
    private actor FakeSender: PingSending {
        private var attempt: PingAttempt
        private let suspends: Bool
        private(set) var callCount = 0
        private(set) var labels: [String] = []
        private var parked: CheckedContinuation<Void, Never>?
        private var waiter: CheckedContinuation<Void, Never>?
        private var didEnter = false

        init(returning attempt: PingAttempt, suspends: Bool = false) {
            self.attempt = attempt
            self.suspends = suspends
        }

        /// Swaps in the attempt the *next* send returns.
        func stub(_ newAttempt: PingAttempt) {
            attempt = newAttempt
        }

        func send(label: String) async -> PingAttempt {
            callCount += 1
            labels.append(label)
            didEnter = true
            waiter?.resume()
            waiter = nil
            if suspends {
                await withCheckedContinuation { parked = $0 }
            }
            return attempt
        }

        /// Returns once `send(label:)` has been entered, whether that already happened or not.
        func waitUntilEntered() async {
            guard !didEnter else { return }
            await withCheckedContinuation { waiter = $0 }
        }

        /// Resumes a parked `send`, letting `testConnection()` finish.
        func release() {
            parked?.resume()
            parked = nil
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

    // MARK: Keychain failures -- every one of these arms was unreachable by this suite

    /// The defect this pins: a mutation turning this arm's `.error` into `.saved` passed the
    /// entire gate. The user would be told "Saved" while nothing reached the Keychain, which is
    /// the inverse of ARCHITECTURE's fail-fast rule -- and they would then ping with credentials
    /// the app does not have.
    @Test
    func aKeychainWriteFailureIsReportedAndNeverLooksLikeSuccess() {
        let fake = FakeCredentialStore()
        fake.saveErrorToThrow = KeychainFailure()
        let model = SettingsModel(store: fake)
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = Self.fixtureKey
        model.headerName = Self.fixtureHeader

        model.save()

        #expect(model.status != .saved)
        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(message.contains("Keychain"))
        #expect(!model.hasStoredKey, "a failed write must not leave the key-saved indicator on")
    }

    /// `save()` re-reads the stored key when the field was left untouched. If that read fails the
    /// model must say so rather than write an empty key over a good one.
    @Test
    func aFailedRereadOfTheStoredKeyIsReportedAndWritesNothing() {
        let fake = FakeCredentialStore(
            stored: WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureKey, headerName: Self.fixtureHeader))
        let model = SettingsModel(store: fake)
        model.load()
        fake.loadErrorToThrow = KeychainFailure()
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = ""

        model.save()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(message.contains("Keychain"))
        #expect(fake.saveCallCount == 0, "nothing may be written when the re-read failed")
    }

    /// A stored key that reads back empty is not a usable credential: say the key is missing
    /// rather than silently saving an empty one.
    @Test
    func anEmptyStoredKeyIsReportedAsMissingAndWritesNothing() {
        let fake = FakeCredentialStore(
            stored: WebhookCredentials(
                url: Self.fixtureURL, senderKey: "", headerName: Self.fixtureHeader))
        let model = SettingsModel(store: fake)
        model.load()
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = ""

        model.save()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(message.lowercased().contains("sender key"))
        #expect(fake.saveCallCount == 0)
    }

    @Test
    func aKeychainLoadFailureIsReportedRatherThanSwallowed() {
        let fake = FakeCredentialStore()
        fake.loadErrorToThrow = KeychainFailure()
        let model = SettingsModel(store: fake)

        model.load()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(message.contains("Keychain"))
    }

    @Test
    func aKeychainClearFailureIsReportedAndLeavesTheFieldsAlone() {
        let fake = FakeCredentialStore(
            stored: WebhookCredentials(
                url: Self.fixtureURL, senderKey: Self.fixtureKey, headerName: Self.fixtureHeader))
        let model = SettingsModel(store: fake)
        model.load()
        fake.clearErrorToThrow = KeychainFailure()

        model.clear()

        guard case .error(let message) = model.status else {
            Issue.record("expected .error, got \(model.status)")
            return
        }
        #expect(message.contains("Keychain"))
        #expect(model.hasStoredKey, "a failed clear must not pretend the key is gone")
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

    // MARK: Test connection (REQ-11) -- the exact status and body, never a silent failure.

    @Test
    func noSenderProducesAnUnavailableReport() async {
        let model = SettingsModel(store: FakeCredentialStore())

        await model.testConnection()

        guard let report = model.connectionReport else {
            Issue.record("expected a report, got nil")
            return
        }
        #expect(report.succeeded == false)
        #expect(!report.headline.isEmpty)
        #expect(report.statusCode == nil)
        #expect(report.responseBody == nil)
        #expect(model.isTesting == false)
    }

    @Test
    func sentAttemptCarriesStatusAndBody() async {
        let sender = FakeSender(
            returning: PingAttempt(
                fix: nil, disposition: .sent, statusCode: 200, responseBody: "{\"ok\":true}"))
        let model = SettingsModel(store: FakeCredentialStore(), sender: sender)

        await model.testConnection()

        guard let report = model.connectionReport else {
            Issue.record("expected a report, got nil")
            return
        }
        #expect(report.succeeded == true)
        #expect(report.statusCode == 200)
        #expect(report.responseBody == "{\"ok\":true}")
        #expect(!report.headline.isEmpty)
        // The same `PingSending` the home screen's button uses, reached exactly once, with the
        // literal label that marks a diagnostic ping at the receiving end.
        #expect(await sender.labels == ["Test connection"])
    }

    @Test
    func unauthorizedAttemptShowsItsCodeAndBody() async {
        // The disposition comes from the real `PingClassifier`, so the headline asserted below
        // is the sentence the app would actually show for a 401 -- not one authored here.
        let response = PingResponse(statusCode: 401, body: "unauthorized")
        let sender = FakeSender(
            returning: PingAttempt(
                fix: nil, disposition: PingClassifier.disposition(for: response),
                statusCode: response.statusCode, responseBody: response.body))
        let model = SettingsModel(store: FakeCredentialStore(), sender: sender)

        await model.testConnection()

        guard let report = model.connectionReport else {
            Issue.record("expected a report, got nil")
            return
        }
        #expect(report.succeeded == false)
        #expect(report.statusCode == 401)
        #expect(report.responseBody == "unauthorized")
        #expect(report.headline.contains("401"))
    }

    @Test
    func aLongResponseBodyIsNotTruncated() async {
        let longBody = String(repeating: "a", count: 5000)
        let sender = FakeSender(
            returning: PingAttempt(
                fix: nil, disposition: .sent, statusCode: 200, responseBody: longBody))
        let model = SettingsModel(store: FakeCredentialStore(), sender: sender)

        await model.testConnection()

        guard let report = model.connectionReport else {
            Issue.record("expected a report, got nil")
            return
        }
        #expect(report.responseBody?.count == 5000)
        #expect(report.responseBody == longBody)
    }

    @Test
    func anEmptyResponseBodyStaysEmpty() async {
        let sender = FakeSender(
            returning: PingAttempt(
                fix: nil, disposition: .sent, statusCode: 204, responseBody: ""))
        let model = SettingsModel(store: FakeCredentialStore(), sender: sender)

        await model.testConnection()

        guard let report = model.connectionReport else {
            Issue.record("expected a report, got nil")
            return
        }
        #expect(report.responseBody != nil)
        #expect(report.responseBody == "")
        #expect(report.statusCode == 204)
    }

    @Test
    func aSecondTestWhileOneIsInFlightIsIgnored() async {
        let sender = FakeSender(
            returning: PingAttempt(
                fix: nil, disposition: .sent, statusCode: 200, responseBody: "ok"),
            suspends: true)
        let model = SettingsModel(store: FakeCredentialStore(), sender: sender)

        let task = Task { await model.testConnection() }
        await sender.waitUntilEntered()

        #expect(model.isTesting == true)
        await model.testConnection()
        #expect(await sender.callCount == 1)

        await sender.release()
        await task.value

        #expect(model.isTesting == false)
        #expect(await sender.callCount == 1)
    }

    @Test
    func testConnectionLeavesSaveStatusAlone() async {
        let sender = FakeSender(
            returning: PingAttempt(
                fix: nil, disposition: .sent, statusCode: 200, responseBody: "ok"))
        let model = SettingsModel(store: FakeCredentialStore(), sender: sender)
        #expect(model.status == .idle)

        await model.testConnection()

        #expect(model.status == .idle)

        // A failing test connection must not overwrite a `.saved` status either -- `status`
        // belongs to save and clear, and the report is the only thing a test writes.
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = Self.fixtureKey
        model.save()
        #expect(model.status == .saved)

        await sender.stub(
            PingAttempt(
                fix: nil,
                disposition: .permanentFailure(reason: "Rejected by the webhook (HTTP 403)."),
                statusCode: 403, responseBody: "forbidden"))
        await model.testConnection()

        #expect(model.status == .saved)
        #expect(model.connectionReport?.succeeded == false)
    }
}
