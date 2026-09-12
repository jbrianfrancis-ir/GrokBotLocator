import CoreLocation
import Foundation
import Testing
@testable import GrokBotLocator

/// Proves `TriggerCoordinator` -- ARCHITECTURE's one location coordinator -- with no device: the
/// drain-first ordering (REQ-05's carried fourth drain opportunity), the 500 m gate (REQ-06),
/// arrival-only pinging (REQ-07), geofence re-registration (REQ-08), a rate-limited attempt
/// advancing nothing, arming only what settings enable (REQ-10), and the reentrancy case that
/// proves the reference-coordinate read-modify-write is genuinely serialized across concurrent
/// wakes, not just at its final write.
///
/// Every fake below genuinely suspends (`await Task.yield()`) before mutating or returning --
/// LEARNINGS: a fake that never suspends cannot exercise anything that happens across an actor's
/// `await`, and that is exactly how phase 03's three reentrancy holes shipped invisibly. Every
/// test awaits `await coordinator.settled()` between delivering an event and asserting anything:
/// a handler returns once its work is QUEUED onto the serialized chain, not once it has run, so
/// asserting immediately races the work being asserted about.
@Suite
struct TriggerCoordinatorTests {

    // MARK: Fakes

    /// Records every start/stop/authorization call `TriggerCoordinator` makes, and lets a test
    /// delivers a significant-change or visit report through the exact handlers `start()`
    /// installed -- the same path CoreLocation itself would use.
    actor FakeTriggerSource: LocationTriggerSource {
        private(set) var significantChangeStartCount = 0
        private(set) var significantChangeStopCount = 0
        private(set) var visitsStartCount = 0
        private(set) var visitsStopCount = 0
        private(set) var requestAlwaysCount = 0
        /// Counted separately from `requestAlwaysCount` because the two are now different
        /// events -- holding the session vs. prompting -- and debug/001 was precisely the case
        /// where the second happens and the first does not.
        private(set) var beginAlwaysSessionCount = 0
        private var authorization: CLAuthorizationStatus

        private var significantChangeHandler: (@Sendable (SignificantChangeReport) async -> Void)?
        private var visitHandler: (@Sendable (VisitReport) async -> Void)?

        init(authorization: CLAuthorizationStatus = .authorizedWhenInUse) {
            self.authorization = authorization
        }

        func setHandlers(
            significantChange: @escaping @Sendable (SignificantChangeReport) async -> Void,
            visit: @escaping @Sendable (VisitReport) async -> Void
        ) async {
            await Task.yield()
            significantChangeHandler = significantChange
            visitHandler = visit
        }

        func startSignificantChange() async {
            await Task.yield()
            significantChangeStartCount += 1
        }

        func stopSignificantChange() async {
            await Task.yield()
            significantChangeStopCount += 1
        }

        func startVisits() async {
            await Task.yield()
            visitsStartCount += 1
        }

        func stopVisits() async {
            await Task.yield()
            visitsStopCount += 1
        }

        func currentAuthorization() async -> CLAuthorizationStatus {
            await Task.yield()
            return authorization
        }

        func beginAlwaysSession() async {
            await Task.yield()
            beginAlwaysSessionCount += 1
        }

        func requestAlways() async -> CLAuthorizationStatus {
            await Task.yield()
            requestAlwaysCount += 1
            authorization = .authorizedAlways
            return authorization
        }
    }

    /// Scripts what `AutomaticPinger` would have decided, and records every `(fix, trigger)` it
    /// was asked to send -- `TriggerCoordinator` never sends anything itself.
    actor CountingPinger: AutomaticPinging {
        private(set) var calls: [(fix: LocationFix, trigger: PingTrigger)] = []
        private var scriptedResults: [AutomaticPingResult]
        private let fallback: AutomaticPingResult

        init(scriptedResults: [AutomaticPingResult] = [], fallback: AutomaticPingResult = .pinged(.sent)) {
            self.scriptedResults = scriptedResults
            self.fallback = fallback
        }

        var callCount: Int { calls.count }

        func ping(fix: LocationFix, trigger: PingTrigger) async -> AutomaticPingResult {
            await Task.yield()
            calls.append((fix, trigger))
            if !scriptedResults.isEmpty {
                return scriptedResults.removeFirst()
            }
            return fallback
        }
    }

