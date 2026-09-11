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
    private let drain: @Sendable () async -> Void

    private var settings: TriggerSettings
    /// Where the last ping happened. `nil` until the first ping ever goes out, or right after a
    /// cold background relaunch before the significant-change handler (added in a later task)
    /// rehydrates it from the geofence monitor's own durable record (this app keeps no second
    /// coordinate file of its own -- D-12 reserves that role for the offline queue alone).
    private var reference: TriggerCoordinate?
    private var alwaysWasRequested = false
    /// The tail of the serialized chain the trigger handlers (added in a later task) append onto.
    /// Declared here so `settled()` below compiles before those handlers exist.
    private var chain: Task<Void, Never>?

    init(
        source: any LocationTriggerSource,
        geofence: any GeofenceMonitoring,
        pinger: any AutomaticPinging,
        fixes: any LocationFixProvider,
        settingsStore: any TriggerSettingsStoring,
        drain: @escaping @Sendable () async -> Void
    ) {
        self.source = source
        self.geofence = geofence
        self.pinger = pinger
        self.fixes = fixes
        self.settingsStore = settingsStore
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

    /// The completion signal for the serialized chain a later task introduces. A handler will
    /// return as soon as its work is QUEUED onto `chain`, not once it has run, so a caller that
    /// wants to know whether a drain/gate/ping actually finished must await this afterward.
    func settled() async {
        await chain?.value
    }

    /// Read-only window onto `reference` for tests -- `reference` itself stays `private` because
    /// this is the one piece of state the reentrancy tests need to observe, not a second way to
    /// mutate it.
    func currentReference() async -> TriggerCoordinate? {
        reference
    }

    // Stubs so `start()` above compiles while the handlers are wired in -- a later task replaces
    // each body with the real drain-first, gate-checked logic and adds the serialized chain that
    // protects the reference-coordinate read-modify-write across them.
    func handleSignificantChange(_ report: SignificantChangeReport) async {}

    func handleVisit(_ report: VisitReport) async {}

    func handleGeofenceExit(at date: Date) async {}
}
