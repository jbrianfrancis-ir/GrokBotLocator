import Foundation

/// The single gate in front of every send path -- manual and automatic together (REQ-09,
/// SC-04). One `PingRateLimiter` instance built at the composition root (04-13) is shared by
/// `PingModel`'s manual path (04-09) and `AutomaticPinger` (04-10): nothing in this type
/// distinguishes a caller, which is what makes "manual and automatic share one window" true by
/// construction rather than by convention.
///
/// Two decisions here are BACKSTOP -- not derived from REQUIREMENTS.md -- until a human states
/// the rule; a later reader should not mistake either for a settled derivation (a test pinning
/// a choice is not the same as a rule, .planning/LEARNINGS.md):
/// - A claim landing EXACTLY `interval` after the last allowed one is ALLOWED (`>=`, not `>`).
///   REQ-09 says "minimum-interval" and SC-04 says ">= 15 s spacing"; both readings of the
///   boundary are defensible and nothing settles which.
/// - A slot is consumed at claim time, so a ping that is claimed and then FAILS to send (no
///   credentials, transport error, queued offline) still holds the window against the next
///   trigger. Requirements speak of pings that "reach the routine" and never say whether a
///   failed attempt counts; releasing the slot on failure is equally defensible.

/// What a claim against the limiter resolved to.
enum RateLimitDecision: Sendable, Equatable {
    case allowed
    case tooSoon(retryAfter: TimeInterval, reason: String)
}

/// The seam `PingModel` and `AutomaticPinger` depend on, so neither couples to the concrete
/// actor directly (ARCHITECTURE: transport and storage are protocol-backed and injected --
/// the same discipline applies to the gate in front of them).
protocol PingRateLimiting: Sendable {
    func claim(at now: Date) async -> RateLimitDecision
    func setMinimumInterval(_ seconds: TimeInterval) async
}

/// The single shared gate. No clock, no timer of its own: `now` always arrives as a parameter,
/// so every schedule is testable instantly -- the house pattern set by `PingRetryPolicy`
/// (src/Queue/PingRetryPolicy.swift).
actor PingRateLimiter: PingRateLimiting {
    static let hardFloor: TimeInterval = 15
    static let defaultInterval: TimeInterval = 60

    private var interval: TimeInterval
    private var lastAllowed: Date?

    init(minimumInterval: TimeInterval = PingRateLimiter.defaultInterval, lastAllowed: Date? = nil) {
        self.interval = Self.clamped(minimumInterval)
        self.lastAllowed = lastAllowed
    }

    /// Clamped, never rejected: REQ-09 says the interval "cannot be set below 15 s", and a
    /// silently ignored setter would leave Settings showing a value the limiter is not using.
    /// A NaN or negative input also lands on the floor.
    func setMinimumInterval(_ seconds: TimeInterval) {
        interval = Self.clamped(seconds)
    }

    private static func clamped(_ seconds: TimeInterval) -> TimeInterval {
        guard seconds.isFinite else { return hardFloor }
        return max(seconds, hardFloor)
    }

    /// The read-modify-write at the heart of the gate. It contains no suspension point at all:
    /// an actor serializes entry, not a call, and is reentrant at every `await` inside its body
    /// (.planning/LEARNINGS.md -- three read-modify-write holes shipped in `PingQueueDrain` of
    /// exactly this shape, invisible to a suite where every fake returns without suspending).
    /// Because this function never suspends, concurrent callers queue on actor entry and run
    /// this body one at a time with no interleaving possible. A future edit that adds a
    /// suspension point here -- an `await` of any kind -- reopens that hole.
    func claim(at now: Date) -> RateLimitDecision {
        if let lastAllowed, now.timeIntervalSince(lastAllowed) < interval {
            let retryAfter = interval - now.timeIntervalSince(lastAllowed)
            let reason = "Too soon -- pings are spaced at least \(Int(interval)) seconds apart. " +
                "Try again in \(Int(ceil(retryAfter))) seconds."
            return .tooSoon(retryAfter: retryAfter, reason: reason)
        }
        lastAllowed = now
        return .allowed
    }
}
