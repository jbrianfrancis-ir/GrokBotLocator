import Foundation

/// What one call to `PingQueueDrain.drain(before:surfacingFailures:)` produced: an update per
/// ping whose on-screen row actually changed, plus an optional `notice` for a condition that
/// stopped the WHOLE drain rather than one ping (no credentials, an unreadable queue file).
/// `notice` is a finished sentence (DESIGN.md) and is `nil` on an ordinary drain, even one that
/// delivered nothing because nothing was due.
struct PingDrainReport: Sendable, Equatable {
    let updates: [PingDeliveryUpdate]
    let notice: String?
}

/// The dequeue half of REQ-05/SC-02: attempt every due entry, delete what is delivered, back off
/// what is not, and report every outcome as a `PingDeliveryUpdate` the history can apply
/// (`PingModel.apply(_:announcing:)`, 03-10). An `actor` -- not a plain struct or class -- so two
/// drain triggers (a connectivity edge and a foreground launch, say) can never interleave a
/// read-modify-write of the queue file; the file itself has no locking of its own, only
/// `FilePingQueueStore`'s single `write(_:)` call site, which this actor's isolation is what
/// makes safe to call from more than one trigger.
///
/// `surfacingFailures` is `PingModel.apply(_:announcing:)`'s reason to exist (03-07): a
/// background wake marks a permanent failure on the entry and reports it, but leaves the entry on
/// disk, because nothing is on screen to show it to; a foreground drain reports it again AND
/// deletes it, because this time someone can actually see the row. Without the distinction, a
/// permanent rejection discovered while the app is not running would either vanish unreported (the
/// silent drop SC-02 forbids) or be deleted before anyone ever saw it.
actor PingQueueDrain {
    private let store: any PingQueueStoring
    private let credentials: any CredentialStore
    private let transport: any PingTransport
    private let policy: PingRetryPolicy
    private let now: @Sendable () -> Date

    init(
        store: any PingQueueStoring,
        credentials: any CredentialStore,
        transport: any PingTransport,
        policy: PingRetryPolicy,
        now: @Sendable @escaping () -> Date
    ) {
        self.store = store
        self.credentials = credentials
        self.transport = transport
        self.policy = policy
        self.now = now
    }

    /// Walks the queue oldest first, sending every entry that is due, and stops at `deadline`
    /// leaving every remaining entry exactly as it was. `surfacingFailures` decides whether an
    /// already-marked or newly-marked permanent failure is deleted after being reported (see the
    /// type doc above).
    func drain(before deadline: Date, surfacingFailures: Bool) async -> PingDrainReport {
        let queue: [QueuedPing]
        do {
            queue = try await store.load()
        } catch PingQueueError.unreadable {
            return PingDrainReport(
                updates: [],
                notice: "Some pings waiting to be sent could not be read and have been set aside. They cannot be delivered."
            )
        } catch {
            return PingDrainReport(
                updates: [],
                notice: "The ping queue could not be read, so nothing waiting could be sent."
            )
        }

        let loadedCredentials: WebhookCredentials?
        do {
            loadedCredentials = try credentials.load()
        } catch {
            loadedCredentials = nil
        }
        guard let credentials = loadedCredentials else {
            // Missing or unreadable credentials drain nothing and delete nothing (D-12 /
            // this plan's backstop truth) -- the queue is never emptied because the app could
            // not read a key. Nothing is written.
            return PingDrainReport(
                updates: [],
                notice: "Add your webhook URL and sender key in Settings — \(queue.count) ping(s) are waiting to be sent."
            )
        }

        var surviving: [QueuedPing] = []
        var updates: [PingDeliveryUpdate] = []
        var index = queue.startIndex

        while index < queue.endIndex {
            if now() >= deadline {
                // The drain stops at its deadline with every remaining entry, including this
                // one, still queued exactly as it is. Nothing further is written -- these
                // entries were never touched.
                surviving.append(contentsOf: queue[index...])
                break
            }

            var entry = queue[index]
            index += 1
            var keep: Bool

            if let reason = entry.permanentFailure {
                // Marked during an earlier, non-surfacing drain: report it again, delete it
                // only now that it is actually being surfaced.
                updates.append(Self.update(for: entry, outcome: .failed, reason: reason))
                keep = !surfacingFailures
            } else if policy.hasGivenUp(firstAttemptAt: entry.firstAttemptAt, now: now()) {
                let reason = PingRetryPolicy.gaveUpReason
                entry.permanentFailure = reason
                updates.append(Self.update(for: entry, outcome: .failed, reason: reason))
                keep = !surfacingFailures
            } else if entry.nextAttemptAt > now() {
                // Not yet due: left completely alone -- not sent, not counted, not removed.
                keep = true
            } else {
                let disposition: PingDisposition
                do {
                    let response = try await transport.send(entry.payload, using: credentials)
                    disposition = PingClassifier.disposition(for: response)
                } catch {
                    disposition = PingClassifier.disposition(forTransportError: error)
                }

                switch disposition {
                case .sent:
                    updates.append(Self.update(for: entry, outcome: .sent, reason: nil))
                    // Delivered: dropped -- the entry is deleted the moment it is delivered (D-12).
                    keep = false
                case .permanentFailure(let reason):
                    entry.permanentFailure = reason
                    updates.append(Self.update(for: entry, outcome: .failed, reason: reason))
                    keep = !surfacingFailures
                case .retryable:
                    // No update emitted -- the row already reads Queued and nothing about it
                    // has changed for the user.
                    entry.attemptsMade += 1
                    entry.nextAttemptAt = policy.nextAttemptDate(afterAttempts: entry.attemptsMade, now: now())
                    keep = true
                }
            }

            if keep {
                surviving.append(entry)
            }
            // Rewritten after EVERY entry, not once at the end, so a process killed mid-drain
            // cannot re-send a ping it already delivered.
            try? await store.replace(with: surviving + queue[index...])
        }

        return PingDrainReport(updates: updates, notice: nil)
    }

    private static func update(
        for entry: QueuedPing,
        outcome: PingOutcome,
        reason: String?
    ) -> PingDeliveryUpdate {
        PingDeliveryUpdate(
            id: entry.id,
            timestamp: entry.payload.capturedAt,
            latitude: entry.payload.latitude,
            longitude: entry.payload.longitude,
            label: entry.payload.label,
            outcome: outcome,
            reason: reason
        )
    }
}
