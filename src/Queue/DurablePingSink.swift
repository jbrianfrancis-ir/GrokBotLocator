import Foundation

/// The durable `PendingPingSink` (REQ-05): the sink writes before it promises. `enqueue` returns
/// `.queued(id:)` only after `store.append` has actually returned -- never before -- so a caller
/// told "queued" is told that because the disk already holds the entry, not because the write is
/// merely underway. A refusal (full queue, unreadable file, or any other write failure) comes
/// back as `.notQueued` carrying a finished sentence (DESIGN.md: what happened and what to do
/// next), which `PingSender` downgrades to an honest `.permanentFailure` -- SC-02 forbids silent
/// loss, and a sink that said "queued" about a ping it did not persist would be exactly that,
/// wearing a success label. Replaces `UnqueuedPingSink` at the composition root in 03-10; same
/// protocol, no change to `PingSender`.
struct DurablePingSink: PendingPingSink {
    /// The sentence for a ping that arrived while the queue file was still sealed after a
    /// restart. Public so a test can pin it by name (D-18's rule: a stated sentence with no test
    /// drifts). Deliberately free of "tap": the only path that reaches it is an automatic trigger.
    static let sealedQueueReason =
        "Not kept: the device has not been unlocked since it restarted, so the offline queue "
        + "could not be opened. Unlock the device once and automatic pings will be saved again."

    let store: any PingQueueStoring
    let policy: PingRetryPolicy
    /// Injected rather than read from `Date()` directly, so the entry's timestamps are testable
    /// and this type reads no clock of its own.
    let now: @Sendable () -> Date

    func enqueue(_ payload: PingPayload, reason: String) async -> PingEnqueueOutcome {
        let id = UUID()
        let stamp = now()
        // `attemptsMade: 1` because the live attempt that just failed IS the first attempt --
        // starting at 0 would schedule the next attempt immediately, re-failing on the same
        // dead connection instead of waiting out the first backoff.
        let entry = QueuedPing(
            id: id,
            payload: payload,
            firstAttemptAt: stamp,
            attemptsMade: 1,
            nextAttemptAt: policy.nextAttemptDate(afterAttempts: 1, now: stamp),
            permanentFailure: nil
        )

        do {
            try await store.append(entry)
        } catch PingQueueError.full {
            return .notQueued(
                reason: "The offline queue is full (200 pings waiting), so this ping was not "
                    + "saved. Send or clear the waiting pings, then tap I'm here again.")
        } catch PingQueueError.unavailable {
            // The queue is intact but still sealed: under D-21's protection class that happens
            // only between a restart and the first unlock, and the ping reaching here is an
            // AUTOMATIC one (a person cannot tap before unlocking). So the sentence must not say
            // "tap I'm here again" -- nobody tapped -- and must not blame the queue or send the
            // user to fix anything, because nothing is broken. It says what happened and the one
            // thing that changes it: unlocking once.
            return .notQueued(reason: Self.sealedQueueReason)
        } catch PingQueueError.unreadable {
            return .notQueued(
                reason: "The offline queue file could not be read and has been set aside, so "
                    + "this ping was not saved. Tap I'm here again.")
        } catch {
            // NEVER interpolate the caught error, the webhook URL, the sender key, or a
            // coordinate into this sentence -- this codebase has already established that
            // doing so is unsafe (see `PingSender`'s doc comment on `PendingPingSink`).
            return .notQueued(
                reason: "This ping could not be saved to the offline queue, so it was not kept. "
                    + "Check that the device has free storage, then tap I'm here again.")
        }

        // The id is returned only now, after the write above returned -- nothing is ever told
        // "queued" before the disk has it.
        return .queued(id: id)
    }
}
