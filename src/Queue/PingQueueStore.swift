import Foundation

/// The durability mechanism (REQ-05, SC-02): a `Codable` array of `QueuedPing` persisted to a
/// single file under Application Support. `FilePingQueueStore` (below) is the ONE sanctioned
/// coordinate store ARCHITECTURE.md names (D-12, 2026-09-10) -- the single named exception to
/// the Forbidden entry that otherwise bans storing or logging raw coordinates -- and it is
/// sanctioned only under four narrow conditions, quoted here so nothing that reads this file
/// mistakes it for general-purpose storage:
///
/// > written with `.completeFileProtectionUntilFirstUserAuthentication`, excluded from backups
/// > (`isExcludedFromBackup`), each entry deleted the moment it is delivered, and never copied
/// > anywhere else.
///
/// The protection class was `.completeFileProtectionUnlessOpen` until D-21 (2026-09-12). That
/// class refuses to open an existing file while the device is locked, and a locked device is
/// precisely when an automatic trigger fires (REQ-06/07/08): every send that failed in a pocket
/// could not be queued, so it was dropped as a permanent failure, and every background drain
/// found the queue unopenable and gave up. Phase 03's fix (`PingQueueError.unavailable`) only
/// stopped a locked read from DESTROYING the queue; it never made the queue usable while locked.
/// `.completeFileProtectionUntilFirstUserAuthentication` -- the same class D-16 chose for
/// `LastPingStore.swift`, for the same reason -- keeps the file openable from the first unlock
/// after boot until the next restart. The trade, stated rather than hidden: queued coordinates
/// are decryptable at rest whenever the phone has been unlocked once since boot.
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

    /// The queue file exists and is almost certainly intact, but the bytes could not be read
    /// right now. Under `.completeFileProtectionUntilFirstUserAuthentication` (D-21) the one
    /// expected cause is a background wake after a restart, BEFORE the user has unlocked the
    /// device for the first time: the file is still sealed until that first unlock. NOTHING is
    /// moved aside and nothing is lost — the caller must treat this as "not now", drain nothing,
    /// report nothing, and try again after the next unlock.
    ///
    /// Separating this from `.unreadable` is not a nicety. While both shared one `catch`, a
    /// background wake on a locked phone (then under `.completeFileProtectionUnlessOpen`, which
    /// sealed the file on EVERY lock) renamed the entire pending queue to
    /// `PingQueue-unreadable.json` and told the user their pings "cannot be delivered" — SC-02's
    /// one promise, broken by the durability mechanism itself, on the most ordinary path there is.
    case unavailable

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

    /// Applies a targeted change in ONE store turn: drops every entry whose id is in `removing`,
    /// and replaces in place every entry whose id matches one in `updating`. Anything the caller
    /// never saw is left exactly as it is.
    ///
    /// The queue deliberately has NO wholesale "replace everything" operation. There used to be
    /// one, and the drain used it: it loaded a
    /// snapshot, awaited the network for up to 30s per entry, then wrote back a value derived
    /// entirely from that stale snapshot -- so a ping the user queued DURING the drain was
    /// overwritten and silently lost, while its row still read Queued. That is SC-02's one
    /// forbidden outcome, a silent drop wearing a success label. Merging against what is actually
    /// on disk, inside the store's own turn, is what makes the drain's write safe, and removing
    /// the wholesale operation is what stops the next caller reopening the hole.
    func apply(removing: Set<UUID>, updating: [QueuedPing]) async throws
}

