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
