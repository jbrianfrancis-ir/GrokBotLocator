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

    var urlText: String = ""
    var senderKey: String = ""
    var headerName: String = WebhookCredentials.defaultHeaderName
    /// D-10: the only trace a saved key leaves in this model. `load()` never assigns the
    /// stored key to `senderKey` -- 01-12 renders its saved indicator from this instead.
    private(set) var hasStoredKey = false
    var status: Status = .idle

    private let store: CredentialStore

    /// Depends on the `CredentialStore` protocol only -- never constructs a
    /// `KeychainCredentialStore` itself -- so tests inject a fake and the real Keychain is
    /// never touched outside the app.
    init(store: CredentialStore) {
        self.store = store
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
