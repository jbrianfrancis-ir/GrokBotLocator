import SwiftUI

/// Injects the one real `KeychainCredentialStore` the app ever constructs into one
/// `SettingsModel`, then hands that to `RootView`. `SettingsModel` depends on the
/// `CredentialStore` protocol only, so this is the only place a concrete Keychain
/// implementation gets named.
@main
struct GrokBotLocatorApp: App {
    @State private var settingsModel = SettingsModel(store: KeychainCredentialStore())

    var body: some Scene {
        WindowGroup {
            RootView(settingsModel: settingsModel)
        }
    }
}
