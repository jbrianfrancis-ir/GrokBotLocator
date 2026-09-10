import Foundation

/// Thrown when the webhook's response is not HTTP -- should not happen over `https`, but a
/// thrown error beats a force-unwrap (ARCHITECTURE.md Forbidden).
enum PingTransportError: Error, Equatable {
    case notAnHTTPResponse
    /// The credentials would not produce an authenticated request: an empty key or header name, or
    /// a non-https URL. Refused rather than sent, per ARCHITECTURE's fail-fast rule.
    case incompleteCredentials
}

/// The one type in the app that talks to the network: a single POST of `payload.encoded()`
/// to `credentials.url`, through an injected `URLSession` so delivery is testable without a
/// device or a live webhook (ARCHITECTURE.md). No retry, no backoff, no queue, no logging --
/// those live one layer up, in phase 03.
struct URLSessionPingTransport: PingTransport {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func send(_ payload: PingPayload, using credentials: WebhookCredentials) async throws -> PingResponse {
        // Fail CLOSED. ARCHITECTURE: "Missing URL, key, or header: refuse to send ... never a
        // default endpoint or empty key." That rule was enforced only by the settings form, and
        // below it nothing held the line: `KeychainCredentialStore.load()` returns credentials
        // whenever the items merely exist, so an empty key or header round-trips as valid, and
        // `PingSender` checks only for nil. It matters because CFNetwork DROPS a header whose name
        // or value holds a control character -- measured -- so the ping would leave with the
        // coordinates and no credential header at all, and a permissive endpoint would accept it
        // and report "Sent". The scheme is re-checked here too, since the https guarantee also
        // lived only in the form.
        guard !credentials.senderKey.isEmpty, !credentials.headerName.isEmpty,
            credentials.url.scheme == "https"
        else {
            throw PingTransportError.incompleteCredentials
        }

        var request = URLRequest(url: credentials.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Verbatim -- the stored sender key, never "Bearer <key>" (see 02-04-PLAN.md
        // backstop_truths; the settings footnote in 02-11 says so too).
        request.setValue(credentials.senderKey, forHTTPHeaderField: credentials.headerName)
        request.httpBody = try payload.encoded()

        // Redirects are REFUSED, not followed. URLSession follows up to 20 transparently, and a
        // webhook that answers 307 with a `Location` on another host makes the session re-send
        // this request there -- carrying the raw coordinates in the body, and the sender key too
        // whenever the user's header name is not one CFNetwork strips cross-host (only
        // `Authorization` is). The client then sees that host's 200, so the app would report a
        // green "Sent" for a ping delivered to somewhere the user never configured. A webhook is
        // a machine endpoint the user typed; it has no legitimate reason to redirect. Refusing
        // also makes `PingClassifier`'s 3xx arm reachable, which it was not while the session
        // consumed the redirect.
        let (data, response) = try await session.data(for: request, delegate: RedirectRefusal())

        guard let http = response as? HTTPURLResponse else {
            throw PingTransportError.notAnHTTPResponse
        }

        return PingResponse(statusCode: http.statusCode, body: String(decoding: data, as: UTF8.self))
    }
}

/// Refuses every HTTP redirect by answering `nil`, so the request is never re-sent anywhere but
/// the host the user configured. Stateless, so one instance per call is free. Internal rather
/// than private so the refusal can be asserted by a test instead of assumed.
final class RedirectRefusal: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest
    ) async -> URLRequest? {
        nil
    }
}
