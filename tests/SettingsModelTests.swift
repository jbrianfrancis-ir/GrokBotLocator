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

        func send(label: String, using fix: LocationFix) async -> PingAttempt {
            await send(label: label)
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

    /// Records every `update(_:)` and answers `currentSettings()`/`authorizationNotice()` from
    /// whatever it was last told -- an actor, per `FakeSender` above, because `TriggerControlling`
    /// is async and a `@MainActor` suite must not read its counters with no ordering between
    /// the two. `await Task.yield()` before each return, per LEARNINGS, so a suite that
    /// forgets to await the actor boundary would still see interleaving rather than a
    /// same-thread illusion of synchronity.
    private actor FakeTriggerControl: TriggerControlling {
        private(set) var settings: TriggerSettings
        private(set) var recordedUpdates: [TriggerSettings] = []
        private var notice: String?
        /// What `authorizationNotice()` answers ONCE `update(_:)` has been called at least once
        /// -- lets `theNoticeRefreshesAfterATriggerChanges` prove the notice is re-read after a
        /// change rather than cached from `init`.
        private let noticeAfterUpdate: String?

        init(
            settings: TriggerSettings = .initial, notice: String? = nil,
            noticeAfterUpdate: String? = nil
        ) {
            self.settings = settings
            self.notice = notice
            self.noticeAfterUpdate = noticeAfterUpdate
        }

        func update(_ settings: TriggerSettings) async {
            await Task.yield()
            recordedUpdates.append(settings)
            self.settings = settings
            if let noticeAfterUpdate {
                notice = noticeAfterUpdate
            }
        }

        func currentSettings() async -> TriggerSettings {
            await Task.yield()
            return settings
        }

        func authorizationNotice() async -> String? {
            await Task.yield()
            return notice
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

    // MARK: Trigger controls (REQ-09/REQ-10) -- no CoreLocation, no UserDefaults; a fake
    // `TriggerControlling` stands in for `TriggerCoordinator`.

    /// Flips all three in sequence on ONE model, checking after each flip that the triggers
    /// already on stay on. `setVisits` goes SECOND deliberately: the defect this pins --
    /// rebuilding an update from `TriggerSettings.initial` instead of the model's current
    /// `triggerSettings` -- looks correct on a first flip (everything else is already off) and
    /// only shows up once an earlier switch has something to lose. Putting the suspect setter
    /// first would let the bug hide behind an all-false starting point.
    @Test
    func eachSwitchChangesOnlyItsOwnTrigger() async {
        let fake = FakeTriggerControl()
        let model = SettingsModel(store: FakeCredentialStore(), triggers: fake)

        await model.setSignificantChange(true)
        var recorded = await fake.recordedUpdates
        #expect(recorded.count == 1)
        #expect(recorded[0].significantChangeEnabled == true)
        #expect(recorded[0].visitsEnabled == false)
        #expect(recorded[0].geofenceEnabled == false)

        await model.setVisits(true)
        recorded = await fake.recordedUpdates
        #expect(recorded.count == 2)
        #expect(recorded[1].visitsEnabled == true)
        #expect(
            recorded[1].significantChangeEnabled == true,
            "significant change, already on, must be left alone")
        #expect(recorded[1].geofenceEnabled == false)

        await model.setGeofence(true)
        recorded = await fake.recordedUpdates
        #expect(recorded.count == 3)
        #expect(recorded[2].geofenceEnabled == true)
        #expect(
            recorded[2].significantChangeEnabled == true,
            "significant change, already on, must be left alone")
        #expect(
            recorded[2].visitsEnabled == true,
            "visits, already on, must be left alone")
    }

    /// REQ-09's floor, expressed through `SettingsModel` rather than `TriggerSettings` directly
    /// -- proves the model routes through the clamp instead of forwarding the raw value.
    @Test
    func theIntervalCannotBeDrivenBelowTheFloor() async {
        let fake = FakeTriggerControl()
        let model = SettingsModel(store: FakeCredentialStore(), triggers: fake)

        await model.setMinimumInterval(2)

        let recorded = await fake.recordedUpdates
        #expect(recorded.count == 1)
        #expect(recorded[0].minimumIntervalSeconds == PingRateLimiter.hardFloor)
        #expect(model.triggerSettings.minimumIntervalSeconds == PingRateLimiter.hardFloor)
    }

    /// A refused Always prompt has to produce its sentence without the user leaving the
    /// screen -- so the notice must be re-read AFTER `update(_:)`, not just on `loadTriggers()`.
    @Test
    func theNoticeRefreshesAfterATriggerChanges() async {
        let refusedSentence = TriggerAuthorizationNotice.notice(
            for: .authorizedWhenInUse, alwaysWasRequested: true)
        let fake = FakeTriggerControl(noticeAfterUpdate: refusedSentence)
        let model = SettingsModel(store: FakeCredentialStore(), triggers: fake)

        await model.loadTriggers()
        #expect(model.triggerNotice == nil)

        await model.setVisits(true)

        #expect(model.triggerNotice == refusedSentence)
    }

    /// ARCHITECTURE: fully usable at When In Use. A missing coordinator (the app came up with
    /// none) must not make Settings unusable -- the switch still moves even with nothing
    /// downstream to arm it.
    @Test
    func aModelWithNoCoordinatorStillFlipsItsSwitches() async {
        let model = SettingsModel(store: FakeCredentialStore(), triggers: nil)

        await model.setVisits(true)

        #expect(model.triggerSettings.visitsEnabled == true)
    }

    @Test
    func loadTriggersReadsTheCurrentSettingsAndNotice() async {
        let settings = TriggerSettings(
            significantChangeEnabled: false, visitsEnabled: false, geofenceEnabled: true,
            minimumIntervalSeconds: 120)
        let notice = "a fixture notice, not a real sentence"
        let fake = FakeTriggerControl(settings: settings, notice: notice)
        let model = SettingsModel(store: FakeCredentialStore(), triggers: fake)

        await model.loadTriggers()

        #expect(model.triggerSettings == settings)
        #expect(model.triggerNotice == notice)
    }

    /// ARCHITECTURE: fully usable at When In Use -- turning triggers on and off must never
    /// touch the credential fields or the Save path.
    @Test
    func manualPingsAreNeverGatedByATriggerSwitch() async {
        let fake = FakeTriggerControl()
        let model = SettingsModel(store: FakeCredentialStore(), triggers: fake)
        model.urlText = Self.fixtureURL.absoluteString
        model.senderKey = Self.fixtureKey
        model.headerName = Self.fixtureHeader
        model.save()
        let urlBefore = model.urlText
        let keyBefore = model.senderKey
        let headerBefore = model.headerName
        let hasStoredBefore = model.hasStoredKey

        await model.setSignificantChange(true)
        await model.setVisits(true)
        await model.setGeofence(true)
        await model.setSignificantChange(false)
        await model.setVisits(false)
        await model.setGeofence(false)

        #expect(model.urlText == urlBefore)
        #expect(model.senderKey == keyBefore)
        #expect(model.headerName == headerBefore)
        #expect(model.hasStoredKey == hasStoredBefore)
    }

    /// The full chain, the UI's own path: a real `TriggerCoordinator` (not `FakeTriggerControl`)
    /// wired to a real `PingRateLimiter`, driven through `SettingsModel.setMinimumInterval` --
    /// the exact call SettingsView's Stepper makes -- and asserted against the GATE, not against
    /// what got persisted. LEARNINGS: a fake that returns without suspending cannot test an
    /// actor, so this uses the real limiter throughout, never a fake.
    @Test
    func anIntervalChangedInSettingsReachesTheGate() async {
        let limiter = PingRateLimiter()
        let coordinator = TriggerCoordinator(
            source: TriggerCoordinatorTests.FakeTriggerSource(),
            geofence: InMemoryGeofence(),
            pinger: TriggerCoordinatorTests.CountingPinger(scriptedResults: []),
            // No trigger event is ever delivered in this test, so no fix is ever requested.
            fixes: TriggerCoordinatorTests.FakeFixProvider(result: .failure(KeychainFailure())),
            settingsStore: TriggerCoordinatorTests.FakeSettingsStore(initial: .initial),
            lastPing: InMemoryLastPingStore(),
            rateLimiter: limiter,
            drain: {})
        await coordinator.start()

        let model = SettingsModel(store: FakeCredentialStore(), triggers: coordinator)
        await model.loadTriggers()
        await model.setMinimumInterval(PingRateLimiter.defaultInterval * 2)

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(await limiter.claim(at: t) == .allowed)
        // Halfway between the default and twice the default -- ALLOWED at the old wiring
        // (default interval), REFUSED once the doubled interval set in Settings reaches the gate.
        guard
            case .tooSoon = await limiter.claim(
                at: t.addingTimeInterval(PingRateLimiter.defaultInterval * 1.5))
        else {
            Issue.record("the gate ignored the interval set in Settings")
            return
        }
    }
}
