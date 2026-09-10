import Foundation

/// What a send attempt returned from the webhook: the exact HTTP status code and the exact
/// response body as text, decoded UTF-8 (empty string when there is none). REQUIREMENTS.md
/// shows both, so neither is collapsed into a category here -- that collapsing is
/// `PingClassifier`'s job, one layer up.
struct PingResponse: Sendable, Equatable {
    let statusCode: Int
    let body: String
}

/// What a disposition means for the caller: delivered, rejected for good, or worth retrying.
/// Every failure case carries a finished-sentence reason -- what happened and what to do next,
/// with any status code inside the sentence, never a bare code (DESIGN.md).
enum PingDisposition: Sendable, Equatable {
    case sent
    case permanentFailure(reason: String)
    case retryable(reason: String)
}

/// Sends one payload to the webhook. Protocol-backed and injected per ARCHITECTURE.md, so
/// delivery is testable without a device or a live webhook.
protocol PingTransport: Sendable {
    func send(_ payload: PingPayload, using credentials: WebhookCredentials) async throws -> PingResponse
}

/// Turns a `PingResponse` or a thrown transport error into a `PingDisposition` -- a pure
/// function over a status code, no `URLSession`, no credential, no I/O. Any 2xx is `.sent`.
/// 401/403 are permanent and point at Settings, since a wrong sender key or header name is
/// the ordinary cause. The rest of the 4xx range is left undecided by REQUIREMENTS.md (see
/// 02-03-PLAN.md backstop_truths) and is treated as permanent here too, naming the webhook
/// URL instead since a routing/path mistake is the ordinary cause there. 5xx is retryable.
/// Anything outside 200...599 (a redirect, a 1xx, a bogus code) is treated as permanent,
/// naming the code, since none of those is a "try again" situation. A thrown transport error
/// is always retryable, and the error itself is never interpolated into the reason -- it
/// could carry the URL or other detail not meant for a user-facing string.
enum PingClassifier {
    static func disposition(for response: PingResponse) -> PingDisposition {
        let code = response.statusCode
        switch code {
        case 200...299:
            return .sent
        case 401, 403:
            return .permanentFailure(
                reason: "Rejected by the webhook (HTTP \(code)). Check the sender key and header name in Settings."
            )
        case 400...499:
            return .permanentFailure(
                reason: "The webhook refused this ping (HTTP \(code)). Check the webhook URL in Settings."
            )
        case 500...599:
            return .retryable(
                reason: "The webhook is unavailable (HTTP \(code)). Try again in a moment."
            )
        default:
            return .permanentFailure(
                reason: "The webhook returned an unexpected response (HTTP \(code)). Check the webhook URL in Settings."
            )
        }
    }

    static func disposition(forTransportError error: Error) -> PingDisposition {
        .retryable(reason: "Could not reach the webhook — check your connection, then tap again.")
    }
}
