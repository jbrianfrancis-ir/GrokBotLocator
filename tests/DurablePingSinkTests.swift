import Foundation
import Testing
@testable import GrokBotLocator

/// Proves `DurablePingSink` writes before it promises: the queued entry is on disk (in the
/// fake) before `.queued(id:)` comes back, the entry starts at one attempt made with a backoff
/// already applied, and every store refusal -- full, unreadable, or any other throw -- comes
/// back as a safe `.notQueued` sentence with nothing appended to the store. No real disk;
/// `PingQueueStoreTests` proves `FilePingQueueStore` itself. Synthetic payload only.
@Suite
struct DurablePingSinkTests {

    /// `PendingPingSink.enqueue` is a nonisolated `async` requirement, so this fake's `append`
    /// runs off a `@MainActor` suite -- lock-guarded per `.planning/LEARNINGS.md`'s note on the
    /// phase-02 fake that hung the suite when it wasn't.
    private final class FakeQueueStore: PingQueueStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [QueuedPing] = []
        var errorToThrow: Error?

        var storedEntries: [QueuedPing] {
            lock.withLock { entries }
        }

        func load() async throws -> [QueuedPing] {
            lock.withLock { entries }
        }

        func append(_ ping: QueuedPing) async throws {
            if let errorToThrow {
                throw errorToThrow
            }
            lock.withLock { entries.append(ping) }
        }


        func apply(removing: Set<UUID>, updating: [QueuedPing]) async throws {
            lock.withLock {
                let replacements = Dictionary(updating.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
                entries = entries.compactMap { entry in
                    if removing.contains(entry.id) { return nil }
                    return replacements[entry.id] ?? entry
                }
            }
        }
    }

    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private static let payload = PingPayload(
        latitude: 40.77465,
        longitude: 17.23107,
        accuracyMetres: 5.0,
        label: "Test ping",
        capturedAt: fixedNow
    )

    private static func makeSink(store: FakeQueueStore) -> DurablePingSink {
        DurablePingSink(store: store, policy: .standard, now: { fixedNow })
    }

    @Test
    func aQueuedPingIsOnDiskBeforeTheIdIsReturned() async throws {
        let store = FakeQueueStore()
        let sink = Self.makeSink(store: store)

        let outcome = await sink.enqueue(Self.payload, reason: "connection lost")

        guard case .queued(let id) = outcome else {
            Issue.record("expected .queued, got \(outcome)")
            return
        }
        let entries = store.storedEntries
        #expect(entries.count == 1)
        #expect(entries.first?.id == id)
        #expect(entries.first?.payload == Self.payload)
        #expect(entries.first?.payload.capturedAt == Self.payload.capturedAt)
    }

    @Test
    func theEntryStartsAtOneAttemptWithABackoffAlreadyApplied() async throws {
        let store = FakeQueueStore()
        let sink = Self.makeSink(store: store)

        _ = await sink.enqueue(Self.payload, reason: "connection lost")

        let entry = try #require(store.storedEntries.first)
        #expect(entry.attemptsMade == 1)
        #expect(entry.firstAttemptAt == Self.fixedNow)
        #expect(
            entry.nextAttemptAt
                == PingRetryPolicy.standard.nextAttemptDate(afterAttempts: 1, now: Self.fixedNow))
    }

    @Test(arguments: [PingQueueError.full, PingQueueError.unreadable, PingQueueError.unavailable])
    func aStoreRefusalBecomesANotQueuedSentence(_ error: PingQueueError) async throws {
        let store = FakeQueueStore()
        store.errorToThrow = error
        let sink = Self.makeSink(store: store)

        let outcome = await sink.enqueue(Self.payload, reason: "connection lost")

        guard case .notQueued(let reason) = outcome else {
            Issue.record("expected .notQueued, got \(outcome)")
            return
        }
        #expect(reason.hasSuffix("."))
        #expect(reason.count > 40)
        #expect(!reason.contains("https"))
        #expect(!reason.contains("Error"))
        #expect(!reason.contains("test-sender-key"))
    }

    /// D-21: `.unavailable` now means the queue file is still sealed between a restart and the
    /// first unlock, and the only ping that can arrive then is an AUTOMATIC one — nobody tapped.
    /// The sentence used to read "Unlock the device and tap I'm here again", a manual-tap remedy
    /// shown on a row for a ping the user never initiated. Pinned by name (D-18's rule) and by
    /// content: it must not ask for a tap, and it must still say what happened and what changes it.
    @Test
    func aSealedQueueSentenceDoesNotAskForATap() async throws {
        let store = FakeQueueStore()
        store.errorToThrow = PingQueueError.unavailable
        let sink = Self.makeSink(store: store)

        let outcome = await sink.enqueue(Self.payload, reason: "connection lost")

        #expect(outcome == .notQueued(reason: DurablePingSink.sealedQueueReason))
        let lowered = DurablePingSink.sealedQueueReason.lowercased()
        #expect(!lowered.contains("tap"))
        #expect(!lowered.contains("i'm here"))
        #expect(lowered.contains("unlock"))
        #expect(!lowered.contains("locked."), "the old 'while the device is locked' framing is gone")
        #expect(store.appended.isEmpty)
    }

    @Test
    func anUnexpectedWriteFailureAlsoRefusesSafely() async throws {
        let store = FakeQueueStore()
        store.errorToThrow = CocoaError(.fileWriteOutOfSpace)
        let sink = Self.makeSink(store: store)

        let outcome = await sink.enqueue(Self.payload, reason: "connection lost")

        guard case .notQueued(let reason) = outcome else {
            Issue.record("expected .notQueued, got \(outcome)")
            return
        }
        #expect(!reason.contains("CocoaError"))
        #expect(!reason.contains("NSError"))
    }

    @Test
    func nothingIsQueuedWhenTheAppendThrows() async throws {
        let store = FakeQueueStore()
        store.errorToThrow = PingQueueError.full
        let sink = Self.makeSink(store: store)

        _ = await sink.enqueue(Self.payload, reason: "connection lost")

        #expect(store.storedEntries.isEmpty)
    }
}