    /// `TriggerSettingsStoring` is synchronous by protocol (`UserDefaults`-backed in production),
    /// so this fake is a plain `@unchecked Sendable` class, matching the pattern this codebase
    /// already uses for a fake store (`SettingsModelTests.FakeCredentialStore`) rather than an
    /// actor, which cannot satisfy a non-async requirement.
    final class FakeSettingsStore: TriggerSettingsStoring, @unchecked Sendable {
        private var stored: TriggerSettings
        private(set) var saveCount = 0

        init(initial: TriggerSettings) {
            self.stored = initial
        }

        func load() -> TriggerSettings {
            stored
        }

        func save(_ settings: TriggerSettings) {
            stored = settings
            saveCount += 1
        }
    }

    /// The one-shot fix `runGeofenceExit` asks for -- a geofence exit event carries no coordinate
    /// of its own (RESEARCH.md Q2).
    actor FakeFixProvider: LocationFixProvider {
        private let result: Result<LocationFix, Error>

        init(result: Result<LocationFix, Error>) {
            self.result = result
        }

        func currentFix() async throws -> LocationFix {
            await Task.yield()
            return try result.get()
        }

        func authorizationNotice() async -> String? {
            await Task.yield()
            return nil
        }
    }

    /// Counts drain calls -- the drain itself is a plain injected closure
    /// (`@Sendable () async -> Void`), not a protocol, so this backs it rather than conforming to
    /// anything.
    actor DrainCounter {
        private(set) var count = 0

        func increment() async {
            await Task.yield()
            count += 1
        }
    }

    private struct FixUnavailable: Error {}

    // MARK: Fixtures

    private static func coordinate(_ latitude: Double, _ longitude: Double = 0) -> TriggerCoordinate {
        TriggerCoordinate(latitude: latitude, longitude: longitude)
    }

    private static func fix(
        at coordinate: TriggerCoordinate = TriggerCoordinatorTests.coordinate(0, 0),
        timestamp: Date = Date(timeIntervalSince1970: 1_000)
    ) -> LocationFix {
        LocationFix(
            latitude: coordinate.latitude, longitude: coordinate.longitude, accuracyMetres: 5,
            timestamp: timestamp)
    }

    private static func significantChangeReport(
        at coordinate: TriggerCoordinate, timestamp: Date = Date(timeIntervalSince1970: 1_000)
    ) -> SignificantChangeReport {
        SignificantChangeReport(coordinate: coordinate, accuracyMetres: 5, timestamp: timestamp)
    }

    private static func visitReport(
        at coordinate: TriggerCoordinate = TriggerCoordinatorTests.coordinate(1, 1),
        isArrival: Bool,
        arrivalDate: Date = Date(timeIntervalSince1970: 2_000)
    ) -> VisitReport {
        VisitReport(
            coordinate: coordinate, accuracyMetres: 5, arrivalDate: arrivalDate,
            departureDate: isArrival ? Date.distantFuture : arrivalDate.addingTimeInterval(600))
    }

    private static func makeCoordinator(
        significantChangeEnabled: Bool = false,
        visitsEnabled: Bool = false,
        geofenceEnabled: Bool = false,
        fixResult: Result<LocationFix, Error> = .success(TriggerCoordinatorTests.fix()),
        pingerScript: [AutomaticPingResult] = [],
        minimumIntervalSeconds: TimeInterval = PingRateLimiter.defaultInterval,
        rateLimiter: any PingRateLimiting = PingRateLimiter(),
        lastPing: any LastPingStoring = InMemoryLastPingStore(),
        authorization: CLAuthorizationStatus = .authorizedWhenInUse
    ) -> (
        coordinator: TriggerCoordinator, source: FakeTriggerSource, geofence: InMemoryGeofence,
        pinger: CountingPinger, counter: DrainCounter, store: FakeSettingsStore
    ) {
        let source = FakeTriggerSource(authorization: authorization)
        let geofence = InMemoryGeofence()
        let pinger = CountingPinger(scriptedResults: pingerScript)
        let fixes = FakeFixProvider(result: fixResult)
        var settings = TriggerSettings.initial
        settings.significantChangeEnabled = significantChangeEnabled
        settings.visitsEnabled = visitsEnabled
        settings.geofenceEnabled = geofenceEnabled
        settings.setMinimumInterval(minimumIntervalSeconds)
        let store = FakeSettingsStore(initial: settings)
        let counter = DrainCounter()
        let coordinator = TriggerCoordinator(
            source: source, geofence: geofence, pinger: pinger, fixes: fixes, settingsStore: store,
            lastPing: lastPing,
            rateLimiter: rateLimiter, drain: { await counter.increment() })
        return (coordinator, source, geofence, pinger, counter, store)
    }

