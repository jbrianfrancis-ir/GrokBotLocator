import Foundation

/// The one piece of ping state that persists between pings (REQ-03): the place name the user
/// last typed. `UserDefaults` is the right home for it -- ARCHITECTURE's Keychain-only rule
/// covers credentials, and a typed label is neither a credential nor a coordinate, so nothing
/// here is a violation. This is the app's only `UserDefaults` caller: `./scripts/smoke.sh`
/// greps for that and fails the build on a second one.
///
/// The protocol exists so the model above this store is tested with an in-memory fake, never
/// with real `UserDefaults` -- the store itself is what `PingHistoryTests` exercises directly,
/// against throwaway suites.
protocol PingLabelStore: Sendable {
    func loadLabel() -> String
    func save(_ label: String)
}

/// Backs `PingLabelStore` with `UserDefaults`, one key, nothing else.
///
/// `@unchecked Sendable`: `UserDefaults` is documented thread-safe but the SDK does not mark
/// it `Sendable`, so the compiler cannot check this automatically -- the override asserts
/// what Apple's documentation already guarantees, nothing more.
struct UserDefaultsPingLabelStore: PingLabelStore, @unchecked Sendable {
    private static let key = "ping.label"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Empty string on a fresh store -- never a placeholder and never another user's value,
    /// because each store is scoped to the `UserDefaults` instance it was handed.
    func loadLabel() -> String {
        defaults.string(forKey: Self.key) ?? ""
    }

    /// Writes the label under `ping.label` and nothing else.
    func save(_ label: String) {
        defaults.set(label, forKey: Self.key)
    }
}
