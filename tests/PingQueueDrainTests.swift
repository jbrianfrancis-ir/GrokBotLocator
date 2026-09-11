import Foundation
import Synchronization
import Testing
@testable import GrokBotLocator

/// Pins every disposition `PingQueueDrain.drain(before:surfacingFailures:)` can produce, against
/// fakes only -- no network, no disk, no real clock. This is SC-02's load-bearing suite: a
/// delivered entry is deleted the instant it is reported (D-12), a permanent failure survives on
/// disk until it is actually surfaced, a retryable failure changes the file but never the report,
/// and neither an unreadable queue nor unreadable credentials ever empties the queue. Synthetic
/// coordinates only.
@Suite
struct PingQueueDrainTests {

    // MARK: Fakes

    /// `PingQueueStoring`'s three methods are nonisolated `async` requirements, so this fake runs
    /// off whatever isolation domain calls it -- lock-guarded per `.planning/LEARNINGS.md`'s note
    /// on the phase-02 fake that hung the suite when it wasn't. Records every `replace(with:)`
    /// call, in order, so `theFileIsRewrittenAfterEachEntryNotOnlyAtTheEnd` can see the file
    /// shrink one entry at a time rather than only its final state.
    private final class FakeQueueStore: PingQueueStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [QueuedPing]
        private var replaceCallsStorage: [[QueuedPing]] = []
        var loadErrorToThrow: Error?
        var entriesNow: [QueuedPing] { lock.withLock { entries } }

        init(entries: [QueuedPing] = []) {
            self.entries = entries
        }

        var currentEntries: [QueuedPing] {
            lock.withLock { entries }
        }

        var replaceCalls: [[QueuedPing]] {
            lock.withLock { replaceCallsStorage }
        }

        func load() async throws -> [QueuedPing] {
            if let loadErrorToThrow {
                throw loadErrorToThrow
            }
            return lock.withLock { entries }
        }

        func append(_ ping: QueuedPing) async throws {
            lock.withLock { entries.append(ping) }
        }

