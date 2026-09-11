import Foundation

/// The persisted shape of REQ-09's per-trigger switches and rate limit, and REQ-10's answer to
/// "does anything need Always right now" -- `anyTriggerEnabled` is what 04-12's `SettingsModel`
/// checks before ever prompting for it, which is why every trigger below ships OFF: a fresh
/// install has nothing armed, so nothing asks.
///
/// The hard floor (SC-04: no more than 4 pings/minute, minimum spacing between pings) is defined
/// once, in `PingRateLimiter.hardFloor` -- this type never restates it as a literal. `minimumIntervalSeconds`
/// is `private(set)` for exactly one reason: the only writer is `setMinimumInterval`, which
/// clamps. A plain `var` is how an unclamped 5 gets in.
struct TriggerSettings: Sendable, Equatable {
    var significantChangeEnabled: Bool
    var visitsEnabled: Bool
    var geofenceEnabled: Bool
    private(set) var minimumIntervalSeconds: TimeInterval

    /// Every trigger off, interval at `PingRateLimiter.defaultInterval` -- what a fresh install
    /// (or an empty store) reads back as (REQ-10: no trigger armed means nothing asks for Always).
    static let initial = TriggerSettings(
        significantChangeEnabled: false,
        visitsEnabled: false,
        geofenceEnabled: false,
        minimumIntervalSeconds: PingRateLimiter.defaultInterval
    )

    init(
        significantChangeEnabled: Bool,
        visitsEnabled: Bool,
        geofenceEnabled: Bool,
        minimumIntervalSeconds: TimeInterval
    ) {
        self.significantChangeEnabled = significantChangeEnabled
        self.visitsEnabled = visitsEnabled
        self.geofenceEnabled = geofenceEnabled
        self.minimumIntervalSeconds = Self.clamped(minimumIntervalSeconds)
    }

    /// The only way to change the interval. Stores `max(seconds, PingRateLimiter.hardFloor)`;
    /// a non-finite input (`.nan`, `.infinity` with the wrong sign would still clamp via `max`,
    /// but NaN compares false against everything) lands on the floor too.
    mutating func setMinimumInterval(_ seconds: TimeInterval) {
        minimumIntervalSeconds = Self.clamped(seconds)
    }

    private static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return PingRateLimiter.hardFloor }
        return max(seconds, PingRateLimiter.hardFloor)
    }

    /// True when any of the three triggers is on -- what 04-12 checks before requesting Always.
    var anyTriggerEnabled: Bool {
        significantChangeEnabled || visitsEnabled || geofenceEnabled
    }
}
