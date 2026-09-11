import Foundation

/// Second exemption in `./scripts/smoke.sh`'s `UserDefaults` guard, alongside
/// `PingLabelStore.swift` -- three per-trigger switches and one interval, none of them a
/// credential or a coordinate, so ARCHITECTURE's secure-storage rule and its ban on location
/// data in `UserDefaults` are both untouched. Nothing in this file ever stores a map position,
/// a transport endpoint, or an auth secret; that boundary is what the guard exists to hold,
/// not what it forbids naming in a comment.
///
/// The protocol exists so `SettingsModel` (04-12) and `TriggerCoordinator` (04-11) depend on a
/// seam, never on `UserDefaults` directly -- the same discipline `PingLabelStore` set.
protocol TriggerSettingsStoring: Sendable {
    func load() -> TriggerSettings
    func save(_ settings: TriggerSettings)
}

/// Backs `TriggerSettingsStoring` with `UserDefaults`, four keys, nothing else.
///
/// `@unchecked Sendable`: `UserDefaults` is documented thread-safe but the SDK does not mark it
/// `Sendable`, so the compiler cannot check this automatically -- the override asserts what
/// Apple's documentation already guarantees, nothing more (the same reasoning `PingLabelStore`
/// uses for its own conformer).
struct UserDefaultsTriggerSettingsStore: TriggerSettingsStoring, @unchecked Sendable {
    private static let significantChangeKey = "triggers.significantChange"
    private static let visitsKey = "triggers.visits"
    private static let geofenceKey = "triggers.geofence"
    private static let minimumIntervalKey = "triggers.minimumIntervalSeconds"

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// Absent booleans read `false`, matching `TriggerSettings.initial`. The interval is read
    /// with `object(forKey:) as? Double` rather than `double(forKey:)` so an ABSENT key (fresh
    /// install) is distinguishable from a stored `0.0` (hand-edited or, pre-clamp, legitimately
    /// written): absent falls back to `PingRateLimiter.defaultInterval`, present goes through
    /// `TriggerSettings.init`, which re-applies the floor -- so a hand-edited value below it
    /// comes back clamped rather than honoured. The clamp lives in exactly one place
    /// (`TriggerSettings`), not restated here.
    func load() -> TriggerSettings {
        let interval = (defaults.object(forKey: Self.minimumIntervalKey) as? Double)
            ?? PingRateLimiter.defaultInterval
        return TriggerSettings(
            significantChangeEnabled: defaults.bool(forKey: Self.significantChangeKey),
            visitsEnabled: defaults.bool(forKey: Self.visitsKey),
            geofenceEnabled: defaults.bool(forKey: Self.geofenceKey),
            minimumIntervalSeconds: interval
        )
    }

    /// Writes all four keys. `settings.minimumIntervalSeconds` is already clamped by
    /// `TriggerSettings` itself, so this never needs to re-clamp on the way out.
    func save(_ settings: TriggerSettings) {
        defaults.set(settings.significantChangeEnabled, forKey: Self.significantChangeKey)
        defaults.set(settings.visitsEnabled, forKey: Self.visitsKey)
        defaults.set(settings.geofenceEnabled, forKey: Self.geofenceKey)
        defaults.set(settings.minimumIntervalSeconds, forKey: Self.minimumIntervalKey)
    }
}
