import SwiftUI

/// The app's one composition root. Every concrete dependency the app has is constructed here
/// and nowhere else, so this is still the only place a concrete Keychain, URLSession,
/// CoreLocation or UserDefaults type is named: `PingSender`, `PingModel` and `SettingsModel`
/// each depend on `CredentialStore`, `LocationFixProvider`, `PingTransport`,
/// `PendingPingSink`, `PingLabelStore` and `PingSending` as protocols only
/// (ARCHITECTURE.md -- transport and storage are protocol-backed and injected).
///
/// The explicit `init()` is structural, not stylistic. A `@State` property's default-value
/// expression cannot reference another property of the same struct, so two independent `@State`
/// initialisers could neither compile against each other nor share one `PingSender`. Building
/// the graph as locals and assigning through the underscored projections is what makes
/// `SettingsModel`'s Test connection and the ping button drive the SAME sender -- if they each
/// had their own, a passing Test connection would not prove the button works.
@main
struct GrokBotLocatorApp: App {
    @State private var pingModel: PingModel
    @State private var settingsModel: SettingsModel

    init() {
        let store = KeychainCredentialStore()
        let fixes = CoreLocationFixProvider()
        let sender = PingSender(
            credentials: store, fixes: fixes, transport: URLSessionPingTransport(),
            pending: UnqueuedPingSink())
        _pingModel = State(
            wrappedValue: PingModel(
                sender: sender, labelStore: UserDefaultsPingLabelStore(), fixes: fixes))
        _settingsModel = State(wrappedValue: SettingsModel(store: store, sender: sender))
    }

    var body: some Scene {
        WindowGroup {
            RootView(pingModel: pingModel, settingsModel: settingsModel)
        }
    }
}
