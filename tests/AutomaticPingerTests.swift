import Foundation
import Synchronization
import Testing
@testable import GrokBotLocator

/// Proves `AutomaticPinger` with no view, no network, no CoreLocation: a refused rate-limiter
/// claim sends nothing and logs nothing, an allowed trigger sends with the GEOCODED label
/// (never the typed manual label), an empty label is a normal outcome, an automatic ping never
/// announces, the history row carries whichever trigger produced it, a retryable send is
/// recorded as queued rather than dropped, and two triggers inside the shared window produce
/// exactly one send -- the same gate REQ-09/SC-04 counts the manual path through.
///
/// Every fake below genuinely suspends (`await Task.yield()`) before returning
/// (.planning/LEARNINGS.md -- a fake that never suspends cannot exercise anything that happens
/// across an await).
@MainActor
@Suite
struct AutomaticPingerTests {

    // MARK: Fakes -- the collaborators AutomaticPinger itself depends on

    private final class FakeSender: PingSending, @unchecked Sendable {
        var attemptToReturn = PingAttempt(
            fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
        private(set) var sendCallCount = 0
        private(set) var capturedLabels: [String] = []
        private(set) var capturedFixes: [LocationFix] = []

        func send(label: String, using fix: LocationFix) async -> PingAttempt {
            sendCallCount += 1
            capturedLabels.append(label)
            capturedFixes.append(fix)
            await Task.yield()
            return attemptToReturn
        }

        /// AutomaticPinger always has a fix in hand -- it must never call this arm.
        func send(label: String) async -> PingAttempt {
            Issue.record("AutomaticPinger must call send(label:using:), never send(label:)")
            return PingAttempt(fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
        }
    }

    private final class FakeTriggerLabelProvider: TriggerLabelProviding, @unchecked Sendable {
        var labelToReturn = ""

        func label(for coordinate: TriggerCoordinate) async -> String {
            await Task.yield()
            return labelToReturn
        }
    }

    private final class FakeRateLimiter: PingRateLimiting, @unchecked Sendable {
        var decisionToReturn: RateLimitDecision = .allowed
        private(set) var claimCallCount = 0

        func claim(at now: Date) async -> RateLimitDecision {
            claimCallCount += 1
            await Task.yield()
            return decisionToReturn
        }

        func setMinimumInterval(_ seconds: TimeInterval) async {}
    }

    // MARK: Fakes -- only to satisfy `PingModel`'s initializer. `AutomaticPinger` folds into
    // `model.apply(_:announcing:)`; nothing here should ever be called by these tests, since
    // `model.ping()` (the manual path) never runs in this suite.

    private final class NeverCalledSender: PingSending, @unchecked Sendable {
        func send(label: String) async -> PingAttempt {
            Issue.record("PingModel.ping() should never run in AutomaticPingerTests")
            return PingAttempt(fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
        }

        func send(label: String, using fix: LocationFix) async -> PingAttempt {
            Issue.record("PingModel.ping() should never run in AutomaticPingerTests")
            return PingAttempt(fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
        }
    }

    private final class InMemoryLabelStore: PingLabelStore, @unchecked Sendable {
        private var label: String
        init(initialLabel: String) { label = initialLabel }
        func loadLabel() -> String { label }
        func save(_ newLabel: String) { label = newLabel }
    }

    private final class NeverCalledFixProvider: LocationFixProvider, @unchecked Sendable {
        func currentFix() async throws -> LocationFix {
            Issue.record("PingModel.ping() should never run in AutomaticPingerTests")
            throw LocationFixError.unavailable
        }
        func authorizationNotice() async -> String? { nil }
    }

    /// `model`'s OWN gate -- distinct from the `rateLimiter` handed to `AutomaticPinger` below,
    /// and never claimed against in this suite either.
    private struct AlwaysAllowingRateLimiter: PingRateLimiting {
        func claim(at now: Date) async -> RateLimitDecision { .allowed }
        func setMinimumInterval(_ seconds: TimeInterval) async {}
    }

    // MARK: Fixtures -- synthetic values only, none resolves anywhere.

    /// `nonisolated`: a plain, immutable `Sendable` value with no actor-bound state, and
    /// `Fakes`' default `now` closure below reads it from inside a `@Sendable` closure body,
    /// which cannot reference a `@MainActor`-isolated static.
    private nonisolated static let fixtureFix = LocationFix(
        latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000))

    @MainActor
    private struct Fakes {
        let sender = FakeSender()
        let labels = FakeTriggerLabelProvider()
        let rateLimiter: any PingRateLimiting
        let model: PingModel
        let now: @Sendable () -> Date

        init(
            modelLabel: String = "",
            rateLimiter: any PingRateLimiting = FakeRateLimiter(),
            now: @escaping @Sendable () -> Date = { AutomaticPingerTests.fixtureFix.timestamp }
        ) {
            self.rateLimiter = rateLimiter
            self.now = now
            model = PingModel(
                sender: NeverCalledSender(), labelStore: InMemoryLabelStore(initialLabel: modelLabel),
                fixes: NeverCalledFixProvider(), rateLimiter: AlwaysAllowingRateLimiter(),
                now: { Date() })
        }

        func makePinger() -> AutomaticPinger {
            AutomaticPinger(
                sender: sender, labels: labels, rateLimiter: rateLimiter, model: model, now: now)
        }
    }

    // MARK: The rate gate

    @Test
    func aRateLimitedTriggerSendsNothingAndLogsNothing() async {
        let limiter = FakeRateLimiter()
        limiter.decisionToReturn = .tooSoon(retryAfter: 30, reason: "Too soon -- try again later.")
        let fakes = Fakes(rateLimiter: limiter)

        let result = await fakes.makePinger().ping(fix: Self.fixtureFix, trigger: .arrival)

        #expect(result == .rateLimited)
        #expect(fakes.sender.sendCallCount == 0)
        #expect(fakes.model.log.entries.isEmpty)
        #expect(fakes.model.lastAttempt == nil)
    }

    // MARK: The label source (never the typed manual label)

    @Test
    func anAllowedTriggerSendsWithTheGeocodedLabel() async {
        let fakes = Fakes(modelLabel: "Alberobello")
        fakes.labels.labelToReturn = "Ostuni"
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)

        _ = await fakes.makePinger().ping(fix: Self.fixtureFix, trigger: .arrival)

        #expect(fakes.sender.capturedLabels == ["Ostuni"])
        #expect(fakes.model.label == "Alberobello")  // untouched -- the typed label is not read
    }

    @Test
    func anEmptyLabelProviderProducesAnEmptyLabel() async {
        // `modelLabel` is seeded non-empty so this cannot pass by coincidence against a caller
        // that reads the typed manual label instead of the provider.
        let fakes = Fakes(modelLabel: "Alberobello")
        fakes.labels.labelToReturn = ""
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)

        _ = await fakes.makePinger().ping(fix: Self.fixtureFix, trigger: .arrival)

        #expect(fakes.sender.capturedLabels == [""])
    }

