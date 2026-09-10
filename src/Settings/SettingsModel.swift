import Foundation
import Observation

/// The settings screen's state machine: load from a `CredentialStore`, validate on save,
/// report the outcome. No Keychain, no network, no view -- 01-12 renders this model, and
/// tests inject a fake store (see `SettingsModelTests`) so nothing here ever touches the
/// real Keychain. Never prints, logs, or interpolates a credential.
@Observable
@MainActor
final class SettingsModel {
    enum Status: Equatable {
        case idle
        case saved
        case error(String)
    }

    /// What the webhook answered to a test connection, carried verbatim for REQ-11: the exact
    /// status code and the exact body text, never collapsed into a category and never replaced
    /// by a placeholder word. Both are nil only when no response came back at all.
    struct ConnectionReport: Equatable, Sendable {
        let succeeded: Bool
        let headline: String
        let statusCode: Int?
        let responseBody: String?
    }

    var urlText: String = ""
    var senderKey: String = ""
    var headerName: String = WebhookCredentials.defaultHeaderName
    /// D-10: the only trace a saved key leaves in this model. `load()` never assigns the
    /// stored key to `senderKey` -- 01-12 renders its saved indicator from this instead.
    private(set) var hasStoredKey = false
    var status: Status = .idle
    /// The last test connection's result, or nil before one has run. 02-11 renders it.
    private(set) var connectionReport: ConnectionReport?
    /// True for exactly the span of one `testConnection()`, so the view can show a test in
    /// flight and a second call while one is running is ignored outright.
    private(set) var isTesting = false

    private let store: CredentialStore
    /// Optional so every existing call site and test builds a model without one; the app
    /// passes the same `PingSender` the home screen's button uses (02-13).
    private let sender: PingSending?

    /// Depends on the `CredentialStore` protocol only -- never constructs a
    /// `KeychainCredentialStore` itself -- so tests inject a fake and the real Keychain is
    /// never touched outside the app.
    init(store: CredentialStore, sender: PingSending? = nil) {
        self.store = store
        self.sender = sender
    }

    /// Fills `urlText` and `headerName` from the store. Never assigns the stored key to
    /// `senderKey` (D-10); `hasStoredKey` is the only signal a key exists. Nothing stored
    /// leaves both fields at their defaults and `hasStoredKey` false.
    func load() {
        do {
            guard let credentials = try store.load() else {
                urlText = ""
                headerName = WebhookCredentials.defaultHeaderName
                hasStoredKey = false
                return
            }
            urlText = credentials.url.absoluteString
            headerName = credentials.headerName
            hasStoredKey = true
        } catch {
            status = .error("Could not load saved settings from the Keychain — try again.")
        }
    }

    /// Validates all three fields, then persists through the `CredentialStore` protocol.
    /// Each failure sets `status = .error` naming the field and the fix, and writes
    /// nothing. An untouched `senderKey` while `hasStoredKey` is true re-reads the stored
    /// key from the store and writes it back unchanged -- the model never holds the key
    /// itself (D-10), so this is the only way a save doesn't blank it.
    func save() {
        guard let url = Self.normalizedHTTPSURL(from: urlText) else {
            status = .error("Webhook URL must start with https:// and include a host.")
            return
        }

        let trimmedKey = senderKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let keyToSave: String
        if !trimmedKey.isEmpty {
            keyToSave = trimmedKey
        } else if hasStoredKey {
            do {
                guard let existing = try store.load(), !existing.senderKey.isEmpty else {
                    status = .error("Sender key is missing — enter the webhook sender key.")
                    return
                }
                keyToSave = existing.senderKey
            } catch {
                status = .error(
                    "Could not read the stored sender key from the Keychain — enter it again.")
                return
            }
        } else {
            status = .error("Sender key cannot be empty — enter the webhook sender key.")
            return
        }

        let trimmedHeader = headerName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedHeader.isEmpty else {
            status = .error(
                "Header name cannot be empty — enter the header the key rides in, e.g. Authorization."
            )
            return
        }

        do {
            try store.save(
                WebhookCredentials(url: url, senderKey: keyToSave, headerName: trimmedHeader))
            hasStoredKey = true
            status = .saved
        } catch {
            status = .error("Could not save to the Keychain — try again.")
        }
    }

    /// Empties the store and every field, including `hasStoredKey` -- otherwise 01-12
    /// would keep showing a "key saved" indicator after clearing.
    func clear() {
        do {
            try store.clear()
            urlText = ""
            senderKey = ""
            headerName = WebhookCredentials.defaultHeaderName
            hasStoredKey = false
            status = .idle
        } catch {
            status = .error("Could not clear the Keychain — try again.")
        }
    }

    /// REQ-11: send one real ping through the same `PingSending` the home screen's button uses
    /// -- not a second code path -- and report exactly what the webhook answered, so a wrong
    /// key shows its 401/403 instead of failing silently. A test connection is a diagnostic,
    /// not a logged ping: nothing here writes to the ping history. Leaves `status` alone --
    /// that field belongs to `save()` and `clear()`.
    func testConnection() async {
        guard !isTesting else { return }
        guard let sender else {
            connectionReport = ConnectionReport(
                succeeded: false, headline: "Test connection is unavailable in this build.",
                statusCode: nil, responseBody: nil)
            return
        }

        isTesting = true
        defer { isTesting = false }

        // This screen has no label field, so the literal is what distinguishes a diagnostic
        // ping from a real one at the receiving end.
        let attempt = await sender.send(label: "Test connection")

        let succeeded: Bool
        let headline: String
        switch attempt.disposition {
        case .sent:
            succeeded = true
            headline = "The webhook accepted the test ping."
        case .permanentFailure(let reason), .retryable(let reason):
            // The reason is already a finished sentence naming the status code (DESIGN.md).
            succeeded = false
            headline = reason
        }

        // Status and body pass straight through: an empty body stays an empty string, a
        // missing one stays nil, and a long one arrives whole -- REQ-11 shows what came back.
        connectionReport = ConnectionReport(
            succeeded: succeeded, headline: headline, statusCode: attempt.statusCode,
            responseBody: attempt.responseBody)
    }

    /// `nil` unless `text` trims to a parseable URL with an `https` scheme and a non-empty
    /// host -- an `http://` address or a bare string like "not a url" both fail here.
    private static func normalizedHTTPSURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme?.lowercased() == "https",
            let host = url.host, !host.isEmpty
        else {
            return nil
        }
        return url
    }
}
