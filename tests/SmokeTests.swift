import Testing
@testable import GrokBotLocator

/// `SettingsModel` is `@MainActor`, so constructing one to build a `RootView` requires this
/// test to be too. `service` is a throwaway string so this never touches the app's own
/// Keychain items (see `KeychainCredentialStore.init`).
@MainActor
@Test func appModuleIsLinked() {
    let model = SettingsModel(store: KeychainCredentialStore(service: "smoke-test-appModuleIsLinked"))
    let root = RootView(settingsModel: model)
    #expect(type(of: root) == RootView.self)
}
