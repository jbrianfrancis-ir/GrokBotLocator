import Foundation
import Testing
@testable import GrokBotLocator

/// A `URLProtocol` stub registered on an ephemeral `URLSessionConfiguration` -- the means by
/// which `URLSessionPingTransport` is exercised with no network and no device (ARCHITECTURE.md).
/// State is static (the system, not the test, constructs instances of a registered protocol
/// class) and guarded by an `NSLock`. `URLProtocol` strips `httpBody` from the request it is
/// handed, so the body is captured from `httpBodyStream` instead.
final class StubURLProtocol: URLProtocol {
    struct Stub {
        var statusCode: Int = 200
        var body: Data = Data()
        var error: Error?
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var _stub = Stub()
    nonisolated(unsafe) private static var _capturedRequest: URLRequest?
    nonisolated(unsafe) private static var _capturedBody: Data?

    static var stub: Stub {
        get { lock.withLock { _stub } }
        set { lock.withLock { _stub = newValue } }
    }

    static var capturedRequest: URLRequest? {
        lock.withLock { _capturedRequest }
    }

    static var capturedBody: Data? {
        lock.withLock { _capturedBody }
    }

    /// Resets all recorded and stubbed state -- called at the start of every test so one
    /// test's stub can never leak into the next.
    static func reset() {
        lock.withLock {
            _stub = Stub()
            _capturedRequest = nil
            _capturedBody = nil
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let bodyData = Self.readAllFromBodyStream(of: request)
        Self.lock.withLock {
            Self._capturedRequest = request
            Self._capturedBody = bodyData
        }

        let stub = Self.stub

        if let error = stub.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }

        guard let url = request.url,
              let response = HTTPURLResponse(
                url: url, statusCode: stub.statusCode, httpVersion: "HTTP/1.1", headerFields: nil)
        else {
            client?.urlProtocol(self, didFailWithError: PingTransportError.notAnHTTPResponse)
            return
        }

        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func readAllFromBodyStream(of request: URLRequest) -> Data? {
        guard let stream = request.httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }

        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let bytesRead = stream.read(&buffer, maxLength: bufferSize)
            if bytesRead > 0 {
                data.append(buffer, count: bytesRead)
            } else {
                break
            }
        }
        return data
    }
}

/// Drives `URLSessionPingTransport` through `StubURLProtocol` -- the request it builds, the
/// response it returns, and the error it throws -- with no network and no device. `.serialized`
/// because every test shares `StubURLProtocol`'s static stub/capture state.
@Suite(.serialized)
struct PingTransportTests {

    private static let credentials = WebhookCredentials(
        url: URL(string: "https://example.invalid/webhook")!,
        senderKey: "not-a-real-key.invalid",
        headerName: "X-Test-Key")

    private static let payload = PingPayload(
        latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5, label: "Gallipoli",
        capturedAt: Date(timeIntervalSince1970: 1_700_000_000))

    private func makeTransport() -> URLSessionPingTransport {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSessionPingTransport(session: URLSession(configuration: configuration))
    }

    @Test
    func aTwoHundredReturnsItsStatusCodeAndExactBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 200, body: Data(#"{"ok":true}"#.utf8))

        let response = try await makeTransport().send(Self.payload, using: Self.credentials)

        #expect(response.statusCode == 200)
        #expect(response.body == #"{"ok":true}"#)
    }