    // MARK: Silence

    @Test
    func anAutomaticPingIsNeverAnnounced() async {
        let fakes = Fakes()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)

        _ = await fakes.makePinger().ping(fix: Self.fixtureFix, trigger: .arrival)

        #expect(fakes.model.log.entries.count == 1)
        #expect(fakes.model.lastAttempt == nil)
    }

    // MARK: The trigger marking (REQ-07)

    @Test(arguments: [PingTrigger.arrival, .significantChange, .geofenceExit])
    func theHistoryRowCarriesTheTriggerItCameFrom(trigger: PingTrigger) async {
        let fakes = Fakes()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)

        _ = await fakes.makePinger().ping(fix: Self.fixtureFix, trigger: trigger)

        #expect(fakes.model.log.entries.first?.trigger == trigger)
    }

    // MARK: The durable-queue arm reaches through the same PingSender

    @Test
    func aQueuedAutomaticPingIsRecordedAsQueuedNotDropped() async {
        let fakes = Fakes()
        let queuedID = UUID()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .retryable(reason: "Try again in a moment."),
            statusCode: 503, responseBody: nil, queuedID: queuedID)

        let result = await fakes.makePinger().ping(fix: Self.fixtureFix, trigger: .geofenceExit)

        #expect(result == .pinged(.queued))
        #expect(fakes.model.log.entries.first?.outcome == .queued)
        #expect(fakes.model.log.entries.first?.reason == "Try again in a moment.")
        #expect(fakes.model.log.entries.first?.id == queuedID)
    }

    // MARK: The shared rate gate (REQ-09/SC-04) with the REAL limiter

    /// REQ-09's acceptance clause on the automatic side: two triggers 20s apart, against the
    /// real `PingRateLimiter` at its default 60s interval, produce exactly one send.
    @Test
    func twoTriggersTwentySecondsApartProduceOnePing() async {
        let base = Self.fixtureFix.timestamp
        let limiter = PingRateLimiter()
        let callCount = Mutex(0)
        let now: @Sendable () -> Date = {
            let elapsed = callCount.withLock { count -> TimeInterval in
                let value = TimeInterval(count) * 20
                count += 1
                return value
            }
            return base.addingTimeInterval(elapsed)
        }
        let fakes = Fakes(rateLimiter: limiter, now: now)
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)
        let pinger = fakes.makePinger()

        _ = await pinger.ping(fix: Self.fixtureFix, trigger: .arrival)
        _ = await pinger.ping(fix: Self.fixtureFix, trigger: .arrival)

        #expect(fakes.sender.sendCallCount == 1)
    }
}
