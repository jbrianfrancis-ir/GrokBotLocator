import Foundation
import Testing
@testable import GrokBotLocator

/// `SettingsModel` and `PingModel` are both `@MainActor`, so constructing them to build a
/// `RootView` requires this test to be too. `service` is a throwaway string so this never
/// touches the app's own Keychain items (see `KeychainCredentialStore.init`), and `PingModel`
/// gets the file-private fakes below so the link check needs no location manager, no network
/// session, and no write into the test host's `UserDefaults`.
@MainActor
@Test func appModuleIsLinked() {
    let settingsModel = SettingsModel(
        store: KeychainCredentialStore(service: "smoke-test-appModuleIsLinked"))
    let pingModel = PingModel(
        sender: NoopPingSender(), labelStore: NoopPingLabelStore(), fixes: NoopFixProvider(),
        rateLimiter: NoopRateLimiter(), now: { Date() })
    let root = RootView(pingModel: pingModel, settingsModel: settingsModel)
    #expect(type(of: root) == RootView.self)
}

/// Never called by this test -- `RootView` is constructed, not rendered -- but a `PingModel`
/// cannot exist without all three collaborators.
private struct NoopPingSender: PingSending {
    func send(label: String) async -> PingAttempt {
        PingAttempt(fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
    }
}

private struct NoopPingLabelStore: PingLabelStore {
    func loadLabel() -> String { "" }
    func save(_ label: String) {}
}

private struct NoopFixProvider: LocationFixProvider {
    func currentFix() async throws -> LocationFix { throw LocationFixError.notAuthorized }
    func authorizationNotice() async -> String? { nil }
}

private struct NoopRateLimiter: PingRateLimiting {
    func claim(at now: Date) async -> RateLimitDecision { .allowed }
    func setMinimumInterval(_ seconds: TimeInterval) async {}
}
