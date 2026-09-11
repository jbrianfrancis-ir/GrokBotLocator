import BackgroundTasks
import SwiftUI

/// The app's one composition root. Every concrete dependency the app has is constructed here
/// and nowhere else, so this is still the only place a concrete Keychain, URLSession,
/// CoreLocation or UserDefaults type is named: `PingSender`, `PingModel` and `SettingsModel`
/// each depend on `CredentialStore`, `LocationFixProvider`, `PingTransport`,
/// `PendingPingSink`, `PingLabelStore` and `PingSending` as protocols only
/// (ARCHITECTURE.md -- transport and storage are protocol-backed and injected).
///
/// The one bounded `URLSession` the app owns is built here too, like every other concrete
/// dependency. `URLSessionPingTransport.init(session:)` has no default for exactly this
/// reason: a default is how the app's session went back to an unbounded one before, so the
/// composition root must name the bounded session explicitly rather than let the transport
/// reacquire one by omission. The SAME transport instance reaches both `PingSender` (the ping
/// button) and `PingQueueDrain` (the drain) -- one bounded session, not one per consumer.
///
/// The explicit `init()` is structural, not stylistic. A `@State` property's default-value
/// expression cannot reference another property of the same struct, so two independent `@State`
/// initialisers could neither compile against each other nor share one `PingSender`. Building
/// the graph as locals and assigning through the underscored projections is what makes
/// `SettingsModel`'s Test connection and the ping button drive the SAME sender -- if they each
/// had their own, a passing Test connection would not prove the button works.
///
/// Phase 03 (REQ-05, SC-02) adds the durable queue: `FilePingQueueStore.applicationSupport()`
/// is built once and the SAME instance is handed to both `DurablePingSink` (what the ping
/// button writes through) and `PingQueueDrain` (what drains it) -- one actor over one file.
/// When Application Support is unavailable (`queue == nil`), the app falls all the way back
/// to phase 02's behaviour -- `UnqueuedPingSink` and no coordinator -- rather than claiming a
/// queue that does not exist: `PingSender`'s existing downgrade already turns a refused
/// enqueue into an honest `.permanentFailure`, never a false "Queued".
///
/// Phase 04 (REQ-05..10, SC-04) wires the automatic-trigger graph in, still as locals built here
/// and nowhere else: `LocationDelegateProxy` (significant-change/visits), `CLMonitorGeofence`
/// (the geofence region), `UserDefaultsTriggerSettingsStore` (the three switches and the
/// interval) and `AutomaticPinger`, all handed to one `TriggerCoordinator` -- the single
/// actor-isolated owner ARCHITECTURE requires for all location work. Two things are shared
/// rather than duplicated, both for the same reason as the transport instance above: the SAME
/// `PingRateLimiter` this file already builds for the manual path also reaches `AutomaticPinger`,
/// which is what makes SC-04's "4 pings a minute, manual and automatic together" true by
/// construction; and the SAME `CoreLocationFixProvider` (`fixes`) that serves a manual ping also
/// serves the geofence-exit trigger's one-shot fix, rather than a second provider. The trigger
/// coordinator is handed to `SettingsModel` as its `TriggerControlling` so the Settings toggles
/// actually reach it. `MapKitTriggerLabelProvider` -- the real reverse-geocoding label provider
/// (D-15) -- is what ships here; `EmptyTriggerLabelProvider` remains in the codebase as the
/// fallback and the test double, simply not what this file constructs. This file never imports
/// the MapKit framework: naming the provider type is permitted, importing the framework itself
/// is confined to that provider's own file (ARCHITECTURE Forbidden).
@main
struct GrokBotLocatorApp: App {
    @State private var pingModel: PingModel
    @State private var settingsModel: SettingsModel
    /// Nil when Application Support could not be opened -- see the header above. Present, this
    /// is the one object owning every drain trigger this phase delivers (launch, foreground
    /// return, connectivity edge, background refresh); phase 04's location-triggered wake is
    /// not one of them.
    @State private var coordinator: QueueDrainCoordinator?
    /// The one actor-isolated owner of every automatic trigger (REQ-06/07/08). Built
    /// unconditionally, whether or not `coordinator` above exists -- an unavailable Application
    /// Support disables the queue and the drain closure becomes a no-op, but the triggers still
    /// arm and still ping, matching phase 03's documented fallback shape.
    @State private var triggerCoordinator: TriggerCoordinator?

    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = KeychainCredentialStore()
        let fixes = CoreLocationFixProvider()
        let transport = URLSessionPingTransport(session: WebhookSession.make())

