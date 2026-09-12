import Foundation

/// Whether an automatic trigger actually produced a ping. 04-11's `TriggerCoordinator` reads
/// this to decide whether to advance its reference coordinate and re-register a geofence --
/// both of those must happen only when a ping actually went out or is held for delivery, never
/// on a rate-limited or misconfigured attempt that sent nothing, and (D-21) never on a
/// `.pinged(.failed)` either: the carried `PingOutcome` is what lets the coordinator tell a
/// delivered-or-queued ping from one that is gone.
enum AutomaticPingResult: Sendable, Equatable {
    case pinged(PingOutcome)
    case rateLimited
    case noCredentialsOrFix
}

/// The seam `TriggerCoordinator` (04-11) depends on, so it never couples to the concrete
/// `AutomaticPinger` (ARCHITECTURE: transport and storage are protocol-backed and injected --
/// the same discipline applies here).
protocol AutomaticPinging: Sendable {
    func ping(fix: LocationFix, trigger: PingTrigger) async -> AutomaticPingResult
}

/// What actually sends a ping when a trigger fires: one fix already in hand, a geocoded-or-empty
/// label, the shared rate gate, and the same sender, queue and history the manual tap uses.
/// `@MainActor` because it folds results into `PingModel`, which is itself `@MainActor`.
///
/// Nothing here acquires a fix, reads the typed manual label, sleeps, or reads the wall clock
/// directly -- the trigger already carries a fix (ARCHITECTURE's Forbidden continuous-GPS entry
/// is exactly what starting a fresh location session here would reintroduce), the label comes
/// from the injected `TriggerLabelProviding`, and `now` is always the injected clock so every
/// schedule stays testable without sleeping.
@MainActor
final class AutomaticPinger: AutomaticPinging {
    private let sender: any PingSending
    private let labels: any TriggerLabelProviding
    private let rateLimiter: any PingRateLimiting
    private let model: PingModel
    private let now: @Sendable () -> Date

    /// No defaults: the composition root (04-13) must name every collaborator explicitly,
    /// `rateLimiter` above all -- it has to be the SAME instance `PingModel`'s manual path
    /// claims from, or SC-04's "4 pings per minute counting manual and automatic together"
    /// is false.
    init(
        sender: any PingSending, labels: any TriggerLabelProviding,
        rateLimiter: any PingRateLimiting, model: PingModel, now: @escaping @Sendable () -> Date
    ) {
        self.sender = sender
        self.labels = labels
        self.rateLimiter = rateLimiter
        self.model = model
        self.now = now
    }

    func ping(fix: LocationFix, trigger: PingTrigger) async -> AutomaticPingResult {
        // The one gate REQ-09/SC-04 counts manual and automatic pings through together. Unlike
        // the MANUAL refusal in `PingModel` -- which DOES tell the user, because a person tapped
        // and is waiting -- nothing here is sent, nothing is logged, and nothing is queued: an
        // event the user never initiated is not a ping that was dropped, there was no ping.
        switch await rateLimiter.claim(at: now()) {
        case .tooSoon:
            return .rateLimited
        case .allowed:
            break
        }

        let label = normalisedTriggerLabel(await labels.label(for: TriggerCoordinate(fix: fix)))
        let attempt = await sender.send(label: label, using: fix)

        let outcome: PingOutcome
        let reason: String?
        switch attempt.disposition {
        case .sent:
            outcome = .sent
            reason = nil
        case .permanentFailure(let r):
            outcome = .failed
            reason = r
        case .retryable(let r):
            outcome = .queued
            reason = r
        }

        let update = PingDeliveryUpdate(
            id: attempt.queuedID ?? UUID(), timestamp: fix.timestamp, latitude: fix.latitude,
            longitude: fix.longitude, label: label, outcome: outcome, reason: reason,
            trigger: trigger)
        // This is never the announcing mode: `PingAttemptFeedback.spoken` renders every non-sent
        // outcome as "Ping failed. …", a sentence about a tap -- and no tap happened here (04-05
        // settled the same question for the drain).
        model.apply([update], announcing: false)

        if case .permanentFailure(let r) = attempt.disposition,
            r == "Add your webhook URL and sender key in Settings before pinging."
        {
            return .noCredentialsOrFix
        }
        return .pinged(outcome)
    }
}
