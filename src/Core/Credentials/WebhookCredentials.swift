import Foundation

/// The three pieces of the Grok webhook credential: destination URL, sender key, and the
/// header name the key rides in. Nothing here is a default value for `url` or `senderKey` --
/// ARCHITECTURE.md requires fail-fast, never a fallback endpoint or an empty stand-in key.
/// `description`/`debugDescription` redact every field so an accidental `"\(credentials)"`
/// interpolation -- in a log line, a crash report, anything -- never leaks the key or URL.
struct WebhookCredentials: Sendable, Equatable {
    let url: URL
    let senderKey: String
    let headerName: String

    /// The only permitted default: the header name the key rides in when the user hasn't
    /// picked one. There is no equivalent default for `url` or `senderKey`.
    static let defaultHeaderName = "Authorization"
}

extension WebhookCredentials: CustomStringConvertible, CustomDebugStringConvertible {
    var description: String {
        "WebhookCredentials(url: <redacted>, senderKey: <redacted>, headerName: <redacted>)"
    }

    var debugDescription: String { description }
}
