import CoreLocation
import Foundation

/// REQ-08: one region at the last ping, an exit event when the phone leaves it, and a
/// re-registration at the new location. `CLMonitor` is confined to this file
/// (scripts/smoke.sh's location guard, check 4) -- nothing else in `src/` may name it.
///
/// The 150 m radius (`radiusMetres` below) is a BACKSTOP decision, not derived from
/// REQUIREMENTS.md: REQ-08 says only "registers a region at the last ping" and names no size,
/// and REQ-06's 500 m is a movement threshold, not a radius. See this plan's `backstop_truths`.
///
/// This file writes NOTHING to disk and keeps no per-app settings key of its own. The region
/// `CLMonitor` holds under `conditionIdentifier` is ONE of two durable records of where the last
/// ping happened -- what `currentCentre()` reads back (RESEARCH.md Q2; confirmed live against the
/// DocC page for `CLMonitor.record(for:)` on 2026-09-11, see this plan's SUMMARY) is still the
/// region's own state, nothing more. The OTHER record is `LastPingStore.swift` (D-16,
/// 2026-09-11): a cold relaunch with only the geofence trigger enabled has no way to recover a
/// reference from this type alone if no region survived, so `TriggerCoordinator
/// .recoverReferenceIfNeeded()` reads the last-ping file FIRST and falls back to `currentCentre()`
/// here second. D-16 widened D-12's "never copied anywhere else" by exactly one more sanctioned
/// store, and no further -- this file still persists nothing of its own.
protocol GeofenceMonitoring: Sendable {
    /// Registers (or replaces) the one region, centred on `coordinate`.
    func register(at coordinate: TriggerCoordinate) async
    /// The registered region's centre, or `nil` if nothing is registered.
    func currentCentre() async -> TriggerCoordinate?
    /// Begins consuming exit events. `onExit` fires once per exit, carrying the event's own
    /// `date` -- never "now". REQ-08 is exit-only: an entry (`.satisfied`) fires nothing.
    func startObserving(onExit: @escaping @Sendable (Date) async -> Void) async
    /// Stops consuming events. A later exit fires nothing until `startObserving` is called again.
    func stopObserving() async
    /// Removes the registered region and clears the readable-back centre.
    func unregister() async
}