    // MARK: Tests

    @Test
    func everyCallbackDrainsEvenWhenItDoesNotPing() async {
        let (coordinator, _, _, pinger, counter, _) = Self.makeCoordinator()
        await coordinator.start()

        await coordinator.handleSignificantChange(Self.significantChangeReport(at: Self.coordinate(1)))
        await coordinator.settled()
        await coordinator.handleVisit(Self.visitReport(isArrival: true))
        await coordinator.settled()
        await coordinator.handleGeofenceExit(at: Date())
        await coordinator.settled()

        #expect(await counter.count == 3)
        #expect(await pinger.callCount == 0)
    }

    @Test
    func aThreeHundredMetreWakeDrainsButDoesNotPing() async {
        let (coordinator, _, _, pinger, counter, _) = Self.makeCoordinator(significantChangeEnabled: true)
        await coordinator.start()

        await coordinator.handleSignificantChange(Self.significantChangeReport(at: Self.coordinate(0, 0)))
        await coordinator.settled()
        #expect(await pinger.callCount == 1)

        // ~300 m north of the seeded reference -- comfortably under the 500 m floor.
        let nearby = Self.coordinate(300.0 / 111_320, 0)
        await coordinator.handleSignificantChange(Self.significantChangeReport(at: nearby))
        await coordinator.settled()

        #expect(await counter.count == 2)
        #expect(await pinger.callCount == 1)
    }

    @Test
    func aFiveHundredMetreWakePings() async {
        let (coordinator, _, _, pinger, _, _) = Self.makeCoordinator(significantChangeEnabled: true)
        await coordinator.start()

        await coordinator.handleSignificantChange(Self.significantChangeReport(at: Self.coordinate(0, 0)))
        await coordinator.settled()
        #expect(await pinger.callCount == 1)

        // ~600 m north -- past the 500 m floor.
        let far = Self.coordinate(600.0 / 111_320, 0)
        await coordinator.handleSignificantChange(Self.significantChangeReport(at: far))
        await coordinator.settled()

        #expect(await pinger.callCount == 2)
        #expect(await pinger.calls.last?.trigger == .significantChange)
    }

    @Test
    func anArrivalPingsOnceAndADepartureDoesNot() async {
        let (coordinator, _, _, pinger, _, _) = Self.makeCoordinator(visitsEnabled: true)
        await coordinator.start()

        await coordinator.handleVisit(Self.visitReport(isArrival: true))
        await coordinator.settled()
        #expect(await pinger.callCount == 1)
        #expect(await pinger.calls.last?.trigger == .arrival)

        await coordinator.handleVisit(Self.visitReport(isArrival: false))
        await coordinator.settled()
        #expect(await pinger.callCount == 1)
    }

    @Test
    func aGeofenceExitPingsAndReRegistersAtTheNewPosition() async {
        let target = Self.coordinate(2, 2)
        let (coordinator, _, geofence, pinger, _, _) = Self.makeCoordinator(
            geofenceEnabled: true, fixResult: .success(Self.fix(at: target)))
        await coordinator.start()

        await coordinator.handleGeofenceExit(at: Date())
        await coordinator.settled()

        #expect(await pinger.callCount == 1)
        #expect(await pinger.calls.last?.trigger == .geofenceExit)
        let centre = await geofence.currentCentre()
        #expect(centre == target)
    }

    @Test
    func aRateLimitedPingDoesNotAdvanceTheReference() async {
        let seed = Self.coordinate(0, 0)
        let far = Self.coordinate(600.0 / 111_320, 0)
        let (coordinator, _, geofence, pinger, _, _) = Self.makeCoordinator(
            significantChangeEnabled: true, geofenceEnabled: true,
            pingerScript: [.pinged(.sent), .rateLimited])
        await coordinator.start()

        await coordinator.handleSignificantChange(Self.significantChangeReport(at: seed))
        await coordinator.settled()
        let seededReference = await coordinator.currentReference()
        #expect(seededReference == seed)
        let seededCentre = await geofence.currentCentre()
        #expect(seededCentre == seed)

        await coordinator.handleSignificantChange(Self.significantChangeReport(at: far))
        await coordinator.settled()

        #expect(await pinger.callCount == 2)
        let reference = await coordinator.currentReference()
        #expect(reference == seed)
        let centre = await geofence.currentCentre()
        #expect(centre == seed)
    }

