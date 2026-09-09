import Foundation
import Security

/// The only type in this module -- in the app, in fact -- that calls a `SecItem*` function.
/// Stores each field of `WebhookCredentials` as its own `kSecClassGenericPassword` item
/// under a shared `kSecAttrService`, one `kSecAttrAccount` per field. This file writes
/// nowhere but the Keychain -- no console output, no preferences storage of any kind: a
/// Keychain failure surfaces as a thrown `CredentialStoreError` carrying the `OSStatus`,
/// never a value written anywhere else.
struct KeychainCredentialStore: CredentialStore {
    private enum Account {
        static let url = "webhook.url"
        static let senderKey = "webhook.senderKey"
        static let headerName = "webhook.headerName"
    }

    private let service: String

    /// `service` defaults to the bundle id so the app's three real callers share one
    /// namespace; tests inject a throwaway string so they never touch the app's own items.
    init(service: String = Bundle.main.bundleIdentifier ?? "GrokBotLocator") {
        self.service = service
    }

    func load() throws -> WebhookCredentials? {
        guard let urlString = try readString(account: Account.url),
            let url = URL(string: urlString)
        else {
            return nil
        }
        guard let senderKey = try readString(account: Account.senderKey) else {
            return nil
        }
        // An explicit empty save is treated the same as never having saved one -- both
        // fall back to the default, so a cleared header field never sticks as blank.
        let headerName = try readString(account: Account.headerName).flatMap { $0.isEmpty ? nil : $0 }
            ?? WebhookCredentials.defaultHeaderName
        return WebhookCredentials(url: url, senderKey: senderKey, headerName: headerName)
    }

    func save(_ credentials: WebhookCredentials) throws {
        try writeString(credentials.url.absoluteString, account: Account.url)
        try writeString(credentials.senderKey, account: Account.senderKey)
        try writeString(credentials.headerName, account: Account.headerName)
    }

    func clear() throws {
        try deleteItem(account: Account.url)
        try deleteItem(account: Account.senderKey)
        try deleteItem(account: Account.headerName)
    }

    // MARK: - SecItem plumbing

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    private func readString(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data, let value = String(data: data, encoding: .utf8) else {
                return nil
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw CredentialStoreError(operation: "load", status: status)
        }
    }

    /// Updates the existing item in place; on `errSecItemNotFound` falls back to adding one,
    /// so a re-save overwrites rather than duplicating.
    private func writeString(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(
            query as CFDictionary, [kSecValueData as String: data] as CFDictionary)

        if updateStatus == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw CredentialStoreError(operation: "save", status: addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw CredentialStoreError(operation: "save", status: updateStatus)
        }
    }

    /// `errSecItemNotFound` is success: clearing an already-empty store is not an error.
    private func deleteItem(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        if status != errSecSuccess && status != errSecItemNotFound {
            throw CredentialStoreError(operation: "clear", status: status)
        }
    }
}
