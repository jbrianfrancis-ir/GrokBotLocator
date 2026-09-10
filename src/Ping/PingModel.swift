import Foundation
import Observation

/// The home screen's state machine (02-09-PLAN.md): label, in-flight, history, guidance,
/// authorization notice. No view, no network, no CoreLocation -- `PingSending`,
/// `PingLabelStore` and `LocationFixProvider` are all protocols, so every branch here is
/// testable with three fakes (see `PingModelTests`). Follows `SettingsModel`'s shape:
/// `@Observable @MainActor final class`, `private(set)` on everything the view only reads.
/// Plan 02-12 renders this; plan 02-13 constructs it with exactly the labels below.
@Observable
@MainActor
final class PingModel {
    private let sender: PingSending
    private let labelStore: PingLabelStore
    private let fixes: LocationFixProvider

    /// Written back to `labelStore` on every change (REQ-03's write half). Seeding this from
    /// `labelStore.loadLabel()` in `init` below goes through `@Observable`'s generated
    /// setter -- the macro rewrites `label` into a computed property -- so that seed DOES
    /// fire `didSet` and writes the just-loaded value straight back to the store. That is one
    /// redundant same-value write per launch and nothing more; accepted rather than reaching
    /// for a separate backing property just to dodge it.
    var label: String {
        didSet { labelStore.save(label) }
    }

    private(set) var isInFlight = false
    private(set) var log = PingHistoryLog()
    private(set) var guidance: String?
    private(set) var authorizationNotice: String?
    private(set) var lastAnnouncement: String?

    /// Argument labels and order are pinned -- 02-13's call site writes them verbatim.
    init(sender: PingSending, labelStore: PingLabelStore, fixes: LocationFixProvider) {
        self.sender = sender
        self.labelStore = labelStore
        self.fixes = fixes
        self.label = labelStore.loadLabel()
    }

    /// REQ-10: what the current authorization level does not allow, as a finished sentence,
    /// or nil when there is nothing to explain. The view calls this from `.task`; `ping()`
    /// also calls it after every attempt below, because a first ping is when the system
    /// prompt gets answered, so the notice can only be right afterwards.
    func refreshAuthorizationNotice() async {
        authorizationNotice = await fixes.authorizationNotice()
    }

    /// One tap, one POST: a second call while one is already in flight is ignored outright,
    /// so the sender is never invoked twice for one gesture.
    func ping() async {
        guard !isInFlight else { return }
        isInFlight = true
        defer { isInFlight = false }
        guidance = nil

        let attempt = await sender.send(label: label)

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
            // Phase 03 (REQ-05) turns this arm into `.queued` once the durable queue exists.
            // Until then there is nowhere durable to put it, so a retryable disposition is
            // recorded exactly like a permanent one -- `.failed`, with its reason -- which is
            // what keeps "no ping silently dropped" (ARCHITECTURE.md) true in this phase.
            outcome = .failed
            reason = r
        }
        let announcement = outcome == .sent ? "Ping sent." : "Ping failed. " + (reason ?? "")

        if let fix = attempt.fix {
            log.record(
                PingHistoryEntry(
                    timestamp: fix.timestamp, latitude: fix.latitude, longitude: fix.longitude,
                    label: label, outcome: outcome, reason: reason))
        } else {
            // No fix means no coordinates to list -- record nothing, and explain why instead.
            guidance = reason
        }

        lastAnnouncement = announcement

        await refreshAuthorizationNotice()
    }
}
