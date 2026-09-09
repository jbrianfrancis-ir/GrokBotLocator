import Foundation

/// Read/write access to the stored webhook credential, injectable so callers -- and tests --
/// never depend on a concrete Keychain implementation.
protocol CredentialStore: Sendable {
    /// `nil` when nothing usable is stored. Never synthesizes a default url or key.
    func load() throws -> WebhookCredentials?
    /// Overwrites whatever is currently stored; never duplicates an existing item.
    func save(_ credentials: WebhookCredentials) throws
    /// Removes everything this store owns. Idempotent -- clearing an already-empty store
    /// is not an error.
    func clear() throws
}

/// A failing Keychain operation. Carries the operation name and the raw `OSStatus` --
/// never a credential value -- so a caught error is diagnosable without ever printing
/// what was being stored.
struct CredentialStoreError: Error, Equatable {
    let operation: String
    let status: OSStatus
}