    @Test
    func twoSimultaneousWakesProduceOnePingAndOneReference() async {
        let (coordinator, _, geofence, pinger, _, _) = Self.makeCoordinator(
            significantChangeEnabled: true, geofenceEnabled: true)
        await coordinator.start()

        // Seed the reference at R = (0, 0). With no reference yet, the gate always allows the
        // first ping (DisplacementGate's documented backstop).
        await coordinator.handleSignificantChange(Self.significantChangeReport(at: Self.coordinate(0, 0)))
        await coordinator.settled()
        #expect(await pinger.callCount == 1)

        // A and B are each ~700 m from R (well past the 500 m gate) but only ~45 m from EACH
        // OTHER -- one slightly east of due-north, one slightly west of it. Whichever wins the
        // race advances the reference; the other then measures against THAT new reference, not
        // R, and 45 m fails the gate. This is what proves the read-modify-write is serialized
        // end to end, not just at the final write.
        let a = Self.coordinate(0.0065, 0.0002)
        let b = Self.coordinate(0.0065, -0.0002)

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await coordinator.handleSignificantChange(Self.significantChangeReport(at: a)) }
            group.addTask { await coordinator.handleSignificantChange(Self.significantChangeReport(at: b)) }
        }
        await coordinator.settled()

        #expect(await pinger.callCount == 2)
        let winnerFix = await pinger.calls.last?.fix
        let reference = await coordinator.currentReference()
        let centre = await geofence.currentCentre()
        if let winnerFix {
            let winnerCoordinate = TriggerCoordinate(fix: winnerFix)
            #expect(reference == winnerCoordinate)
            #expect(centre == winnerCoordinate)
        } else {
            Issue.record("expected a second ping to have recorded a call")
        }
    }

    /// REQ-08's runtime gap (debug/001): a cold relaunch with Always ALREADY granted must still
    /// reach the one foreground touchpoint that starts holding a `CLServiceSession`
    /// (`LocationDelegateProxy.requestAlways()`, the sole assignment site for that session).
    /// Skipping it because the status is already `.authorizedAlways` leaves the process holding
    /// no session at all, and RESEARCH Q2/Q5 (WWDC24) is explicit that "Always authorization will
    /// only be effective when you hold one of these" -- so the region arms, the event loop spins,
    /// and the OS never delivers an exit to a backgrounded app.
    ///
    /// This is the case the rest of this suite structurally could not see: every other test
    /// starts from the fake's `.authorizedWhenInUse` default, which always takes the request
    /// branch.
    @Test
    func startingAlreadyAlwaysStillHoldsTheAlwaysSession() async {
        let (coordinator, source, _, _, _, _) = Self.makeCoordinator(
            geofenceEnabled: true, authorization: .authorizedAlways)

        await coordinator.start()

        #expect(await source.beginAlwaysSessionCount == 1)
        // Nothing to prompt for -- the grant is already there. The session is the missing piece,
        // not the permission, which is why asserting on the request count alone would have kept
        // passing on the broken code for the wrong reason.
        #expect(await source.requestAlwaysCount == 0)
    }

    /// The other half of the split: at When-In-Use an arming pass must do BOTH -- hold the
    /// session and ask for the upgrade. This is the path every other test in this suite takes.
    @Test
    func startingAtWhenInUseBothHoldsTheSessionAndRequestsAlways() async {
        let (coordinator, source, _, _, _, _) = Self.makeCoordinator(
            geofenceEnabled: true, authorization: .authorizedWhenInUse)

        await coordinator.start()

        #expect(await source.beginAlwaysSessionCount == 1)
        #expect(await source.requestAlwaysCount == 1)
    }

    @Test
    func disabledTriggersAreNotArmedAndEnablingArmsOnlyThatOne() async {
        let (coordinator, source, _, _, _, _) = Self.makeCoordinator()
        await coordinator.start()

        #expect(await source.significantChangeStartCount == 0)
        #expect(await source.visitsStartCount == 0)
        #expect(await source.requestAlwaysCount == 0)
        // REQ-10 covers the session too, not just the prompt: all three off means the app holds
        // no Always session at all.
        #expect(await source.beginAlwaysSessionCount == 0)

        var visitsOn = TriggerSettings.initial
        visitsOn.visitsEnabled = true
        await coordinator.update(visitsOn)

        #expect(await source.visitsStartCount == 1)
        #expect(await source.significantChangeStartCount == 0)
        #expect(await source.requestAlwaysCount == 1)
        #expect(await source.beginAlwaysSessionCount == 1)
    }

    @Test
    func turningEveryTriggerOffStopsEverythingAndUnregistersTheRegion() async {
        let (coordinator, source, geofence, _, _, _) = Self.makeCoordinator(
            significantChangeEnabled: true, visitsEnabled: true, geofenceEnabled: true)
        await coordinator.start()
        // Seed a registered region so unregister() below has something to clear.
        await geofence.register(at: Self.coordinate(0, 0))

        await coordinator.update(.initial)

        #expect(await source.significantChangeStopCount == 1)
        #expect(await source.visitsStopCount == 1)
        let centre = await geofence.currentCentre()
        #expect(centre == nil)
    }

    // MARK: REQ-08 cold-relaunch arming (D-16)

    /// The case that already worked at HEAD, still proven not to regress: a PREVIOUS process left
    /// a region registered (simulated here by calling `register` directly on the fake, standing
    /// in for `CLMonitor` having persisted it), and `start()` must recover the reference from
    /// THAT without re-registering over it.
    @Test
    func aColdStartWithOnlyTheGeofenceEnabledRecoversTheReference() async {
        let (coordinator, _, geofence, _, _, _) = Self.makeCoordinator(geofenceEnabled: true)
        let lastPingCoordinate = Self.coordinate(3, 3)
        await geofence.register(at: lastPingCoordinate)

        await coordinator.start()

        #expect(await coordinator.currentReference() == lastPingCoordinate)
        #expect(await geofence.registrations.count == 1, "start() must not re-register over a region already there")
    }

    /// The gap this plan closes: NO region survived the relaunch (the geofence fake starts
    /// empty), but D-16's last-ping file does carry a coordinate. `start()` must recover the
    /// reference from the FILE and use it to re-arm the region -- REQ-08 arms whether or not
    /// CLMonitor persisted anything.
    @Test
    func aColdStartWithNoRegionRecoversFromTheLastPingFileAndArms() async {
        let store = InMemoryLastPingStore()
        let coordinate = Self.coordinate(4, 4)
        await store.save(coordinate)
        let (coordinator, _, geofence, _, _, _) = Self.makeCoordinator(
            geofenceEnabled: true, lastPing: store)

        await coordinator.start()

        #expect(await coordinator.currentReference() == coordinate)
        #expect(await geofence.currentCentre() == coordinate, "the region must be registered FROM the file")
    }

    /// D-16 condition 4's coordinator-level half: a real ping first proves the store holds the
    /// coordinate the ping path just saved, then disabling every trigger must delete it, both on
    /// disk and in memory.
    @Test
    func disablingEveryTriggerDeletesTheLastPingCoordinate() async {
        let store = InMemoryLastPingStore()
        let target = Self.coordinate(5, 5)
        let (coordinator, _, _, pinger, _, _) = Self.makeCoordinator(
            significantChangeEnabled: true, fixResult: .success(Self.fix(at: target)),
            lastPing: store)
        await coordinator.start()

        await coordinator.handleSignificantChange(Self.significantChangeReport(at: target))
        await coordinator.settled()
        #expect(await pinger.callCount == 1)
        #expect(await store.load() == target)

        await coordinator.update(.initial)

        #expect(await store.load() == nil)
        #expect(await coordinator.currentReference() == nil)
    }

    /// The launch path: an interval already on disk must reach the gate through `start()`
    /// ALONE, with no Settings visit at all -- a relaunch must not silently revert to the
    /// default. LEARNINGS: the real `PingRateLimiter` throughout, never a fake -- a fake that
    /// returns without suspending cannot test an actor.
    @Test
    func anIntervalOnDiskReachesTheGateAtStart() async {
        let limiter = PingRateLimiter()
        let (coordinator, _, _, _, _, _) = Self.makeCoordinator(
            minimumIntervalSeconds: PingRateLimiter.defaultInterval * 2, rateLimiter: limiter)

        await coordinator.start()
        // No Settings visit -- start() alone must carry the interval on disk to the gate.

        let t = Date(timeIntervalSince1970: 1_700_000_000)
        #expect(await limiter.claim(at: t) == .allowed)
        guard
            case .tooSoon = await limiter.claim(
                at: t.addingTimeInterval(PingRateLimiter.defaultInterval * 1.5))
        else {
            Issue.record("start() did not carry the interval on disk to the gate")
            return
        }
    }
}
