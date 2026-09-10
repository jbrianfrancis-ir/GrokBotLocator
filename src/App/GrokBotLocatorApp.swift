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
@main
struct GrokBotLocatorApp: App {
    @State private var pingModel: PingModel
    @State private var settingsModel: SettingsModel
    /// Nil when Application Support could not be opened -- see the header above. Present, this
    /// is the one object owning every drain trigger this phase delivers (launch, foreground
    /// return, connectivity edge, background refresh); phase 04's location-triggered wake is
    /// not one of them.
    @State private var coordinator: QueueDrainCoordinator?

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
        _pingModel = State(
            wrappedValue: PingModel(
                sender: sender, labelStore: UserDefaultsPingLabelStore(), fixes: fixes))
        _settingsModel = State(wrappedValue: SettingsModel(store: store, sender: sender))

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
    }

    var body: some Scene {
        WindowGroup {
            RootView(pingModel: pingModel, settingsModel: settingsModel)
                .task { await coordinator?.start() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        Task { await coordinator?.drainForeground() }
                    } else if phase == .background {
                        scheduleRefresh()
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