        let queue = try? FilePingQueueStore.applicationSupport()

        let pending: PendingPingSink
        if let queue {
            pending = DurablePingSink(store: queue, policy: .standard, now: { Date() })
        } else {
            pending = UnqueuedPingSink()
        }

        let sender = PingSender(
            credentials: store, fixes: fixes,
            transport: transport,
            pending: pending)
        // Built here, ahead of the gate below, so the interval already on disk is in force from
        // the very first claim -- `TriggerCoordinator.start()` is a foreground-only touchpoint
        // (see that type's header), so seeding at construction is what covers the manual button
        // and any launch that has not run `start()` yet.
        let triggerStore = UserDefaultsTriggerSettingsStore()
        // The one shared gate (REQ-09/SC-04): the manual path below and 04-10's AutomaticPinger
        // claim from the SAME instance, which is what makes "4 pings a minute, manual and
        // automatic together" true by construction rather than convention. Seeded from disk --
        // the limiter's own init already clamps, so no floor check belongs here.
        let rateLimiter = PingRateLimiter(minimumInterval: triggerStore.load().minimumIntervalSeconds)
        _pingModel = State(
            wrappedValue: PingModel(
                sender: sender, labelStore: UserDefaultsPingLabelStore(), fixes: fixes,
                rateLimiter: rateLimiter, now: { Date() }))

        if let queue {
            _coordinator = State(
                wrappedValue: QueueDrainCoordinator(
                    store: queue,
                    drain: PingQueueDrain(
                        store: queue, credentials: store, transport: transport,
                        policy: .standard, now: { Date() }),
                    model: _pingModel.wrappedValue,
                    connectivity: NWPathMonitorConnectivity(),
                    now: { Date() }))
        }

        // Phase 04's automatic-trigger graph -- see the header above. `proxy` and `geofence` are
        // the two CoreLocation-backed collaborators `TriggerCoordinator` drives; `triggerStore`
        // (built above, alongside the gate it seeds) persists the three switches and the
        // interval; `labels` is the shipping (D-15) reverse-geocoding provider, at its default
        // 3-second budget.
        let proxy = LocationDelegateProxy()
        let geofence = CLMonitorGeofence()
        let labels = MapKitTriggerLabelProvider()
        // Same `sender` the manual button uses (credentials, transport, classifier and durable
        // sink all shared) and the SAME `rateLimiter` above -- not a second one -- so SC-04's
        // ceiling counts manual and automatic pings together.
        let pinger = AutomaticPinger(
            sender: sender, labels: labels, rateLimiter: rateLimiter,
            model: _pingModel.wrappedValue, now: { Date() })
        // `queueCoordinator` is nil exactly when `coordinator` above is -- Application Support
        // unavailable -- and the closure then does nothing, which is the harmless no-op phase
        // 03's fallback requires: triggers still arm and still ping with no queue to drain.
        let queueCoordinator = _coordinator.wrappedValue
        let drain: @Sendable () async -> Void = { await queueCoordinator?.drainForeground() }
        _triggerCoordinator = State(
            wrappedValue: TriggerCoordinator(
                source: proxy, geofence: geofence, pinger: pinger,
                // The SAME `CoreLocationFixProvider` the manual path already uses -- the
                // geofence-exit path needs a one-shot fix and there is no reason for a second.
                fixes: fixes, settingsStore: triggerStore,
                // The SAME `rateLimiter` above -- not a second one -- so a minimum interval set
                // in Settings reaches the one gate the manual and automatic paths share.
                rateLimiter: rateLimiter, drain: drain))

