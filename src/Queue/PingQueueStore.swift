import Foundation

/// The durability mechanism (REQ-05, SC-02): a `Codable` array of `QueuedPing` persisted to a
/// single file under Application Support. `FilePingQueueStore` (below) is the ONE sanctioned
/// coordinate store ARCHITECTURE.md names (D-12, 2026-09-10) -- the single named exception to
/// the Forbidden entry that otherwise bans storing or logging raw coordinates -- and it is
/// sanctioned only under four narrow conditions, quoted here so nothing that reads this file
/// mistakes it for general-purpose storage:
///
/// > written with `.completeFileProtectionUnlessOpen`, excluded from backups
/// > (`isExcludedFromBackup`), each entry deleted the moment it is delivered, and never copied
/// > anywhere else.
///
/// A queue that keeps delivered pings is a location history, which is not what this is for.
/// Nothing outside `FilePingQueueStore` may write a `QueuedPing` to disk, and no entry read from
/// here may be copied into a log, `UserDefaults`, analytics, or the in-memory `PingHistoryLog`.
struct QueuedPing: Codable, Sendable, Equatable, Identifiable {
    /// The identity `PingAttempt.queuedID` carries away from the sink, and the identity a later
    /// drain (03-09) reports delivery or failure against -- the one thing that ties a queue
    /// entry back to the attempt that created it.
    let id: UUID

    /// The wire payload, unsent. Its `Codable` conformance (synthesized, keyed `lat`/`lng`/
    /// `accuracy_m`/`label`/`at`) is what this file persists -- `encoded()` is the wire format
    /// for the POST body and is never called here.
    let payload: PingPayload

    /// When the FIRST attempt at this ping was made. What `PingRetryPolicy.hasGivenUp` measures
    /// from -- the give-up horizon is time-based from this moment, not from how many attempts
    /// have actually run, so a phone offline for days doesn't give up early just because it had
    /// no chance to retry.
    let firstAttemptAt: Date

    /// How many attempts have been made so far, including failed ones. Feeds
    /// `PingRetryPolicy.delay(afterAttempts:)` for the next backoff interval.
    var attemptsMade: Int

    /// When the next attempt is due. Set by `PingRetryPolicy.nextAttemptDate` after each
    /// failed attempt; a drain (03-09) skips any entry whose `nextAttemptAt` is still in the
    /// future.
    var nextAttemptAt: Date

    /// Nil while the ping is still pending retry. Once retrying has stopped for good --
    /// `PingRetryPolicy.hasGivenUp` returned true, or the classifier called the failure
    /// permanent -- this holds the finished, user-visible sentence explaining why, and the
    /// entry stays on disk carrying it until the app has SHOWN that sentence to the user, at
    /// which point it is removed. (This plan's backstop truth: nothing in REQUIREMENTS.md says
    /// whether a permanent failure that happens while the app is not running must survive to be
    /// shown, or may be dropped once recorded nowhere the user will look -- this type assumes
    /// it must survive, which is why `permanentFailure` exists on the persisted entry at all
    /// rather than being reported and discarded at the moment of failure.)
    var permanentFailure: String?
}

/// What can go wrong reading or writing the queue file, each with the user-facing consequence
/// it forces -- not just the on-disk condition that caused it.
enum PingQueueError: Error, Equatable {
    /// The queue file exists but could not be decoded (corrupt bytes, an incompatible past
    /// format). The unreadable file has already been moved aside by the time this is thrown, so
    /// nothing on disk is lost, but every entry that was pending in it is gone from the queue
    /// the app will actually drain -- the caller must tell the user their queued pings could not
    /// be recovered, and the next write starts a clean file.
    case unreadable

    /// The queue already holds `FilePingQueueStore.capacity` entries. The new ping was NOT
    /// queued and nothing already queued was evicted to make room -- the caller must turn this
    /// into a user-visible failure for the ping that was just attempted, the same way any other
    /// send failure is reported.
    case full
}

/// The seam between the rest of the app and the queue file. Three operations only: `load` reads
/// the whole queue, the caller decides what changes, and `replace` writes the whole queue back --
/// there is no partial-update operation (no "mark id X delivered") to get out of step with what
/// is actually on disk. `DurablePingSink` (03-08) is the only caller of `append`;
/// `PingQueueDrain` (03-09) is the only caller of `load` and `replace`. Nothing else in the app
/// touches a `QueuedPing`.
protocol PingQueueStoring: Sendable {
    /// The full queue, oldest first. An empty array if no queue file exists yet -- that is not
    /// an error, it is the state of a fresh install or a drain that just emptied the queue.
    func load() async throws -> [QueuedPing]

    /// Adds one pending ping to the queue, refusing rather than evicting if the queue is full.
    func append(_ ping: QueuedPing) async throws

    /// Replaces the entire on-disk queue with `pings`. The drain's only write: after deciding
    /// which entries were delivered, gave up, or are still pending, it writes back exactly the
    /// survivors.
    func replace(with pings: [QueuedPing]) async throws
}
