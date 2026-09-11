import Foundation

/// One attempt's full outcome: what fix (if any) was used, what the send resolved to, and the
/// raw HTTP status/body when a response actually came back. REQ-11 reads both the status code
/// and the body from here, so neither is collapsed into `disposition`'s reason string.
struct PingAttempt: Sendable, Equatable {
    let fix: LocationFix?
    let disposition: PingDisposition
    let statusCode: Int?
    let responseBody: String?
    /// The queue entry's own identity, non-nil if and only if this payload is now held by the
    /// sink under this id. Minted by the sink -- it is what writes the entry -- and carried back
    /// here so a later drain (03-09) can say which ping was delivered, and so `PingModel` (03-07)
    /// can stamp a history row with the same id as the queue entry it came from. Defaulted so
    /// every existing call site (previews, tests) keeps compiling untouched.
    let queuedID: UUID?

    init(
        fix: LocationFix?, disposition: PingDisposition, statusCode: Int?, responseBody: String?,
        queuedID: UUID? = nil
    ) {
        self.fix = fix
        self.disposition = disposition
        self.statusCode = statusCode
        self.responseBody = responseBody
        self.queuedID = queuedID
    }
}

/// Phase 03's seam (REQ-05): the durable on-disk queue conforms to this protocol and replaces
/// `UnqueuedPingSink` wholesale. Until that lands, a retryable disposition is recorded as a
/// `.failed` outcome with a user-visible reason -- never silently dropped (ARCHITECTURE.md) --
/// but nothing in this phase drains a queue, so nothing here promises one.
///
/// What the sink did with a payload. A returned value rather than `throws`, for three reasons.
/// ARCHITECTURE.md requires a USER-VISIBLE reason, and only the sink knows a sentence that is
/// both specific and safe to show ("there is not enough storage left…"); a thrown `Error` would
/// be turned into copy by `PingSender`, which knows nothing about storage, and this codebase has
/// already established that interpolating a caught error into user-facing text is unsafe because
/// it can carry the webhook URL (see `URLSessionPingTransport`). Nothing else in this pipeline
/// throws: `PingSender.send` returns a `PingAttempt` for every branch including four failures, so
/// a throwing edge here would be the only one inside a function whose shape is "every outcome is
/// a value". And it matches `PingDisposition`, which is already this pattern -- a closed set of
/// outcomes, each failure carrying a finished sentence.
enum PingEnqueueOutcome: Sendable, Equatable {
    /// `id` is the queue entry's own identity, minted by the sink because the sink is what
    /// writes the entry -- and it is what lets a later drain say which ping was delivered.
    case queued(id: UUID)
    case notQueued(reason: String)
}

/// Phase 03's seam (REQ-05): the durable on-disk queue conforms to this protocol and replaces
/// `UnqueuedPingSink` wholesale. A conformer that writes a file can fail -- disk full, data
/// protection unavailable at a background wake, an encode error, a corrupt existing queue -- and
/// the return value is how `PingSender` learns that. Without it, `PingModel` would flip this arm
/// to a durable-looking "Queued" and reassure the user about a ping held nowhere, which is what
/// ARCHITECTURE.md's "no ping is silently dropped" forbids and is worse than an honest failure,
/// because it stops them worrying.
protocol PendingPingSink: Sendable {
    func enqueue(_ payload: PingPayload, reason: String) async -> PingEnqueueOutcome
}

/// The implementation phase 02 ships. Nothing durable exists yet, so nothing is EVER queued --
/// and saying so in the return type is what makes that a type-enforced invariant rather than a
/// promise kept by a comment. Echoes the classifier's own sentence back rather than inventing
/// copy about the build. Phase 03 swaps in the durable queue that conforms to the same protocol.
struct UnqueuedPingSink: PendingPingSink {
    func enqueue(_ payload: PingPayload, reason: String) async -> PingEnqueueOutcome {
        .notQueued(reason: reason)
    }
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
        // `var` because a failing enqueue below downgrades a retryable disposition to permanent.
        var disposition: PingDisposition
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

        // Non-nil only when the retryable arm below gets a `.queued(id:)` back -- every other
        // path (delivered, or permanently rejected) is held by nothing.
        var queuedID: UUID?
        if case .retryable(let reason) = disposition {
            switch await pending.enqueue(payload, reason: reason) {
            case .queued(let id):
                queuedID = id  // disposition stays .retryable -- it really is pending somewhere
            case .notQueued(let why):
                // Nothing holds this ping, so it is final for the user: gone, here is why, tap
                // again. `.permanentFailure` already means and renders exactly that, and the
                // sink supplied the sentence because only it knows what is safe to show.
                disposition = .permanentFailure(reason: why)
            }
        }

        return PingAttempt(
            fix: fix, disposition: disposition, statusCode: statusCode, responseBody: responseBody,
            queuedID: queuedID)
    }
}
