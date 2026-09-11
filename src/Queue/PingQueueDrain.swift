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
/// drain triggers (a connectivity edge and a foreground launch, say) are serialized on entry.
///
/// Actor isolation alone turned out NOT to be enough, twice, and both holes were the same shape:
/// an actor is reentrant across `await`, and this type awaits the network in the middle of a
/// read-modify-write. `isDraining` closes drain-vs-drain (it delivered one ping twice); applying a
/// DELTA through `store.apply(removing:updating:)` instead of writing back a snapshot closes
/// drain-vs-enqueue (it erased a ping the user queued mid-drain, while the row read Queued).
/// Neither was caught by a test until PR review, because every test drove one caller at a time
/// against a transport that never suspends.
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

    /// True from the moment a drain starts until it returns.
    ///
    /// An `actor` serializes ENTRY, not a whole call: it is reentrant across every `await`, and
    /// `drain()` awaits the network in the middle of a load-send-replace sequence. Without this
    /// flag a second drain entered while the first was parked on `transport.send`, loaded the
    /// same not-yet-replaced queue, and delivered the same ping again. That is not theoretical --
    /// it happened on a simulator during phase 03 acceptance (2026-09-11): one queued ping, two
    /// POSTs at the receiver carrying the same `at` in the same second. Both drains fire on
    /// launch, `.task { start() }` and `scenePhase` -> `.active`.
    private var isDraining = false

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
        // Reads and writes of `isDraining` both sit on the actor's own turn with no `await`
        // between them, so this guard is atomic even though the body below suspends repeatedly.
        // A refused drain reports NOTHING rather than an empty-but-successful result: the drain
        // already running owns this queue and will report whatever it delivers.
        guard !isDraining else { return PingDrainReport(updates: [], notice: nil) }
        isDraining = true
        defer { isDraining = false }

        let queue: [QueuedPing]
        do {
            queue = try await store.load()
        } catch PingQueueError.unavailable {
            // The device is locked, so the queue file cannot be opened yet. Nothing is wrong and
            // nothing is lost -- say NOTHING to the user, because there is nothing for them to do
            // and the next unlocked drain picks the queue up untouched. Reporting a notice here
            // would tell someone their pings failed because their phone was in their pocket.
            return PingDrainReport(updates: [], notice: nil)
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

        // A DELTA, not a rewrite. `queue` is a snapshot taken before the first `await`, and the
        // drain parks on the network for up to 30s per entry -- long enough for the user to tap
        // "I'm here" and have `DurablePingSink` append to the same store. Writing back anything
        // derived from the snapshot erased that ping while its row read Queued.
        var removed: Set<UUID> = []
        var changed: [QueuedPing] = []
        var updates: [PingDeliveryUpdate] = []
        var index = queue.startIndex

        while index < queue.endIndex {
            // An expired `BGAppRefreshTask` cancels the task, `URLSession.bytes` throws, and
            // `PingClassifier` maps every thrown error to `.retryable` -- so without this check the
            // loop walked the REST of the queue bumping `attemptsMade` and pushing `nextAttemptAt`
            // a rung further out, for entries it never actually attempted, while the 7-day give-up
            // clock kept running. Stopping leaves every remaining entry exactly as it was.
            if Task.isCancelled { break }

            if now() >= deadline {
                // The drain stops at its deadline with every remaining entry, including this one,
                // still queued exactly as it is. They are simply absent from the delta, so nothing
                // touches them.
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
                changed.append(entry)
            } else {
                removed.insert(entry.id)
            }
            // Applied after EVERY entry, not once at the end, so a process killed mid-drain cannot
            // re-send a ping it already delivered. The delta is cumulative and therefore
            // idempotent: re-applying a removal or an update is a no-op.
            try? await store.apply(removing: removed, updating: changed)
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
