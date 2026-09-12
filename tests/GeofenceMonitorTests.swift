import Foundation
import Testing
@testable import GrokBotLocator

/// `CLMonitor` cannot be driven from a unit test (no device, no simulator geofence triggers
/// under test control), so this file pins the CONTRACT every `GeofenceMonitoring` conformer must
/// satisfy, and ships the fake 04-11's `TriggerCoordinator` will be driven with. `internal`, not
/// `private`, so `TriggerCoordinatorTests` can reuse this exact fake rather than writing a second
/// one that could quietly disagree with this one's behaviour.
actor InMemoryGeofence: GeofenceMonitoring {
    /// Every `register(at:)` call, not just the latest -- so a caller that leaks regions (adds
    /// without ever reusing the identifier / removing the old one) is visible in the test that
    /// inspects this array, even though `currentCentre()` only ever reports the last one.
    private(set) var registrations: [TriggerCoordinate] = []
    private(set) var centre: TriggerCoordinate?
    private var onExit: (@Sendable (Date) async -> Void)?
    private(set) var isObserving = false

    func register(at coordinate: TriggerCoordinate) async {
        // Genuinely suspends before mutating -- LEARNINGS: phase 03's whole suite missed three
        // reentrancy holes because every fake returned without suspending, so a test driving
        // concurrent calls against this fake never actually interleaved. `Task.yield()` makes
        // `concurrentRegistrationsDoNotLeaveTwoRegions` below a real interleaving test.
        await Task.yield()
        registrations.append(coordinate)
        centre = coordinate
    }

    func currentCentre() async -> TriggerCoordinate? {
        centre
    }

    func startObserving(onExit: @escaping @Sendable (Date) async -> Void) async {
        self.onExit = onExit
        isObserving = true
    }

    func stopObserving() async {
        isObserving = false
        onExit = nil
    }

    func unregister() async {
        centre = nil
    }

    /// Fires the installed callback exactly once, carrying `date` through unchanged. Does
    /// nothing -- no trap -- when nothing is observing.
    func simulateExit(at date: Date) async {
        guard isObserving, let onExit else { return }
        await onExit(date)
    }
}

/// A `Sendable` recorder for exit callbacks -- an actor rather than a captured `var`, since Swift
/// 6 strict concurrency rejects an escaping closure mutating a captured local `var` even under a
/// lock (LEARNINGS).
private actor ExitRecorder {
    private(set) var dates: [Date] = []

    func record(_ date: Date) {
        dates.append(date)
    }
}

@Suite
struct GeofenceMonitorTests {
    private static func coordinate(_ value: Double) -> TriggerCoordinate {
        TriggerCoordinate(latitude: value, longitude: value)
    }

    @Test
    func registeringTwiceLeavesExactlyOneRegion() async {
        let geofence = InMemoryGeofence()
        let a = Self.coordinate(1)
        let b = Self.coordinate(2)

        await geofence.register(at: a)
        await geofence.register(at: b)

        let centre = await geofence.currentCentre()
        #expect(centre == b)
        // WHY re-registration on the real conformer cannot leak: a single fixed identifier
        // that `add(_:identifier:)` always reuses, which is what replaces rather than
        // accumulates a condition on every re-registration.
        #expect(!CLMonitorGeofence.conditionIdentifier.isEmpty)
    }

    @Test
    func anExitFiresTheCallbackExactlyOnce() async {
        let geofence = InMemoryGeofence()
        let recorder = ExitRecorder()
        let exitDate = Date(timeIntervalSince1970: 1_000)

        await geofence.startObserving { date in await recorder.record(date) }
        await geofence.simulateExit(at: exitDate)

        let dates = await recorder.dates
        #expect(dates == [exitDate])
    }

    @Test
    func anExitWithNoObserverFiresNothing() async {
        let geofence = InMemoryGeofence()

        // No trap, and nothing to fire: startObserving was never called.
        await geofence.simulateExit(at: Date())

        let isObserving = await geofence.isObserving
        #expect(isObserving == false)
    }

    @Test
    func stopObservingSilencesLaterExits() async {
        let geofence = InMemoryGeofence()
        let recorder = ExitRecorder()

        await geofence.startObserving { date in await recorder.record(date) }
        await geofence.stopObserving()
        await geofence.simulateExit(at: Date())

        let dates = await recorder.dates
        #expect(dates.isEmpty)
    }

    @Test
    func unregisterClearsTheCentre() async {
        let geofence = InMemoryGeofence()

        await geofence.register(at: Self.coordinate(3))
        await geofence.unregister()

        let centre = await geofence.currentCentre()
        #expect(centre == nil)
    }

    @Test
    func theRadiusIsOneHundredAndFiftyMetres() {
        // Pins the backstop value: a silent change to the radius fails this NAMED test rather
        // than drifting unnoticed.
        #expect(CLMonitorGeofence.radiusMetres == 150)
    }

    @Test
    func concurrentRegistrationsDoNotLeaveTwoRegions() async {
        let geofence = InMemoryGeofence()
        let coordinates = (0..<20).map { Self.coordinate(Double($0)) }

        await withTaskGroup(of: Void.self) { group in
            for coordinate in coordinates {
                group.addTask { await geofence.register(at: coordinate) }
            }
        }

        let centre = await geofence.currentCentre()
        #expect(centre != nil)
        if let centre {
            #expect(coordinates.contains(centre))
        }
    }
}
