import Foundation
import Synchronization
import Testing
@testable import GrokBotLocator

/// Proves `QueueDrainCoordinator` owns every drain trigger REQ-05/SC-02 hands to phase 03:
/// launch hydration is silent and capped at the log's own capacity, hydration never re-runs, a
/// connectivity edge drains the queue unattended, a drain notice reaches the user only through
/// `PingModel.show(notice:)`, and a background drain keeps a permanent failure on file until a
/// foreground drain actually surfaces it. Fakes only -- no network, no disk, no real clock.
@MainActor
@Suite
struct QueueDrainCoordinatorTests {

    // MARK: Fakes -- same shape as `PingQueueDrainTests`, lock-guarded: `PingQueueStoring` and
    // `PingTransport` are nonisolated `async` requirements, so a fake without a lock can hang the
    // suite intermittently (.planning/LEARNINGS.md, the phase-02 fake that hung 2 runs in 5).

    private final class FakeQueueStore: PingQueueStoring, @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [QueuedPing]
        var loadErrorToThrow: Error?

        init(entries: [QueuedPing] = []) {
            self.entries = entries
        }

        var currentEntries: [QueuedPing] {
            lock.withLock { entries }
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

    /// Replays a caller-set script of responses or errors, one per call, holding past the end of
    /// the script on a plain 200 -- same contract as `PingQueueDrainTests`'s fake.
    private final class FakeTransport: PingTransport, @unchecked Sendable {
        private let lock = NSLock()
        private var script: [Result<PingResponse, Error>]
        private var index = 0
        private var callCountStorage = 0

        init(script: [Result<PingResponse, Error>] = []) {
            self.script = script
        }

        var callCount: Int { lock.withLock { callCountStorage } }

        /// Replaces the script and resets the replay index -- lets a test reprogram the same
        /// fake mid-run (e.g. "now answer 200" after connectivity returns).
        func reprogram(_ newScript: [Result<PingResponse, Error>]) {
            lock.withLock {
                script = newScript
                index = 0
            }
        }

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

    /// `load()` is a synchronous (non-`async`) requirement, so every call lands on the actor's
    /// own turn -- no lock needed, same as `PingQueueDrainTests`'s fake.
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

    /// A stream the test drives by hand -- `AsyncStream.makeStream()` hands back the stream and
    /// its continuation together, so `yieldEdge()` can fire an edge on demand with no
    /// `NWPathMonitor` and no real network anywhere in this suite.
    private final class FakeConnectivity: ConnectivityObserving, @unchecked Sendable {
        private let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() {
            (stream, continuation) = AsyncStream<Void>.makeStream()
        }

        func onlineEdges() -> AsyncStream<Void> { stream }

        func yieldEdge() {
            continuation.yield()
        }
    }

    /// Stand-ins for `PingModel`'s other two dependencies. Neither is ever expected to be
    /// called by anything under test here -- `QueueDrainCoordinator` only ever reaches
    /// `PingModel.apply(_:announcing:)` and `.show(notice:)`, never `ping()` -- so a call into
    /// either is a test bug, not a valid path.
    private final class FakeLabelStore: PingLabelStore, @unchecked Sendable {
        func loadLabel() -> String { "" }
        func save(_ newLabel: String) {}
    }

    private final class FakeLocationFixProvider: LocationFixProvider, @unchecked Sendable {
        func currentFix() async throws -> LocationFix {
            throw LocationFixError.unavailable
        }
        func authorizationNotice() async -> String? { nil }
    }

    // MARK: Fixtures -- synthetic values only, none resolves anywhere.

    // `nonisolated` because both are read from inside `@Sendable` closures (the `now` fixture
    // default, `FakeTransport`/`FakeCredentialStore` fixture values) -- without it, a MainActor-
    // isolated static on this `@MainActor` suite cannot be referenced from a Sendable context.
    private nonisolated static let fixedNow = Date(timeIntervalSince1970: 1_700_000_000)

    private nonisolated static let fixtureCredentials = WebhookCredentials(
        url: URL(string: "https://example.invalid/webhook")!,
        senderKey: "dummy-sender-key-coordinator-test",
        headerName: "X-Test-Key")

    private static func makeQueuedPing(
        id: UUID = UUID(),
        latitude: Double = 40.77465,
        longitude: Double = 17.23107,
        label: String = "Test ping",
        capturedAt: Date = fixedNow,
        firstAttemptAt: Date = fixedNow,
        attemptsMade: Int = 1,
        nextAttemptAt: Date = fixedNow,
        permanentFailure: String? = nil
    ) -> QueuedPing {
        QueuedPing(
            id: id,
            payload: PingPayload(
                latitude: latitude,
                longitude: longitude,
                accuracyMetres: 5.0,
                label: label,
                capturedAt: capturedAt
            ),
            firstAttemptAt: firstAttemptAt,
            attemptsMade: attemptsMade,
            nextAttemptAt: nextAttemptAt,
            permanentFailure: permanentFailure
        )
    }

    /// Bundles every fake the coordinator needs, wired the way production wires them (03-12):
    /// ONE store shared between hydration and the real `PingQueueDrain`, a REAL `PingModel` over
    /// phase 02's fakes, and a REAL `PingQueueDrain` over this bundle's transport/credentials.
    @MainActor
    private struct Fakes {
        let store: FakeQueueStore
        let transport: FakeTransport
        let credentials: FakeCredentialStore
        let connectivity = FakeConnectivity()
        let model: PingModel
        let coordinator: QueueDrainCoordinator

        init(
            entries: [QueuedPing] = [],
            transportScript: [Result<PingResponse, Error>] = [],
            hasCredentials: Bool = true,
            now: @escaping @Sendable () -> Date = { QueueDrainCoordinatorTests.fixedNow }
        ) {
            store = FakeQueueStore(entries: entries)
            transport = FakeTransport(script: transportScript)
            credentials = FakeCredentialStore()
            credentials.stored = hasCredentials ? QueueDrainCoordinatorTests.fixtureCredentials : nil
            model = PingModel(
                sender: NeverCalledSender(), labelStore: FakeLabelStore(),
                fixes: FakeLocationFixProvider())
            let drain = PingQueueDrain(
                store: store, credentials: credentials, transport: transport,
                policy: .standard, now: now)
            coordinator = QueueDrainCoordinator(
                store: store, drain: drain, model: model, connectivity: connectivity, now: now)
        }
    }

    /// `PingModel.ping()` is never called anywhere in this suite -- only `apply(_:announcing:)`
    /// and `show(notice:)`, both reached through the coordinator -- so this sender exists only
    /// to satisfy `PingModel`'s initializer and traps if it is ever actually invoked.
    private final class NeverCalledSender: PingSending, @unchecked Sendable {
        func send(label: String) async -> PingAttempt {
            Issue.record("PingSending.send should never be called by QueueDrainCoordinator")
            return PingAttempt(fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
        }
    }

    // MARK: Tests

    @Test
    func launchHydratesTheHistoryFromTheQueueFile() async throws {
        let first = Self.makeQueuedPing()
        let second = Self.makeQueuedPing()
        let fakes = Fakes(
            entries: [first, second],
            transportScript: [
                .success(PingResponse(statusCode: 503, body: "")),
                .success(PingResponse(statusCode: 503, body: "")),
            ])

        await fakes.coordinator.start()

        #expect(fakes.model.log.entries.count == 2)
        for entry in fakes.model.log.entries {
            #expect(entry.outcome == .queued)
            #expect(entry.reason == "Waiting to send. It will go out at the next opportunity.")
        }
        // Silent: hydration never announces, and the drain in `start()` delivered nothing (both
        // entries came back retryable, which never produces an update) -- nothing here tells the
        // user "Ping failed" for a tap they never made.
        #expect(fakes.model.lastAttempt == nil)
    }

    @Test
    func launchHydratesAPermanentFailureSilentlyBeforeItIsSurfaced() async throws {
        // A failure marked during an earlier, non-surfacing (background) drain: it is already on
        // file with its own reason, and hydration must restore it into the log exactly as it
        // reads -- silently. It is only actually SURFACED (announced) by the drain later in this
        // same `start()` call, because that drain is the first chance anyone has had to see it.
        let entry = Self.makeQueuedPing(permanentFailure: "The webhook rejected the sender key.")
        let fakes = Fakes(entries: [entry])

        await fakes.coordinator.start()

        #expect(fakes.model.log.entries.count == 1)
        #expect(fakes.model.log.entries.first?.outcome == .failed)
        #expect(fakes.model.log.entries.first?.reason == "The webhook rejected the sender key.")
        // Surfaced once, by the drain that follows hydration in the same `start()` call -- this
        // IS a fresh disclosure (nothing on screen showed it before now), so it is announced.
        #expect(fakes.model.lastAttempt?.outcome == .failed)
        #expect(fakes.store.currentEntries.isEmpty)
    }

    @Test
    func hydrationIsCappedAtTheLogsCapacityAndKeepsTheNewest() async throws {
        let seedCount = PingHistoryLog.capacity + 10
        let entries = (0..<seedCount).map { offset in
            Self.makeQueuedPing(
                capturedAt: Self.fixedNow.addingTimeInterval(TimeInterval(offset)),
                nextAttemptAt: Self.fixedNow.addingTimeInterval(3_600))
        }
        let fakes = Fakes(entries: entries)

        await fakes.coordinator.start()

        #expect(fakes.model.log.entries.count == PingHistoryLog.capacity)
        let newestSeeded = entries.last!
        let oldestSeeded = entries.first!
        #expect(fakes.model.log.entries.contains { $0.id == newestSeeded.id })
        #expect(!fakes.model.log.entries.contains { $0.id == oldestSeeded.id })
        // Bounded on the SCREEN only -- every seeded entry is still on the queue file.
        #expect(fakes.store.currentEntries.count == seedCount)
    }

    @Test
    func hydrationRunsOnlyOnce() async throws {
        // `nextAttemptAt` is an hour past `fixedNow`, so neither `start()` call's foreground
        // drain ever finds this entry due -- any row change we see is `hydrate()`'s doing, or
        // it is nothing at all.
        let entry = Self.makeQueuedPing(nextAttemptAt: Self.fixedNow.addingTimeInterval(3_600))
        let fakes = Fakes(entries: [entry])

        await fakes.coordinator.start()
        #expect(fakes.model.log.entries.count == 1)
        #expect(fakes.model.log.entries.first?.outcome == .queued)

        // Simulate the row having been corrected by some OTHER mechanism between the two
        // `start()` calls (what a real drain elsewhere would do) -- if `hasHydrated` ever failed
        // to guard, a second hydration would stomp this back to the generic standing sentence.
        fakes.model.apply(
            [PingDeliveryUpdate(
                id: entry.id, timestamp: entry.payload.capturedAt,
                latitude: entry.payload.latitude, longitude: entry.payload.longitude,
                label: entry.payload.label, outcome: .sent, reason: nil)],
            announcing: false)
        #expect(fakes.model.log.entries.first?.outcome == .sent)

        await fakes.coordinator.start()

        #expect(fakes.model.log.entries.count == 1)
        #expect(fakes.model.log.entries.first?.outcome == .sent)
    }

    @Test
    func aConnectivityEdgeDrainsTheQueue() async throws {
        // Not due at `fixedNow` -- `start()`'s own foreground drain must leave it exactly as
        // hydrated, so the send below can only be attributed to the connectivity edge.
        let entry = Self.makeQueuedPing(nextAttemptAt: Self.fixedNow.addingTimeInterval(3_600))
        let clock = Mutex(Self.fixedNow)
        let now: @Sendable () -> Date = { clock.withLock { $0 } }
        let fakes = Fakes(
            entries: [entry],
            transportScript: [.success(PingResponse(statusCode: 200, body: ""))],
            now: now)

        await fakes.coordinator.start()
        #expect(fakes.model.log.entries.first?.outcome == .queued)
        #expect(fakes.transport.callCount == 0)

        // Advance past the entry's due time, THEN fire the edge -- REQ-05's "airplane off ->
        // flips to sent" with nobody touching the screen.
        clock.withLock { $0 = Self.fixedNow.addingTimeInterval(7_200) }
        fakes.connectivity.yieldEdge()

        var iterations = 0
        while fakes.model.log.entries.first?.outcome != .sent, iterations < 1_000 {
            await Task.yield()
            iterations += 1
        }

        #expect(iterations < 1_000)
        #expect(fakes.model.log.entries.first?.outcome == .sent)
    }

    @Test
    func aNoticeFromTheDrainBecomesOnScreenGuidance() async throws {
        let entry = Self.makeQueuedPing()
        let fakes = Fakes(entries: [entry], hasCredentials: false)

        await fakes.coordinator.drainForeground()

        #expect(fakes.model.guidance != nil)
        #expect(fakes.model.guidance?.contains("Settings") == true)
        #expect(fakes.model.log.entries.isEmpty)
    }

    @Test
    func aBackgroundDrainKeepsAPermanentlyFailedEntryOnFile() async throws {
        let entry = Self.makeQueuedPing()
        let fakes = Fakes(
            entries: [entry],
            transportScript: [.success(PingResponse(statusCode: 401, body: ""))])

        await fakes.coordinator.drainBackground()

        #expect(fakes.store.currentEntries.count == 1)
        #expect(fakes.store.currentEntries.first?.permanentFailure != nil)

        await fakes.coordinator.drainForeground()

        #expect(fakes.store.currentEntries.isEmpty)
    }
}
