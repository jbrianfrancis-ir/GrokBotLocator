import Foundation
import Testing
@testable import GrokBotLocator

/// Proves every branch of `PingSender.send(label:)` with four fakes and no network, no disk,
/// no device: missing/unreadable credentials refuse before any fix or POST is attempted, a
/// fix failure never reaches the transport, a response's exact status code and body ride along
/// in `PingAttempt`, and the phase-03 queue seam only ever receives a `.retryable` disposition
/// -- never a `.sent` or `.permanentFailure` one, 401 included.
@Suite
struct PingSenderTests {

    // MARK: Fakes

    /// Returns a caller-set credential, or throws a caller-set error. `@unchecked Sendable`
    /// per `SettingsModelTests`'s `FakeCredentialStore` -- state is only ever touched
    /// sequentially within one awaited test.
    private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
        var stored: WebhookCredentials?
        var errorToThrow: Error?
        private(set) var loadCallCount = 0

        func load() throws -> WebhookCredentials? {
            loadCallCount += 1
            if let errorToThrow { throw errorToThrow }
            return stored
        }

        func save(_ credentials: WebhookCredentials) throws {}
        func clear() throws {}
    }

    private final class FakeLocationFixProvider: LocationFixProvider, @unchecked Sendable {
        var fixToReturn: LocationFix?
        var errorToThrow: Error?
        private(set) var currentFixCallCount = 0

        func currentFix() async throws -> LocationFix {
            currentFixCallCount += 1
            if let errorToThrow { throw errorToThrow }
            guard let fixToReturn else {
                throw LocationFixError.unavailable
            }
            return fixToReturn
        }

        func authorizationNotice() async -> String? { nil }
    }

    /// Records the payload and credentials it received and replays a caller-set
    /// `PingResponse` or `Error`.
    private final class FakeTransport: PingTransport, @unchecked Sendable {
        var responseToReturn: PingResponse?
        var errorToThrow: Error?
        private(set) var sendCallCount = 0
        private(set) var capturedPayload: PingPayload?
        private(set) var capturedCredentials: WebhookCredentials?

        func send(_ payload: PingPayload, using credentials: WebhookCredentials) async throws -> PingResponse {
            sendCallCount += 1
            capturedPayload = payload
            capturedCredentials = credentials
            if let errorToThrow { throw errorToThrow }
            guard let responseToReturn else {
                throw PingTransportError.notAnHTTPResponse
            }
            return responseToReturn
        }
    }

    /// A spy on the phase-03 queue seam: counts calls and keeps every payload and reason
    /// handed to it.
    private final class FakeSink: PendingPingSink, @unchecked Sendable {
        private(set) var enqueueCallCount = 0
        private(set) var payloads: [PingPayload] = []
        private(set) var reasons: [String] = []

        func enqueue(_ payload: PingPayload, reason: String) async {
            enqueueCallCount += 1
            payloads.append(payload)
            reasons.append(reason)
        }
    }

    // MARK: Fixtures -- synthetic values only, none resolves anywhere.

    private static let fixtureCredentials = WebhookCredentials(
        url: URL(string: "https://example.invalid/webhook")!,
        senderKey: "dummy-sender-key-ping-sender-test",
        headerName: "X-Test-Key")

    private static let fixtureFix = LocationFix(
        latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5, timestamp: Date())

    private struct Fakes {
        let credentials = FakeCredentialStore()
        let fixes = FakeLocationFixProvider()
        let transport = FakeTransport()
        let sink = FakeSink()

        func makeSender() -> PingSender {
            PingSender(credentials: credentials, fixes: fixes, transport: transport, pending: sink)
        }
    }

    // MARK: Credentials

    @Test
    func nothingStoredRefusesBeforeAnyFixOrPost() async {
        let fakes = Fakes()
        fakes.credentials.stored = nil

        let attempt = await fakes.makeSender().send(label: "Home")

        guard case .permanentFailure(let reason) = attempt.disposition else {
            Issue.record("expected .permanentFailure, got \(attempt.disposition)")
            return
        }
        #expect(reason.contains("Settings"))
        #expect(attempt.fix == nil)
        #expect(attempt.statusCode == nil)
        #expect(attempt.responseBody == nil)
        #expect(fakes.fixes.currentFixCallCount == 0)
        #expect(fakes.transport.sendCallCount == 0)
        #expect(fakes.sink.enqueueCallCount == 0)
    }

    @Test
    func aThrowingStoreRefusesTheSameWay() async {
        let fakes = Fakes()
        fakes.credentials.errorToThrow = CredentialStoreError(operation: "load", status: -1)

        let attempt = await fakes.makeSender().send(label: "Home")

        guard case .permanentFailure(let reason) = attempt.disposition else {
            Issue.record("expected .permanentFailure, got \(attempt.disposition)")
            return
        }
        #expect(reason.contains("Settings"))
        #expect(fakes.fixes.currentFixCallCount == 0)
        #expect(fakes.transport.sendCallCount == 0)
    }

    // MARK: Fix failure

    @Test
    func aFixTimeoutNeverReachesTheTransport() async {
        let fakes = Fakes()
        fakes.credentials.stored = Self.fixtureCredentials
        fakes.fixes.errorToThrow = LocationFixError.timedOut

        let attempt = await fakes.makeSender().send(label: "Home")

        guard case .permanentFailure(let reason) = attempt.disposition else {
            Issue.record("expected .permanentFailure, got \(attempt.disposition)")
            return
        }
        #expect(reason == LocationFixError.timedOut.reason)
        #expect(fakes.transport.sendCallCount == 0)
        #expect(fakes.sink.enqueueCallCount == 0)
    }

    // MARK: Transport responses

    @Test
    func aTwoHundredIsSentAndCarriesTheExactStatusAndBody() async {
        let fakes = Fakes()
        fakes.credentials.stored = Self.fixtureCredentials
        fakes.fixes.fixToReturn = Self.fixtureFix
        fakes.transport.responseToReturn = PingResponse(statusCode: 200, body: #"{"ok":true}"#)

        let attempt = await fakes.makeSender().send(label: "Gallipoli")

        #expect(attempt.disposition == .sent)
        #expect(attempt.statusCode == 200)
        #expect(attempt.responseBody == #"{"ok":true}"#)
        #expect(fakes.sink.enqueueCallCount == 0)

        guard let sentPayload = fakes.transport.capturedPayload else {
            Issue.record("expected a captured payload")
            return
        }
        #expect(sentPayload.latitude == Self.fixtureFix.latitude)
        #expect(sentPayload.longitude == Self.fixtureFix.longitude)
        #expect(sentPayload.accuracyMetres == Self.fixtureFix.accuracyMetres)
        #expect(sentPayload.label == "Gallipoli")
    }

    @Test
    func aFourOhOneIsPermanentAndNeverReachesTheSink() async {
        let fakes = Fakes()
        fakes.credentials.stored = Self.fixtureCredentials
        fakes.fixes.fixToReturn = Self.fixtureFix
        fakes.transport.responseToReturn = PingResponse(statusCode: 401, body: "unauthorized")

        let attempt = await fakes.makeSender().send(label: "Home")

        guard case .permanentFailure = attempt.disposition else {
            Issue.record("expected .permanentFailure, got \(attempt.disposition)")
            return
        }
        #expect(attempt.statusCode == 401)
        #expect(attempt.responseBody == "unauthorized")
        #expect(fakes.sink.enqueueCallCount == 0)
    }

    @Test
    func aFiveOhThreeIsRetryableAndReachesTheSinkWithTheSamePayload() async {
        let fakes = Fakes()
        fakes.credentials.stored = Self.fixtureCredentials
        fakes.fixes.fixToReturn = Self.fixtureFix
        fakes.transport.responseToReturn = PingResponse(statusCode: 503, body: "unavailable")

        let attempt = await fakes.makeSender().send(label: "Home")

        guard case .retryable = attempt.disposition else {
            Issue.record("expected .retryable, got \(attempt.disposition)")
            return
        }
        #expect(fakes.sink.enqueueCallCount == 1)
        #expect(fakes.sink.payloads.first == fakes.transport.capturedPayload)
    }

    @Test
    func aTransportErrorIsRetryableAndReachesTheSink() async {
        let fakes = Fakes()
        fakes.credentials.stored = Self.fixtureCredentials
        fakes.fixes.fixToReturn = Self.fixtureFix
        fakes.transport.errorToThrow = URLError(.notConnectedToInternet)

        let attempt = await fakes.makeSender().send(label: "Home")

        guard case .retryable = attempt.disposition else {
            Issue.record("expected .retryable, got \(attempt.disposition)")
            return
        }
        #expect(attempt.statusCode == nil)
        #expect(fakes.sink.enqueueCallCount == 1)
    }

    // MARK: Never leaks the sender key

    @Test
    func noAttemptReasonEverContainsTheSenderKey() async {
        let cases: [() async -> PingAttempt] = [
            {
                let fakes = Fakes()
                fakes.credentials.stored = nil
                return await fakes.makeSender().send(label: "Home")
            },
            {
                let fakes = Fakes()
                fakes.credentials.errorToThrow = CredentialStoreError(operation: "load", status: -1)
                return await fakes.makeSender().send(label: "Home")
            },
            {
                let fakes = Fakes()
                fakes.credentials.stored = Self.fixtureCredentials
                fakes.fixes.errorToThrow = LocationFixError.timedOut
                return await fakes.makeSender().send(label: "Home")
            },
            {
                let fakes = Fakes()
                fakes.credentials.stored = Self.fixtureCredentials
                fakes.fixes.fixToReturn = Self.fixtureFix
                fakes.transport.responseToReturn = PingResponse(statusCode: 401, body: "unauthorized")
                return await fakes.makeSender().send(label: "Home")
            },
            {
                let fakes = Fakes()
                fakes.credentials.stored = Self.fixtureCredentials
                fakes.fixes.fixToReturn = Self.fixtureFix
                fakes.transport.responseToReturn = PingResponse(statusCode: 503, body: "unavailable")
                return await fakes.makeSender().send(label: "Home")
            },
            {
                let fakes = Fakes()
                fakes.credentials.stored = Self.fixtureCredentials
                fakes.fixes.fixToReturn = Self.fixtureFix
                fakes.transport.errorToThrow = URLError(.notConnectedToInternet)
                return await fakes.makeSender().send(label: "Home")
            },
        ]

        for makeAttempt in cases {
            let attempt = await makeAttempt()
            switch attempt.disposition {
            case .permanentFailure(let reason), .retryable(let reason):
                #expect(!reason.contains(Self.fixtureCredentials.senderKey))
            case .sent:
                break
            }
        }
    }
}
