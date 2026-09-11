import CoreLocation
import Foundation

/// ARCHITECTURE: "All location work sits in one actor-isolated coordinator; views never touch
/// the location manager directly." This type is that coordinator -- the phase's integration
/// point. It arms the three triggers from `TriggerSettings`, drains the offline queue on every
/// wake before deciding anything else, and asks `DisplacementGate` (never the OS) whether a
/// significant-change wake is actually 500 m of travel. It talks to CoreLocation only through
/// `LocationTriggerSource` and `GeofenceMonitoring` -- both protocols -- so this file never needs
/// to name the concrete location manager or monitor types, and scripts/smoke.sh's location guard
/// holds that boundary.
///
/// `start()` is a FOREGROUND touchpoint only, called once from the root view's `task` (04-13).
/// RESEARCH.md consequence 4: Always is only effective while a `CLServiceSession` is held, and a
/// session can only be started in the foreground -- so arming (and the Always request inside it)
/// must never run from a background wake. `update(_:)` is the other foreground touchpoint,
/// reached from a Settings toggle.
actor TriggerCoordinator {
    private let source: any LocationTriggerSource
    private let geofence: any GeofenceMonitoring
    private let pinger: any AutomaticPinging
    private let fixes: any LocationFixProvider
    private let settingsStore: any TriggerSettingsStoring
    /// The seam between the stored interval and the enforcer (REQ-09's gap): `applySettings`
    /// carries `s.minimumIntervalSeconds` here on every entry, and this type never restates the
    /// floor or the default -- `setMinimumInterval`'s own clamp is the only one that applies.
    private let rateLimiter: any PingRateLimiting
    private let drain: @Sendable () async -> Void

    private var settings: TriggerSettings
    /// Where the last ping happened. `nil` until the first ping ever goes out, or right after a
    /// cold background relaunch before `runSignificantChange` rehydrates it from the geofence
    /// monitor's own durable record (this app keeps no second coordinate file of its own -- D-12
    /// reserves that role for the offline queue alone).
    private var reference: TriggerCoordinate?
    private var alwaysWasRequested = false
    /// The tail of the serialized chain every handler below appends onto. `nil` until the first
    /// callback arrives.
    private var chain: Task<Void, Never>?

    init(
        source: any LocationTriggerSource,
        geofence: any GeofenceMonitoring,
        pinger: any AutomaticPinging,
        fixes: any LocationFixProvider,
        settingsStore: any TriggerSettingsStoring,
        rateLimiter: any PingRateLimiting,
        drain: @escaping @Sendable () async -> Void
    ) {
        self.source = source
        self.geofence = geofence
        self.pinger = pinger
        self.fixes = fixes
        self.settingsStore = settingsStore
        self.rateLimiter = rateLimiter
        self.drain = drain
        self.settings = .initial
    }

    /// Loads whatever is on disk, installs this coordinator as the one place every trigger
    /// callback lands, and arms exactly what settings say. Idempotent in the sense that installing
    /// the handlers twice just overwrites them with the same closures -- there is no per-call
    /// state here that a second call could duplicate.
    func start() async {
        settings = settingsStore.load()
        await source.setHandlers(
            significantChange: { [weak self] report in
                guard let self else { return }
                await self.handleSignificantChange(report)
            },
            visit: { [weak self] report in
                guard let self else { return }
                await self.handleVisit(report)
            }
        )
        await geofence.startObserving { [weak self] date in
            guard let self else { return }
            await self.handleGeofenceExit(at: date)
        }
        await applySettings(settings)
    }

    /// What a Settings toggle calls. Persists first, then arms/disarms to match.
    func update(_ newSettings: TriggerSettings) async {
        settingsStore.save(newSettings)
        settings = newSettings
        await applySettings(newSettings)
    }

    /// Requests Always only when at least one trigger is enabled and the app is not already
    /// authorized for it (REQ-10: never at launch with all three off). The three start/stop
    /// calls and the geofence registration are independent of whether that request succeeded --
    /// a refusal is reported through `authorizationNotice()`, not by silently leaving a trigger
    /// that IS switched on in Settings unarmed.
    private func applySettings(_ s: TriggerSettings) async {
        // FIRST -- above the Always request, so a refusal cannot skip it. Both entries into this
        // function carry the stored interval to the gate: `start()` (the value just loaded from
        // disk) and `update(_:)` (the value a Settings change just persisted).
        await rateLimiter.setMinimumInterval(s.minimumIntervalSeconds)

        if s.anyTriggerEnabled, await source.currentAuthorization() != .authorizedAlways {
            _ = await source.requestAlways()
            alwaysWasRequested = true
        }

        if s.significantChangeEnabled {
            await source.startSignificantChange()
        } else {
            await source.stopSignificantChange()
        }

        if s.visitsEnabled {
            await source.startVisits()
        } else {
            await source.stopVisits()
        }

        if s.geofenceEnabled {
            // Only registers when nothing is registered yet AND a reference already exists --
            // there is nothing to centre a region on before the first ping has ever gone out.
            if await geofence.currentCentre() == nil, let reference {
                await geofence.register(at: reference)
            }
        } else {
            await geofence.unregister()
        }
    }

    /// What SettingsView renders (04-12): a finished sentence about what the current
    /// authorization level does not allow, or `nil` when there is nothing to say.
    func authorizationNotice() async -> String? {
        TriggerAuthorizationNotice.notice(
            for: await source.currentAuthorization(), alwaysWasRequested: alwaysWasRequested)
    }

    func currentSettings() async -> TriggerSettings {
        settings
    }

    /// The completion signal for the serialized chain. A handler returns as soon as its work is
    /// QUEUED onto `chain`, not once it has run -- `serialized(_:)` below assigns a `Task` and
    /// returns immediately, so `await coordinator.handleSignificantChange(report)` on its own
    /// proves nothing about whether the drain, the gate, or the ping actually happened yet.
    /// Every assertion in the test suite runs after `await coordinator.settled()`.
    func settled() async {
        await chain?.value
    }

    /// Read-only window onto `reference` for tests -- `reference` itself stays `private` because
    /// this is the one piece of state the reentrancy tests need to observe, not a second way to
    /// mutate it.
    func currentReference() async -> TriggerCoordinate? {
        reference
    }

    /// Chains `body` after whatever is currently in flight, and reassigns `chain` to the new
    /// Task BEFORE any suspension -- so two callbacks arriving at once each capture a DIFFERENT
    /// `previous` and queue one after the other rather than both reading `reference` off the same
    /// stale snapshot. LEARNINGS: an actor serializes entry, not a call -- it is reentrant at
    /// every `await`. Without this, `runSignificantChange` below is a read-modify-write across
    /// three awaits (the geofence rehydration, the gate, and the ping itself), and two wakes
    /// racing through it would both read the old `reference`, both pass the displacement gate,
    /// and leave `reference` at whichever happened to finish last -- exactly the shape of holes
    /// phase 03 shipped three of.
    private func serialized(_ body: @escaping @Sendable () async -> Void) {
        let previous = chain
        chain = Task {
            await previous?.value
            await body()
        }
    }

    // MARK: - Significant change (REQ-06)

    func handleSignificantChange(_ report: SignificantChangeReport) async {
        serialized { await self.runSignificantChange(report) }
    }

    private func runSignificantChange(_ report: SignificantChangeReport) async {
        // FIRST and unconditional -- REQ-05's fourth drain opportunity, carried over from phase
        // 03. This wake is a drain chance whether or not it becomes a ping, so it sits above
        // every check below it, not beneath the enable check.
        await drain()
        guard settings.significantChangeEnabled else { return }
        guard let fix = report.locationFix() else { return }
        let coordinate = TriggerCoordinate(fix: fix)
        if reference == nil {
            // Cold-relaunch rehydration: the geofence monitor's registered region IS the durable
            // record of where the last ping happened (GeofenceMonitor.swift), so a fresh process
            // recovers it from there rather than this app keeping a second coordinate file.
            reference = await geofence.currentCentre()
        }
        guard DisplacementGate.shouldPing(from: reference, to: coordinate) else { return }
        await pingAndAdvance(fix: fix, coordinate: coordinate, trigger: .significantChange)
    }

    // MARK: - Visits (REQ-07)

    func handleVisit(_ report: VisitReport) async {
        serialized { await self.runVisit(report) }
    }

    private func runVisit(_ report: VisitReport) async {
        await drain()
        guard settings.visitsEnabled else { return }
        // Arrival only -- a departure produces no ping (REQ-07). No displacement gate here:
        // REQ-07 is about lingering somewhere, not about distance from the last ping.
        guard report.isArrival else { return }
        guard let fix = report.locationFix() else { return }
        await pingAndAdvance(fix: fix, coordinate: TriggerCoordinate(fix: fix), trigger: .arrival)
    }

    // MARK: - Geofence exit (REQ-08)

    func handleGeofenceExit(at date: Date) async {
        serialized { await self.runGeofenceExit(at: date) }
    }

    private func runGeofenceExit(at date: Date) async {
        await drain()
        guard settings.geofenceEnabled else { return }
        // The geofence monitor's exit event carries no coordinate of its own (RESEARCH.md Q2),
        // so a geofence exit needs a fresh one-shot fix rather than reusing whatever centred the
        // region.
        guard let fix = try? await fixes.currentFix() else { return }
        await pingAndAdvance(
            fix: fix, coordinate: TriggerCoordinate(fix: fix), trigger: .geofenceExit)
    }

    // MARK: - Shared tail

    /// The only place `reference` is advanced. Only a `.pinged` result moves it -- a rate-limited
    /// or credential/fix-less attempt sent nothing, so "where the last ping was" has not changed
    /// and re-registering the geofence there would be re-arming a region nothing actually reached.
    private func pingAndAdvance(
        fix: LocationFix, coordinate: TriggerCoordinate, trigger: PingTrigger
    ) async {
        let result = await pinger.ping(fix: fix, trigger: trigger)
        guard case .pinged = result else { return }
        reference = coordinate
        if settings.geofenceEnabled {
            await geofence.register(at: coordinate)
        }
    }
}

// MARK: - On-device verification (this plan's acceptance clauses the simulator cannot give)
//
// The unit suite (TriggerCoordinatorTests.swift) proves the drain-first ordering, the 500 m
// gate, arrival-only pinging, geofence re-registration, the rate-limited non-advance, and the
// concurrent-wake reentrancy case -- all with no device. It cannot prove the OS actually
// delivers these callbacks to a backgrounded or terminated app, or what that costs in battery.
// Reproduction steps for whoever runs the device check:
// (a) REQ-06 -- Xcode Debug > Simulate Location with a GPX route crossing 500 m, app
//     backgrounded, expect one ping; a 300 m route, expect none.
// (b) REQ-07 -- a simulated visit event with the app backgrounded, expect exactly one ping shown
//     as an Arrival.
// (c) REQ-05's fourth drain opportunity -- airplane mode, tap once so a ping queues, leave
//     airplane mode on, background the app, then drive a location wake and confirm the queued
//     ping drains WITHOUT any announcement (04-05).
// (d) SC-03 -- a full day with all three triggers on, read Settings > Battery for
//     GrokBotLocator's share and confirm it is under 5%. RESEARCH Q6 found significant-change to
//     be the least battery-friendly of the three, so it is the one to watch if this fails.

