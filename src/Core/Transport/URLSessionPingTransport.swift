import Foundation

/// Thrown when the webhook's response is not HTTP -- should not happen over `https`, but a
/// thrown error beats a force-unwrap (ARCHITECTURE.md Forbidden).
enum PingTransportError: Error, Equatable {
    case notAnHTTPResponse
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
        var request = URLRequest(url: credentials.url)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        // Verbatim -- the stored sender key, never "Bearer <key>" (see 02-04-PLAN.md
        // backstop_truths; the settings footnote in 02-11 says so too).
        request.setValue(credentials.senderKey, forHTTPHeaderField: credentials.headerName)
        request.httpBody = try payload.encoded()

        let (data, response) = try await session.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw PingTransportError.notAnHTTPResponse
        }

        return PingResponse(statusCode: http.statusCode, body: String(decoding: data, as: UTF8.self))
    }
}