    @Test
    func theRequestIsAPostToTheCredentialURLWithTheRightHeadersAndBody() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 200, body: Data())

        _ = try await makeTransport().send(Self.payload, using: Self.credentials)

        guard let request = StubURLProtocol.capturedRequest else {
            Issue.record("expected a captured request")
            return
        }
        #expect(request.httpMethod == "POST")
        #expect(request.url == Self.credentials.url)
        #expect(request.value(forHTTPHeaderField: "X-Test-Key") == Self.credentials.senderKey)
        #expect(request.value(forHTTPHeaderField: "X-Test-Key")?.hasPrefix("Bearer ") == false)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        guard let capturedBody = StubURLProtocol.capturedBody else {
            Issue.record("expected a captured body")
            return
        }

        // Primary: parsed-field equality against the payload's own values -- holds regardless
        // of key order.
        let parsed = try JSONSerialization.jsonObject(with: capturedBody)
        guard let dict = parsed as? [String: Any] else {
            Issue.record("expected a JSON object, got \(parsed)")
            return
        }
        #expect((dict["lat"] as? NSNumber)?.doubleValue == Self.payload.latitude)
        #expect((dict["lng"] as? NSNumber)?.doubleValue == Self.payload.longitude)
        #expect((dict["accuracy_m"] as? NSNumber)?.doubleValue == Self.payload.accuracyMetres)
        #expect(dict["label"] as? String == Self.payload.label)

        // Secondary: raw byte-equality against a second encoded() call -- legitimate only
        // because 02-02 made the encoder byte-stable (proven at 50 identical encodes).
        #expect(capturedBody == (try Self.payload.encoded()))
    }

    @Test
    func aTwoOhFourWithNoBodyReturnsAnEmptyBodyString() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 204, body: Data())

        let response = try await makeTransport().send(Self.payload, using: Self.credentials)

        #expect(response.statusCode == 204)
        #expect(response.body == "")
    }

    @Test
    func aTransportFailureThrowsRatherThanReturningAResponse() async {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(error: URLError(.notConnectedToInternet))

        do {
            _ = try await makeTransport().send(Self.payload, using: Self.credentials)
            Issue.record("expected send to throw")
        } catch is PingTransportError {
            Issue.record("expected the underlying transport error, not PingTransportError")
        } catch {
            // expected: a URLError, not PingTransportError.notAnHTTPResponse
        }
    }

    @Test
    func noAuthorizationHeaderAppearsWhenTheCredentialUsesADifferentHeaderName() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 200, body: Data())

        _ = try await makeTransport().send(Self.payload, using: Self.credentials)

        guard let headers = StubURLProtocol.capturedRequest?.allHTTPHeaderFields else {
            Issue.record("expected a captured request with headers")
            return
        }
        #expect(!headers.keys.contains { $0.caseInsensitiveCompare("Authorization") == .orderedSame })
    }
    // MARK: Redirects are refused, not followed

    /// The defect this pins: URLSession follows up to 20 redirects transparently. A webhook that
    /// answers 307 with a `Location` on another host made CFNetwork re-send this request there,
    /// carrying the raw coordinates in the body -- and the sender key too, unless the header
    /// happened to be `Authorization`, the only name CFNetwork strips cross-host. The client then
    /// saw that host's 200, so the app reported a green "Sent" for a ping delivered to a host the
    /// user never configured. One redirect response was the whole exploit.
    ///
    /// Asserts the delegate's answer, because that answer IS the refusal: returning nil from
    /// `willPerformHTTPRedirection` is what stops the re-send.
    @Test
    func theTransportRefusesARedirectToAnotherHost() async throws {
        let original = try #require(URL(string: "https://webhook.example.com/ping"))
        let elsewhere = try #require(URL(string: "https://attacker.example.net/leak"))
        let redirect = try #require(
            HTTPURLResponse(
                url: original, statusCode: 307, httpVersion: "HTTP/1.1",
                headerFields: ["Location": elsewhere.absoluteString]))
        let session = URLSession(configuration: .ephemeral)

        let followed = await RedirectRefusal().urlSession(
            session, task: session.dataTask(with: original),
            willPerformHTTPRedirection: redirect, newRequest: URLRequest(url: elsewhere))

        #expect(
            followed == nil,
            "a redirect must never be followed -- it re-sends the sender key and the coordinates")
    }

    /// And the classifier arm a refused redirect now actually reaches: while the session consumed
    /// the redirect, this arm was unreachable for a 3xx despite the comment claiming otherwise.
    @Test
    func aRefusedRedirectReadsAsAPermanentFailureNamingTheCode() {
        let disposition = PingClassifier.disposition(for: PingResponse(statusCode: 307, body: ""))

        guard case .permanentFailure(let reason) = disposition else {
            Issue.record("expected .permanentFailure for a 307, got \(disposition)")
            return
        }
        #expect(reason.contains("307"))
    }
    /// Survived a mutation: prefixing "Bearer " only when the header is `Authorization` passed,
    /// because the existing no-prefix assertion uses an `X-Test-Key` fixture -- while
    /// `Authorization` is `WebhookCredentials.defaultHeaderName`, the path real users hit.
    @Test
    func theDefaultAuthorizationHeaderAlsoCarriesTheKeyVerbatim() async throws {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 200, body: Data())
        let credentials = WebhookCredentials(
            url: Self.credentials.url, senderKey: Self.credentials.senderKey,
            headerName: WebhookCredentials.defaultHeaderName)

        _ = try await makeTransport().send(Self.payload, using: credentials)

        let request = try #require(StubURLProtocol.capturedRequest)
        let value = try #require(
            request.value(forHTTPHeaderField: WebhookCredentials.defaultHeaderName))
        #expect(value == Self.credentials.senderKey)
        #expect(!value.hasPrefix("Bearer "))
    }
    /// Fails CLOSED on credentials that cannot authenticate. Measured by the security review:
    /// CFNetwork DROPS a header whose name or value contains a control character, so without this
    /// guard the ping left with the coordinates and no credential header at all -- and a permissive
    /// endpoint would accept it and report "Sent". ARCHITECTURE forbids an empty key on the wire.
    @Test(arguments: [
        WebhookCredentials(
            url: URL(string: "https://example.invalid/webhook")!, senderKey: "",
            headerName: "X-Test-Key"),
        WebhookCredentials(
            url: URL(string: "https://example.invalid/webhook")!, senderKey: "k", headerName: ""),
        WebhookCredentials(
            url: URL(string: "http://example.invalid/webhook")!, senderKey: "k",
            headerName: "X-Test-Key"),
    ])
    func unusableCredentialsAreRefusedBeforeAnythingIsSent(credentials: WebhookCredentials) async {
        StubURLProtocol.reset()
        StubURLProtocol.stub = .init(statusCode: 200, body: Data())

        await #expect(throws: PingTransportError.incompleteCredentials) {
            try await makeTransport().send(Self.payload, using: credentials)
        }
        #expect(
            StubURLProtocol.capturedRequest == nil,
            "nothing may reach the network when the credentials cannot authenticate")
    }
}
