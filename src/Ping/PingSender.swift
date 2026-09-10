import Foundation

/// One attempt's full outcome: what fix (if any) was used, what the send resolved to, and the
/// raw HTTP status/body when a response actually came back. REQ-11 reads both the status code
/// and the body from here, so neither is collapsed into `disposition`'s reason string.
struct PingAttempt: Sendable, Equatable {
    let fix: LocationFix?
    let disposition: PingDisposition
    let statusCode: Int?
    let responseBody: String?
}

/// Phase 03's seam (REQ-05): the durable on-disk queue conforms to this protocol and replaces
/// `UnqueuedPingSink` wholesale. Until that lands, a retryable disposition is recorded as a
/// `.failed` outcome with a user-visible reason -- never silently dropped (ARCHITECTURE.md) --
/// but nothing in this phase drains a queue, so nothing here promises one.
protocol PendingPingSink: Sendable {
    func enqueue(_ payload: PingPayload, reason: String) async
}

/// The no-op implementation phase 02 ships. `enqueue` intentionally does nothing -- phase 03
/// swaps in the durable queue that conforms to the same protocol.
struct UnqueuedPingSink: PendingPingSink {
    func enqueue(_ payload: PingPayload, reason: String) async {}
}

/// What a caller above this needs to send a manual ping: one label in, one attempt out. A
/// protocol so the view layer (and tests) never depend on the concrete sender.
protocol PingSending: Sendable {
    func send(label: String) async -> PingAttempt
}

/// The whole manual ping, end to end, with no view and no device: load credentials, take one
/// fix, encode, POST, classify, and hand a retryable disposition to the queue seam. Depends on
/// `CredentialStore`, `LocationFixProvider`, `PingTransport` and `PendingPingSink` as protocols
/// only (ARCHITECTURE.md -- transport and storage are protocol-backed and injected), so every
/// branch below is testable with four fakes and no network or disk of its own.
struct PingSender: PingSending {
    private let credentials: CredentialStore
    private let fixes: LocationFixProvider
    private let transport: PingTransport
    private let pending: PendingPingSink

    init(
        credentials: CredentialStore, fixes: LocationFixProvider, transport: PingTransport,
        pending: PendingPingSink
    ) {
        self.credentials = credentials
        self.fixes = fixes
        self.transport = transport
        self.pending = pending
    }

    func send(label: String) async -> PingAttempt {
        let loadedCredentials: WebhookCredentials
        do {
            guard let stored = try credentials.load() else {
                return PingAttempt(
                    fix: nil,
                    disposition: .permanentFailure(
                        reason: "Add your webhook URL and sender key in Settings before pinging."),
                    statusCode: nil, responseBody: nil)
            }
            loadedCredentials = stored
        } catch {
            return PingAttempt(
                fix: nil,
                disposition: .permanentFailure(
                    reason: "Add your webhook URL and sender key in Settings before pinging."),
                statusCode: nil, responseBody: nil)
        }

        let fix: LocationFix
        do {
            fix = try await fixes.currentFix()
        } catch let error as LocationFixError {
            return PingAttempt(
                fix: nil, disposition: .permanentFailure(reason: error.reason), statusCode: nil,
                responseBody: nil)
        } catch {
            return PingAttempt(
                fix: nil,
                disposition: .permanentFailure(
                    reason: "Could not get a location fix. Try again in a moment."),
                statusCode: nil, responseBody: nil)
        }

        let payload = fix.payload(label: label)
        let disposition: PingDisposition
        let statusCode: Int?
        let responseBody: String?
        do {
            let response = try await transport.send(payload, using: loadedCredentials)
            disposition = PingClassifier.disposition(for: response)
            statusCode = response.statusCode
            responseBody = response.body
        } catch {
            disposition = PingClassifier.disposition(forTransportError: error)
            statusCode = nil
            responseBody = nil
        }

        if case .retryable(let reason) = disposition {
            await pending.enqueue(payload, reason: reason)
        }

        return PingAttempt(
            fix: fix, disposition: disposition, statusCode: statusCode, responseBody: responseBody)
    }
}