        _settingsModel = State(
            wrappedValue: SettingsModel(
                store: store, sender: sender, triggers: _triggerCoordinator.wrappedValue))
    }

    var body: some Scene {
        WindowGroup {
            RootView(pingModel: pingModel, settingsModel: settingsModel)
                .task {
                    // Order matters: hydrate and drain the queue FIRST, so a trigger that fires
                    // immediately after launch is not racing the launch drain. `triggerCoordinator
                    // .start()` is the FOREGROUND touchpoint where Always may be armed (RESEARCH
                    // consequence 4: a `CLServiceSession` can only be started in the foreground) --
                    // it must never be called from `init()`.
                    await coordinator?.start()
                    await triggerCoordinator?.start()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        // Presence is set BEFORE the drain so this drain announces -- unlike a
                        // location wake, which must see `false` (below).
                        coordinator?.setUserPresent(true)
                        Task { await coordinator?.drainForeground() }
                    } else if phase == .background {
                        // `false` is the value a location wake must see: a process that comes up
                        // for a location event never passes through `.active`, so this is also
                        // 04-05's default and what keeps that drain silent.
                        coordinator?.setUserPresent(false)
                        scheduleRefresh()
                    } else if phase == .inactive {
                        coordinator?.setUserPresent(false)
                    }
                }
        }
        .backgroundTask(.appRefresh(QueueDrainTask.identifier)) {
            await coordinator?.drainBackground()
        }
    }

    /// Submits a `BGAppRefreshTaskRequest` for the next opportunistic drain, or does nothing at
    /// all when `QueueDrainTask.request` refuses to build one (no coordinator, or an empty
    /// identifier -- see that type's doc comment on what an empty identifier does and does not
    /// cover). A scheduling failure from `submit` is not shown to the user: the queue FILE is
    /// the durability mechanism, and the next foreground drain (launch or return) covers for a
    /// refresh that never ran, so failing loudly here would report a problem for something that
    /// is only ever supplementary (ARCHITECTURE.md).
    private func scheduleRefresh() {
        guard let request = QueueDrainTask.request(identifier: QueueDrainTask.identifier, from: Date())
        else { return }
        try? BGTaskScheduler.shared.submit(request)
    }
}

// MARK: - On-device verification (this phase's end-to-end runs the simulator cannot give)
//
// Phase 04's requirements are each written up with their own on-device reproduction steps where
// the behaviour actually lives, not restated here: REQ-06/07 in TriggerCoordinator.swift, REQ-08
// in GeofenceMonitor.swift, REQ-09 and REQ-10 in SettingsView.swift. The one this file owns is
// REQ-05's fourth drain opportunity end to end -- the location-wake drain this composition root
// is what actually wires up:
// 1. Turn on airplane mode.
// 2. Tap "I'm here" so a ping queues (it cannot send with no connectivity).
// 3. Leaving airplane mode ON, background the app.
// 4. Turn airplane mode off.
// 5. Drive a location wake (Xcode Debug > Simulate Location, or a real trigger on device).
// 6. Confirm the queued ping goes out with NO announcement while backgrounded, and that the
//    history row reads Sent when the app is next opened.

/// The app's one `BGAppRefreshTask` identifier, and the one place an empty identifier is turned
/// into "submit nothing" rather than a guessed string.
///
/// `.backgroundTask(.appRefresh(QueueDrainTask.identifier))` above is a `Scene` modifier, and
/// `SceneBuilder` offers no conditional form -- so scene REGISTRATION for this identifier is
/// unconditional, even on the day `identifier` reads `""`, and would register a background task
/// under a useless empty string. What `request(identifier:from:)` guards is SUBMISSION, not
/// registration: an empty identifier makes it return `nil`, so `BGTaskScheduler.shared.submit`
/// is never called and nothing is ever scheduled under a guessed or empty string. What keeps an
/// empty identifier out of a SHIPPED build in the first place is scripts/smoke.sh's
/// background-identifier guard, which reads the BUILT app's Info.plist and fails the gate
/// before it can ship -- not a runtime branch, because none exists at the scene level. Do not
/// read this type as proof the registration itself is conditional; it is not.
enum QueueDrainTask {
    /// Read back from the plist entry `project.yml`'s `BGTaskSchedulerPermittedIdentifiers`
    /// put there (03-11), never restated in source (ARCHITECTURE Forbidden: no bundle id in
    /// source). `""` when the key is missing, empty, or not an array of strings -- every one of
    /// those is treated the same way by `request(identifier:from:)` below: nothing submitted.
    static let identifier: String =
        (Bundle.main.object(forInfoDictionaryKey: "BGTaskSchedulerPermittedIdentifiers")
            as? [String])?.first ?? ""

    /// `nil` when `identifier` is empty -- no request is built and nothing is ever submitted
    /// under a guessed string. Otherwise a `BGAppRefreshTaskRequest` due no sooner than 15
    /// minutes out, matching `UIBackgroundModes: [fetch]`'s "opportunistic, not urgent" framing
    /// (ARCHITECTURE.md -- the refresh task is supplementary). A free function of its inputs, so
    /// the empty case is provable in a test (`QueueDrainTaskTests`) rather than only asserted in
    /// a comment.
    static func request(identifier: String, from now: Date) -> BGAppRefreshTaskRequest? {
        guard !identifier.isEmpty else { return nil }
        let request = BGAppRefreshTaskRequest(identifier: identifier)
        request.earliestBeginDate = now.addingTimeInterval(15 * 60)
        return request
    }
}
