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
    /// D-16's second sanctioned coordinate store -- the single last-ping position, overwritten
    /// never appended. Optional for one reason only: Application Support can be unavailable, the
    /// same case that already makes `queueCoordinator` nil at the composition root; a nil store
    /// is a no-op there too, never a second in-memory conformer standing in for it.
    private let lastPing: (any LastPingStoring)?
    /// The seam between the stored interval and the enforcer (REQ-09's gap): `applySettings`
    /// carries `s.minimumIntervalSeconds` here on every entry, and this type never restates the
    /// floor or the default -- `setMinimumInterval`'s own clamp is the only one that applies.
    private let rateLimiter: any PingRateLimiting
    private let drain: @Sendable () async -> Void

    private var settings: TriggerSettings
    /// Where the last ping happened. `nil` until the first ping ever goes out, or until
    /// `recoverReferenceIfNeeded()` rehydrates it. Two durable records can supply that recovery,
    /// read in this order: this app's own last-ping file (D-16, `lastPing`), then the region
    /// `CLMonitor` itself still holds (`geofence.currentCentre()`) -- see that helper.
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
        lastPing: (any LastPingStoring)?,
        rateLimiter: any PingRateLimiting,
        drain: @escaping @Sendable () async -> Void
    ) {
        self.source = source
        self.geofence = geofence
        self.pinger = pinger
        self.fixes = fixes
        self.settingsStore = settingsStore
        self.lastPing = lastPing
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

    /// Holds the Always service session whenever at least one trigger is enabled, and REQUESTS
    /// Always only when the app is not already authorized for it (REQ-10: neither happens at
    /// launch with all three off -- see the two-call split below). The three start/stop
    /// calls and the geofence registration are independent of whether that request succeeded --
    /// a refusal is reported through `authorizationNotice()`, not by silently leaving a trigger
    /// that IS switched on in Settings unarmed.
    private func applySettings(_ s: TriggerSettings) async {
        // FIRST -- above the Always request, so a refusal cannot skip it. Both entries into this
        // function carry the stored interval to the gate: `start()` (the value just loaded from
        // disk) and `update(_:)` (the value a Settings change just persisted).
        await rateLimiter.setMinimumInterval(s.minimumIntervalSeconds)

        if s.anyTriggerEnabled {
            // UNCONDITIONAL, above the request below (debug/001 -- REQ-08's runtime gap). An
            // Always GRANT is durable across launches; the `CLServiceSession` that makes that
            // grant effective is not -- it dies with the process. Gating session creation on
            // "not already Always", as this did until now, meant a cold relaunch of an app that
            // had been granted Always took NEITHER branch: nothing to request, so no session
            // either, so RESEARCH Q2/Q5's "Always authorization will only be effective when you
            // hold one of these" was never satisfied and no geofence exit was ever delivered.
            // `start()` is a foreground touchpoint (see this type's header), which is what makes
            // creating the session here legal at all.
            await source.beginAlwaysSession()

            // The PROMPT, still gated -- there is nothing to ask an already-authorized user, and
            // `alwaysWasRequested` drives `authorizationNotice()`, so it must keep meaning "we
            // actually asked" rather than "a trigger is on".
            if await source.currentAuthorization() != .authorizedAlways {
                _ = await source.requestAlways()
                alwaysWasRequested = true
            }
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
            // recoverReferenceIfNeeded() ABOVE the register condition is what closes REQ-08's
            // cold-relaunch gap: in a geofence-only configuration `runSignificantChange` never
            // runs, so this was the ONLY place able to notice `reference` is nil, and until D-16
            // it had nothing but `geofence.currentCentre()` to recover from -- nothing if no
            // region survived the relaunch. Reading `centre` here (not a second
            // `geofence.currentCentre()` call below) means recovery and the register condition
            // see the SAME value from the SAME turn.
            let centre = await recoverReferenceIfNeeded()
            // Registers whenever the region is not ALREADY centred on the reference -- which
            // covers two distinct cases, not one:
            //
            // 1. `centre == nil` -- nothing registered. Exactly what recovery-from-file (D-16)
            //    produces when no region survived the relaunch: `reference` is now the file's
            //    coordinate, so this arms the geofence-only cold start (04-15's gap).
            // 2. `centre != reference` -- a region survived, but centred somewhere ELSE. This
            //    condition used to read `centre == nil` alone, which treated "a region exists"
            //    as "the right region exists" and left a STALE region uncorrected: the app went
            //    on watching a point it had already left, and since a region you are already
            //    outside of never produces an exit TRANSITION, REQ-08 could never fire again for
            //    the life of that region. Found by driving the simulator repro (debug/002), not
            //    by review -- 04-15's `aColdStartWithOnlyTheGeofenceEnabledRecoversTheReference`
            //    asserts `registrations.count == 1`, so the suite actively pinned the old
            //    behaviour.
            //
            // Still nothing to register before the first ping has ever gone out: a nil
            // `reference` registers nothing at all.
            //
            // Equality is exact, deliberately: a tolerance would be a new numeric constant this
            // file has no authority to invent (see `radiusMetres`'s backstop note). If a device
            // turns out to round-trip `condition.center` inexactly, this re-registers on every
            // arming pass -- idempotent under the single fixed identifier, but it also resets the
            // region's inside/outside baseline, so the tolerance question is a decision to rule,
            // not to guess. Recorded in debug/002.
            if let reference, centre != reference {
                await geofence.register(at: reference)
            }
        } else {
            await geofence.unregister()
        }

        // D-16 condition 4: nothing is watching, so nothing needs the position, in memory or on
        // disk. Last, so every disable branch above has already run.
        if !s.anyTriggerEnabled {
            await lastPing?.clear()
            reference = nil
        }
    }

    /// The ONE place `reference` is recovered, reading the two durable records D-16 leaves in
    /// order: this app's own last-ping file first, then the region `CLMonitor` itself still
    /// holds. Both `start()` (via `runSignificantChange`, still called there for a wake this
    /// process is already handling) and `applySettings`'s geofence branch reach it through this
    /// single definition -- never two copies that can drift.
    ///
    /// The double unwrap in `(await lastPing?.load() ?? nil) ?? centre` is REQUIRED, not
    /// simplifiable. `lastPing` is `(any LastPingStoring)?` and `load()` itself returns
    /// `TriggerCoordinate?`, so `await lastPing?.load()` is `TriggerCoordinate??` -- optional
    /// chaining wraps the awaited result in one more layer of Optional. The naive
    /// `await lastPing?.load() ?? centre` unwraps only the OUTER optional: a store that EXISTS
    /// but is EMPTY produces `.some(nil))`, which is already non-nil at the outer layer, so
    /// `centre` is never reached and the result is the inner `nil` -- exactly the geofence-only,
    /// nothing-ever-pinged-yet cold start this fix exists for. `?? nil` collapses that inner
    /// optional first, so a genuinely empty file correctly falls through to `centre`.
    @discardableResult
    private func recoverReferenceIfNeeded() async -> TriggerCoordinate? {
        let centre = await geofence.currentCentre()
        if reference == nil {
            reference = (await lastPing?.load() ?? nil) ?? centre
        }
        return centre
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
        // Cold-relaunch rehydration -- the ONE definition, shared with `applySettings`'s
        // geofence branch, so this and that never drift into two copies.
        await recoverReferenceIfNeeded()
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
        // D-16: overwrite the durable record in place, above the geofence re-registration below,
        // so only a real `.pinged` result ever moves it -- same guard as `reference` itself.
        await lastPing?.save(coordinate)
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