/// The one sanctioned coordinate store (D-12) -- an `actor` so two drain triggers (foreground
/// connectivity edge, background refresh, manual launch) can never interleave a
/// read-modify-write and race each other's view of the file.
///
/// Every write goes through `write(_:)`, which applies BOTH `Self.writeOptions`' protection class
/// and `isExcludedFromBackup` every single time -- an atomic replace recreates the file, and a
/// recreated file does not inherit the previous file's resource values, so re-asserting both on
/// every write is the only way either protection reliably survives past the first write.
actor FilePingQueueStore: PingQueueStoring {
    /// The queue never grows past this many pending entries. Reaching it is `.full`, an honest
    /// refusal -- never a silent eviction of the oldest ping, which is exactly the silent drop
    /// ARCHITECTURE.md forbids.
    static let capacity = 200

    private static let fileName = "PingQueue.json"
    private static let unreadableFileName = "PingQueue-unreadable.json"

    private let directory: URL

    private var fileURL: URL {
        directory.appendingPathComponent(Self.fileName)
    }

    private var unreadableFileURL: URL {
        directory.appendingPathComponent(Self.unreadableFileName)
    }

    /// The injectable directory is what makes every case here -- fresh store, full queue,
    /// corrupt file -- testable against a throwaway directory, never against the app's real
    /// queue.
    init(directory: URL) {
        self.directory = directory
    }

    /// The app's real queue location: Application Support, created if it does not exist yet.
    static func applicationSupport() throws -> FilePingQueueStore {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return FilePingQueueStore(directory: directory)
    }

    func load() async throws -> [QueuedPing] {
        try readFromDisk()
    }

    /// The read, synchronous on purpose. `append` and `apply` are read-modify-writes, and an
    /// `await` in the middle of one is a suspension point an actor is free to interleave at --
    /// exactly the hole that lost a mid-drain ping. With no `await` between the read and the
    /// write, each is atomic on the actor's own turn.
    private func readFromDisk() throws -> [QueuedPing] {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return []
        }
        // The read and the decode are deliberately separate `do` blocks. They used to share one
        // `catch`, which meant ANY failure to open the file was treated as corruption and moved
        // the whole queue aside. A data-protected file cannot be opened while it is sealed
        // (until the first unlock after boot, under this file's class -- see `writeOptions`),
        // and a background wake can land there. `fileExists` still succeeds (the directory entry
        // is readable; only the content is encrypted), so the guard above passes and the read is
        // what throws.
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            // Not corruption. Nothing is moved, nothing is lost, and the caller tries again after
            // the next unlock.
            throw PingQueueError.unavailable
        }

        do {
            return try JSONDecoder().decode([QueuedPing].self, from: data)
        } catch {
            // The bytes really did come back and really are not a queue -- set the file aside
            // rather than delete it and report an honest failure. The next write starts a clean
            // file, so this reports the failure exactly once rather than on every load.
            try setAsideUnreadableFile()
            throw PingQueueError.unreadable
        }
    }

    func append(_ ping: QueuedPing) async throws {
        var pings = try readFromDisk()
        guard pings.count < Self.capacity else {
            throw PingQueueError.full
        }
        pings.append(ping)
        try write(pings)
    }

    func apply(removing: Set<UUID>, updating: [QueuedPing]) async throws {
        let current = try readFromDisk()
        let replacements = Dictionary(updating.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        let merged = current.compactMap { entry -> QueuedPing? in
            if removing.contains(entry.id) { return nil }
            return replacements[entry.id] ?? entry
        }
        try write(merged)
    }

    /// Moves the unreadable file aside under a fixed name, replacing any previous set-aside
    /// file rather than accumulating them -- one generation of "could not be read" evidence is
    /// enough, and this is never deleted outright: the entries in it were never delivered.
    private func setAsideUnreadableFile() throws {
        if FileManager.default.fileExists(atPath: unreadableFileURL.path) {
            try FileManager.default.removeItem(at: unreadableFileURL)
        }
        try FileManager.default.moveItem(at: fileURL, to: unreadableFileURL)
    }

    /// Pinned as a named seam, not an inline literal at the call site, so a test can assert
    /// against the SAME symbol `write` actually uses (`PingQueueStoreTests
    /// .theQueueFileCarriesTheStatedProtectionClass`), exactly as `FileLastPingStore.writeOptions`
    /// is pinned. `.completeFileProtectionUntilFirstUserAuthentication` is D-21's class -- see
    /// this file's header for the trade it makes and why `.completeFileProtectionUnlessOpen` was
    /// wrong for a queue that has to accept writes from a locked pocket.
    static let writeOptions: Data.WritingOptions = [
        .atomic, .completeFileProtectionUntilFirstUserAuthentication,
    ]

    /// The only place this file is ever written. Both protections are reasserted on every call:
    /// `Self.writeOptions`' protection class so the coordinates in it are encrypted at rest from
    /// boot until the first unlock, and `isExcludedFromBackup` so they never leave the device in
    /// an iCloud or iTunes backup. Neither is optional and neither is applied only once.
    private func write(_ pings: [QueuedPing]) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let data = try JSONEncoder().encode(pings)
        try data.write(to: fileURL, options: Self.writeOptions)

        var excludedURL = fileURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try excludedURL.setResourceValues(resourceValues)
    }
}