/// `CLMonitor`-backed conformer. Community source describes `CLMonitor` itself as implemented as
/// an actor ("every one of its APIs requires an `await`") -- consistent with its `async` `init(_:)`
/// and `await`-qualified `add`/`remove`/`record(for:)` calls used below.
actor CLMonitorGeofence: GeofenceMonitoring {
    static let monitorName = "GrokBotLocatorTriggers"
    static let conditionIdentifier = "last-ping-region"
    static let radiusMetres: CLLocationDistance = 150

    /// A `Task<CLMonitor, Never>` rather than a plain `CLMonitor?`: the task is the single point
    /// of assignment, made BEFORE the first suspension inside it, so a second caller arriving
    /// while the first `CLMonitor(_:)` call is still suspended awaits the SAME task and gets the
    /// SAME monitor instead of racing to build a second one. LEARNINGS: an actor serializes
    /// entry, not a call -- it is reentrant at every `await`, and two interleaved `monitor()`
    /// calls with no guard here would each build and hold a different backing `CLMonitor`.
    private var monitorTask: Task<CLMonitor, Never>?

    /// In-memory fallback for `currentCentre()` only -- never the source of truth. The monitor
    /// itself (read back via `record(for:)`) is the durable record; this exists purely so
    /// `currentCentre()` has something to return in the (unexpected) case the record lookup
    /// comes back empty right after a register.
    private var registeredCentre: TriggerCoordinate?

    private var observationTask: Task<Void, Never>?

    private func monitor() async -> CLMonitor {
        if let monitorTask {
            return await monitorTask.value
        }
        let task = Task<CLMonitor, Never> {
            await CLMonitor(Self.monitorName)
        }
        monitorTask = task
        return await task.value
    }

    func register(at coordinate: TriggerCoordinate) async {
        let monitor = await monitor()
        let condition = CLMonitor.CircularGeographicCondition(
            center: CLLocationCoordinate2D(latitude: coordinate.latitude, longitude: coordinate.longitude),
            radius: Self.radiusMetres)
        // Always the SAME identifier: `add(_:identifier:)` REPLACES the prior condition under
        // it rather than accumulating a second one. This is the entire leak-prevention
        // mechanism -- re-registering on every ping never grows past one region.
        await monitor.add(condition, identifier: Self.conditionIdentifier)
        registeredCentre = coordinate
    }

    func currentCentre() async -> TriggerCoordinate? {
        let monitor = await monitor()
        // Confirmed live against Apple's DocC JSON for CLMonitor-2r51v/record(for:) on
        // 2026-09-11: `func record(for identifier: String) -> CLMonitor.Record?`, and
        // `CLMonitor.Record.condition: any CLCondition`. Reading the centre back through this
        // accessor -- rather than trusting `registeredCentre` -- is what lets a cold background
        // relaunch (a fresh `CLMonitorGeofence` instance, `registeredCentre` reset to nil)
        // recover the last-ping coordinate: the record lives in the monitor CoreLocation holds
        // under `monitorName`, not in this actor's memory.
        if let record = await monitor.record(for: Self.conditionIdentifier),
            let condition = record.condition as? CLMonitor.CircularGeographicCondition {
            return TriggerCoordinate(
                latitude: condition.center.latitude, longitude: condition.center.longitude)
        }
        return registeredCentre
    }

    func startObserving(onExit: @escaping @Sendable (Date) async -> Void) async {
        let monitor = await monitor()
        observationTask?.cancel()
        // Fire-and-forget by design: nothing ever awaits this task's completion (`stopObserving`
        // only calls `.cancel()`), so a `CLMonitor.events` sequence that never terminates on its
        // own cannot block any caller. The `Task.isCancelled` check on each iteration is what
        // makes `.cancel()` actually silence a LATER exit even if the underlying sequence itself
        // does not proactively observe cancellation while suspended awaiting the next event.
        observationTask = Task {
            do {
                for try await event in await monitor.events {
                    if Task.isCancelled { return }
                    guard event.identifier == Self.conditionIdentifier else { continue }
                    // Diagnostic flags mean the region is no longer meaningfully armed --
                    // stop rather than spin on further events for an identifier the framework
                    // has already given up on.
                    if event.conditionLimitExceeded || event.authorizationDenied {
                        return
                    }
                    if event.state == .unsatisfied {
                        await onExit(event.date)
                    }
                    // `.satisfied` (entry) intentionally does nothing -- REQ-08 is exit-only.
                }
            } catch {
                // `CLMonitor.events` ended abnormally (e.g. cancellation surfaced as a thrown
                // error): observation simply stops. There is no queue or delivery to protect
                // here -- the next `register`/`startObserving` call re-arms it.
            }
        }
    }

    func stopObserving() async {
        observationTask?.cancel()
        observationTask = nil
    }

    func unregister() async {
        let monitor = await monitor()
        await monitor.remove(Self.conditionIdentifier)
        registeredCentre = nil
    }
}

// MARK: - On-device verification (REQ-08's acceptance clause)
//
// The unit suite (GeofenceMonitorTests.swift) proves, with no device: single-region reuse across
// repeated registrations, exit-only delivery (an entry fires nothing), exactly one callback per
// simulated exit, and that `radiusMetres` stays pinned at 150. It CANNOT prove that the OS
// actually wakes a suspended or terminated app for a real geofence exit -- that needs a device.
//
// Reproduction steps for whoever runs the device check -- VERIFICATION.md found that Debug's
// location-simulation menu produces no movement the OS ever notices (a teleport, not a route);
// the machine-driven procedure below is what actually worked for REQ-06 and is what this plan's
// own probe used.
// 0. In Settings, switch OFF significant-change and visits so any ping delivered below can only
//    be a geofence exit, and switch the geofence trigger ON with Always granted. Force-quit the
//    app and relaunch it -- this is the cold-relaunch case this plan (04-15) fixes.
// 1. Resolve a simulator UDID: `UDID=$(scripts/simulator-udid.sh)`.
// 2. Grant Always ahead of time if the prompt has already been answered once:
//    `xcrun simctl privacy "$UDID" grant location-always <bundle id>`.
// 3. Settle at the reference point: `xcrun simctl location "$UDID" set 40.0559,17.9925`
//    (`scripts/gpx/req06-start.gpx`'s coordinate), then tap "I'm here" once so a region registers
//    at the current position.
// 4. Drive the first exit with REAL interpolated movement, never a teleport:
//    `xcrun simctl location "$UDID" start --speed=20 --distance=50 40.0559,17.9925 40.0577012,17.9925`
//    (`scripts/gpx/req06-start.gpx` -> `scripts/gpx/req08-hop1.gpx`'s waypoints). Confirm exactly
//    ONE new row appears in the history, marked as a geofence exit.
// 5. Drive the second exit from there: `... start --speed=20 --distance=50
//    40.0577012,17.9925 40.0595024,17.9925` (`req08-hop1.gpx` -> `req08-hop2.gpx`). Confirm a
//    SECOND row appears -- this is what proves re-registration actually happened rather than the
//    app being stuck
//    watching the original region.
