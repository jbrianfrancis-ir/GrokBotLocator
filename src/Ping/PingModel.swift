import Foundation
import Observation

/// What the last tap did: one value meaning one attempt, carrying the outcome, its reason, and a
/// sequence number. One property rather than several, because the outcome has to reach three
/// places that must never disagree -- the badge pinned by the button, the spoken announcement,
/// and (on the no-fix path) the sentence in the content. It also makes two identical outcomes
/// distinct values: keyed off the text alone, a second "Ping sent." was not a change and was
/// never spoken.
struct PingAttemptFeedback: Equatable, Sendable {
    let sequence: Int
    let outcome: PingOutcome
    let reason: String?

    /// What VoiceOver says. Carries the reason, because "Ping failed." alone tells the user
    /// nothing about what to do next (DESIGN.md).
    var spoken: String {
        outcome == .sent ? "Ping sent." : "Ping failed. " + (reason ?? "")
    }
}

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
    /// The single "what the last tap did" value -- see `PingAttemptFeedback`. The view renders it
    /// as a badge inside the bottom inset beside the button AND announces it; before that, the
    /// only change in the bottom third was the button's label reverting, which is pixel-identical
    /// to a tap that did nothing.
    private(set) var lastAttempt: PingAttemptFeedback?
    private var attemptSequence = 0

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
            // UNREACHABLE in the shipped app while `UnqueuedPingSink` is the sink: it always
            // answers `.notQueued`, so `PingSender` downgrades every retryable to a permanent
            // failure before this switch sees it. Phase 03's queue answers `.queued`, which makes
            // this arm live and is where it becomes `.queued` on screen (REQ-05). Recording it as
            // `.failed` with its reason is what keeps "no ping silently dropped"
            // (ARCHITECTURE.md) true either way -- a ping nothing holds is never called pending.
            outcome = .failed
            reason = r
        }

        if let fix = attempt.fix {
            log.record(
                PingHistoryEntry(
                    timestamp: fix.timestamp, latitude: fix.latitude, longitude: fix.longitude,
                    label: label, outcome: outcome, reason: reason))
        } else {
            // No fix means no coordinates to list -- record nothing, and explain why instead.
            guidance = reason
        }

        await refreshAuthorizationNotice()

        // One sentence per state. An authorization failure sets `guidance` to the very sentence
        // the standing notice already shows, and rendering both stacked them -- at AX5 each
        // block is tall, and before the sentences were unified they actively disagreed about
        // what happened. The notice is the durable one, so the duplicate guidance goes.
        if let guidance, guidance == authorizationNotice {
            self.guidance = nil
        }

        attemptSequence += 1
        lastAttempt = PingAttemptFeedback(
            sequence: attemptSequence, outcome: outcome, reason: reason)
    }
}