        func replace(with pings: [QueuedPing]) async throws {
            lock.withLock {
                entries = pings
                replaceCallsStorage.append(pings)
            }
        }
    }

    /// Replays a caller-set script of responses or errors, one per call, holding past the end of
    /// the script on a plain 200 -- most tests below only ever need one or two calls answered.
    /// Lock-guarded for the same nonisolated-`async` reason as `FakeQueueStore`.
    private final class FakeTransport: PingTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var script: [Result<PingResponse, Error>]
        private var index = 0
        private var callCountStorage = 0

        init(script: [Result<PingResponse, Error>] = []) {
            self.script = script
        }

        var callCount: Int { lock.withLock { callCountStorage } }

        func send(_ payload: PingPayload, using credentials: WebhookCredentials) async throws -> PingResponse {
            let outcome: Result<PingResponse, Error> = lock.withLock {
                callCountStorage += 1
                guard !script.isEmpty else {
                    return .success(PingResponse(statusCode: 200, body: ""))
                }
                let result = script[min(index, script.count - 1)]
                index += 1
                return result
            }
            switch outcome {
            case .success(let response): return response
            case .failure(let error): throw error
            }
        }
    }

    /// A transport that actually suspends, so a second drain can enter the actor while the first
    /// is parked at its `await`. `FakeTransport` returns immediately and never leaves that window
    /// open, which is why the reentrancy bug survived its whole suite.
    private final class SlowTransport: PingTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var callCountStorage = 0
        private let delay: Duration

        init(delay: Duration) { self.delay = delay }

        var callCount: Int { lock.withLock { callCountStorage } }

        func send(_ payload: PingPayload, using credentials: WebhookCredentials) async throws -> PingResponse {
            lock.withLock { callCountStorage += 1 }
            try? await Task.sleep(for: delay)
            return PingResponse(statusCode: 200, body: "")
        }
    }

    /// Returns a caller-set credential, or throws a caller-set error. `load()` is a synchronous
    /// (non-`async`) requirement, so every call lands on the actor's own turn -- no lock needed,
    /// same as `PingSenderTests`'s `FakeCredentialStore`.
    private final class FakeCredentialStore: CredentialStore, @unchecked Sendable {
        var stored: WebhookCredentials?
        var errorToThrow: Error?

        func load() throws -> WebhookCredentials? {
            if let errorToThrow { throw errorToThrow }
            return stored
        }
        func save(_ credentials: WebhookCredentials) throws {}
        func clear() throws {}
    }

    // MARK: Fixtures -- synthetic values only, none resolves anywhere.

    private static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private static let fixtureCredentials = WebhookCredentials(
        url: URL(string: "https://example.invalid/webhook")!,
        senderKey: "dummy-sender-key-drain-test",
        headerName: "X-Test-Key")

    private static func makeQueuedPing(
        id: UUID = UUID(),
        firstAttemptAt: Date = fixedNow,
        attemptsMade: Int = 1,
        nextAttemptAt: Date = fixedNow,
        permanentFailure: String? = nil
    ) -> QueuedPing {
        QueuedPing(
            id: id,
            payload: PingPayload(
                latitude: 40.77465,
                longitude: 17.23107,
                accuracyMetres: 5.0,
                label: "Test ping",
                capturedAt: fixedNow
            ),
            firstAttemptAt: firstAttemptAt,
            attemptsMade: attemptsMade,
            nextAttemptAt: nextAttemptAt,
            permanentFailure: permanentFailure
        )
    }

    private static func makeDrain(
        store: FakeQueueStore,
        credentials: FakeCredentialStore,
        transport: any PingTransport,
        policy: PingRetryPolicy = .standard,
        now: @escaping @Sendable () -> Date = { fixedNow }
    ) -> PingQueueDrain {
        PingQueueDrain(store: store, credentials: credentials, transport: transport, policy: policy, now: now)
    }

    private static let farFutureDeadline = fixedNow.addingTimeInterval(86_400)

    // MARK: Tests

    /// Found on a simulator during phase 03 acceptance, 2026-09-11: ONE queued ping, TWO POSTs at
    /// the receiver with the same `at` in the same second.
    ///
    /// Both drains fire on launch -- `.task { start() }` drains, and `scenePhase` -> `.active`
    /// drains again -- and `PingQueueDrain` is an `actor`, which serializes entry but is REENTRANT
    /// across `await`. Drain A loads the queue and suspends on `transport.send`; drain B enters
    /// during that suspension, loads the same not-yet-replaced queue, and sends the same entry.
    /// `drain()`'s own comment claimed it "cannot re-send a ping it already delivered" -- true of
    /// sequential drains, false of reentrant ones. Every existing test in this suite drives one
    /// drain at a time, which is exactly why none of them caught it.
    ///
    /// Not data loss, so SC-02 still holds; it is duplicate delivery, which spends SC-04's "no
    /// more than 4 pings per minute reach the routine" budget on the same ping twice.
    @Test
    func twoConcurrentDrainsDeliverAQueuedPingExactlyOnce() async throws {
        let entry = Self.makeQueuedPing()
        let store = FakeQueueStore(entries: [entry])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        // Suspends inside `send`, holding drain A at the await long enough for drain B to enter.
        let transport = SlowTransport(delay: .milliseconds(150))
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        async let first = drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)
        async let second = drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)
        let reports = await [first, second]

        #expect(transport.callCount == 1, "the queued ping reached the webhook \(transport.callCount) times")
        // Exactly one drain reports the delivery; the other reports nothing rather than repeating it.
        #expect(reports.map { $0.updates.count }.sorted() == [0, 1])
        #expect(store.entriesNow.isEmpty)
    }

    @Test
    func aDeliveredPingIsRemovedFromTheFileAndReportedSent() async throws {
        let entry = Self.makeQueuedPing()
        let store = FakeQueueStore(entries: [entry])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport(script: [.success(PingResponse(statusCode: 200, body: ""))])
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        let report = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(report.updates.count == 1)
        #expect(report.updates.first?.id == entry.id)
        #expect(report.updates.first?.outcome == .sent)
        #expect(report.updates.first?.reason == nil)
        #expect(report.notice == nil)
        #expect(store.replaceCalls.last?.isEmpty == true)
        #expect(store.currentEntries.isEmpty)
    }

    @Test
    func aPingNotYetDueIsLeftCompletelyAlone() async throws {
        let entry = Self.makeQueuedPing(nextAttemptAt: Self.fixedNow.addingTimeInterval(3_600))
        let store = FakeQueueStore(entries: [entry])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport()
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        let report = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(transport.callCount == 0)
        #expect(report.updates.isEmpty)
        #expect(store.currentEntries == [entry])
    }

    @Test
    func aRetryableFailureBacksOffWithoutReportingOrRemoving() async throws {
        let entry = Self.makeQueuedPing(attemptsMade: 1)
        let store = FakeQueueStore(entries: [entry])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport(script: [.success(PingResponse(statusCode: 503, body: ""))])
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        let report = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(report.updates.isEmpty)
        let survivor = try #require(store.currentEntries.first)
        #expect(store.currentEntries.count == 1)
        #expect(survivor.attemptsMade == 2)
        #expect(
            survivor.nextAttemptAt
                == PingRetryPolicy.standard.nextAttemptDate(afterAttempts: 2, now: Self.fixedNow))
    }

    @Test
    func aPermanentRejectionIsMarkedButKeptWhenNotSurfacing() async throws {
        let entry = Self.makeQueuedPing()
        let store = FakeQueueStore(entries: [entry])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport(script: [.success(PingResponse(statusCode: 401, body: ""))])
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        guard case .permanentFailure(let expectedReason) =
            PingClassifier.disposition(for: PingResponse(statusCode: 401, body: "")) else {
            Issue.record("expected 401 to classify as permanentFailure")
            return
        }

        let firstReport = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: false)

        #expect(firstReport.updates.count == 1)
        #expect(firstReport.updates.first?.outcome == .failed)
        #expect(firstReport.updates.first?.reason == expectedReason)
        #expect(store.currentEntries.count == 1)
        #expect(store.currentEntries.first?.permanentFailure == expectedReason)
        #expect(transport.callCount == 1)

        // Foreground drain of the SAME store: the failure is surfaced (reported again) and only
        // now deleted -- this is the background-wake-then-foreground path SC-02 needs.
        let secondReport = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(secondReport.updates.count == 1)
        #expect(secondReport.updates.first?.outcome == .failed)
        #expect(secondReport.updates.first?.reason == expectedReason)
        #expect(store.currentEntries.isEmpty)
        // Already-marked entries are reported without a second send.
        #expect(transport.callCount == 1)
    }

    @Test
    func givingUpAfterSevenDaysReportsAFailureWithoutSending() async throws {
        let entry = Self.makeQueuedPing(firstAttemptAt: Self.fixedNow.addingTimeInterval(-8 * 86_400))
        let store = FakeQueueStore(entries: [entry])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport()
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        let report = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(transport.callCount == 0)
        #expect(report.updates.count == 1)
        #expect(report.updates.first?.outcome == .failed)
        #expect(report.updates.first?.reason == PingRetryPolicy.gaveUpReason)
    }

    @Test
    func missingCredentialsDrainNothingAndDeleteNothing() async throws {
        let entries = [Self.makeQueuedPing(), Self.makeQueuedPing()]
        let store = FakeQueueStore(entries: entries)
        let credentials = FakeCredentialStore()
        credentials.stored = nil
        let transport = FakeTransport()
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        let report = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(report.updates.isEmpty)
        #expect(report.notice != nil)
        #expect(transport.callCount == 0)
        #expect(store.replaceCalls.isEmpty)
        #expect(store.currentEntries == entries)
    }

    @Test
    func anUnreadableQueueDrainsNothingAndSaysSo() async throws {
        let store = FakeQueueStore()
        store.loadErrorToThrow = PingQueueError.unreadable
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport()
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        let report = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(report.updates.isEmpty)
        #expect(report.notice != nil)
        #expect(transport.callCount == 0)
        #expect(store.replaceCalls.isEmpty)
    }

    @Test
    func theDeadlineStopsTheWalkAndLeavesTheRestQueued() async throws {
        let first = Self.makeQueuedPing()
        let second = Self.makeQueuedPing()
        let third = Self.makeQueuedPing()
        let store = FakeQueueStore(entries: [first, second, third])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport(script: [
            .success(PingResponse(statusCode: 200, body: "")),
            .success(PingResponse(statusCode: 200, body: "")),
            .success(PingResponse(statusCode: 200, body: "")),
        ])

        // Advances 20s on every call, captured as a `let Mutex`, not a captured local `var` --
        // Swift 6 strict concurrency rejects the latter even under a lock (`Connectivity.swift`,
        // .planning/LEARNINGS.md). A deadline 30s out is crossed on the 4th call (t=60), which
        // this drain's per-entry sequence of now() calls reaches partway through the second
        // entry, before it is ever sent.
        let callCount = Mutex(0)
        let now: @Sendable () -> Date = {
            let elapsed = callCount.withLock { count -> TimeInterval in
                let value = TimeInterval(count) * 20
                count += 1
                return value
            }
            return Self.fixedNow.addingTimeInterval(elapsed)
        }
        let deadline = Self.fixedNow.addingTimeInterval(30)
        let drain = Self.makeDrain(
            store: store, credentials: credentials, transport: transport, now: now)

        let report = await drain.drain(before: deadline, surfacingFailures: true)

        #expect(transport.callCount < 3)
        let remainingIDs = Set(store.currentEntries.map(\.id))
        let sentIDs = Set(report.updates.filter { $0.outcome == .sent }.map(\.id))
        #expect(remainingIDs.isDisjoint(with: sentIDs))
        #expect(remainingIDs.count + sentIDs.count == 3)
        // Every entry still on file is byte-for-byte the entry that went in -- untouched, not
        // merely un-sent.
        for remaining in store.currentEntries {
            let original = [first, second, third].first { $0.id == remaining.id }
            #expect(remaining == original)
        }
    }

    @Test
    func theFileIsRewrittenAfterEachEntryNotOnlyAtTheEnd() async throws {
        let first = Self.makeQueuedPing()
        let second = Self.makeQueuedPing()
        let third = Self.makeQueuedPing()
        let store = FakeQueueStore(entries: [first, second, third])
        let credentials = FakeCredentialStore()
        credentials.stored = Self.fixtureCredentials
        let transport = FakeTransport(script: [
            .success(PingResponse(statusCode: 200, body: "")),
            .success(PingResponse(statusCode: 200, body: "")),
            .success(PingResponse(statusCode: 200, body: "")),
        ])
        let drain = Self.makeDrain(store: store, credentials: credentials, transport: transport)

        let report = await drain.drain(before: Self.farFutureDeadline, surfacingFailures: true)

        #expect(report.updates.count == 3)
        #expect(store.replaceCalls.count == 3)
        #expect(store.replaceCalls.map(\.count) == [2, 1, 0])
        #expect(store.currentEntries.isEmpty)
    }
}
