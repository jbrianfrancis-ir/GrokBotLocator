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

    /// Whether the badge beside the button should render at all.
    ///
    /// `false` when the newest history row already says the same thing, which is the common
    /// case right after a tap: one row sits a few hundred points above the button carrying the
    /// same symbol, word and colour, and the badge is then the same outcome twice on one screen.
    /// It stays `true` on the paths that record no row -- a refused fix, a denied authorization
    /// -- where the badge is the ONLY report of what the tap did, which is what 02-12 added it
    /// for.
    ///
    /// Compares outcome and reason rather than an identifier: `PingAttemptFeedback` carries no
    /// entry id, and adding one would touch every construction site to answer a question about
    /// what is on screen. `sequence` is deliberately NOT compared -- it exists to make two
    /// identical outcomes distinct events for the announcement, and the question here is the
    /// opposite one, whether the row displays this same thing.
    var showsLastAttemptBadge: Bool {
        guard let attempt = lastAttempt else { return false }
        guard let newest = log.entries.first else { return true }
        return !(newest.outcome == attempt.outcome && newest.reason == attempt.reason)
    }

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
            // Live now that phase 03's queue answers `.queued` instead of `.notQueued`:
            // `PingSender` only downgrades a REFUSED enqueue to `.permanentFailure` before
            // returning, so by the time this arm is reached the sink has already accepted the
            // payload. `.queued` here means a ping something is actually holding, which is what
            // makes "no ping silently dropped" (ARCHITECTURE.md) hold in this direction too.
            outcome = .queued
            reason = r
        }

        if let fix = attempt.fix {
            log.record(
                PingHistoryEntry(
                    id: attempt.queuedID ?? UUID(), timestamp: fix.timestamp,
                    latitude: fix.latitude, longitude: fix.longitude,
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

    /// Folds a drain's delivery updates into the log. `announcing` is NOT defaulted: both call
    /// sites (03-10's `QueueDrainCoordinator`) must say which they mean, because getting it
    /// wrong is silent in review and loud on the device.
    ///
    /// Only `.sent` and `.failed` updates ever reach the announcing path -- 03-09's drain emits
    /// no `.queued` updates, because a still-waiting ping has not changed for the user -- which
    /// is why `PingAttemptFeedback.spoken`'s two-way split ("Ping sent." vs "Ping failed. " +
    /// reason) is adequate there and only there.
    ///
    /// - `announcing: true`: a drain the user is present for. Every update is applied to the
    ///   log, and `lastAttempt` is set once, for the LAST update only, at a fresh
    ///   `attemptSequence` -- a queued ping flipping to Sent is announced (DESIGN.md: outcomes
    ///   are announced, not just drawn) without narrating a ten-row drain one row at a time.
    /// - `announcing: false`: launch hydration. Every update is applied to the log, but
    ///   `lastAttempt` and `attemptSequence` are left UNTOUCHED. `spoken` renders any non-`.sent`
    ///   outcome as "Ping failed. " + reason, so announcing here would speak "Ping failed. " for
    ///   a queued row restored from disk -- a fact about the past, not an outcome of a tap the
    ///   user just made.
    ///
    /// Either mode: an empty `updates` array touches nothing at all, including `guidance` and
    /// `authorizationNotice` -- a drain that delivered nothing is not an event.
    func apply(_ updates: [PingDeliveryUpdate], announcing: Bool) {
        guard !updates.isEmpty else { return }
        for update in updates {
            log.apply(update)
        }
        // The WORST outcome in the batch, not the last one. A drain reports several pings at
        // once, and `updates.last` announced whichever happened to finish last: a queue of
        // [A rejected 401, B sent] said "Ping sent." and A's permanent rejection was never spoken
        // at all -- `showsLastAttemptBadge` then suppressed the badge too, because B's row is the
        // newest. A failure the user is never told about is the silent drop in another costume.
        guard announcing,
              let worst = updates.max(by: { Self.announcementRank($0.outcome) < Self.announcementRank($1.outcome) })
        else { return }
        attemptSequence += 1
        lastAttempt = PingAttemptFeedback(
            sequence: attemptSequence, outcome: worst.outcome, reason: worst.reason)
    }

    /// How loud an outcome is. `.failed` outranks `.queued` outranks `.sent`, so a batch
    /// announces the one the user most needs to hear.
    private static func announcementRank(_ outcome: PingOutcome) -> Int {
        switch outcome {
        case .sent: return 0
        case .queued: return 1
        case .failed: return 2
        }
    }

    /// The only way anything outside this file can put a drain sentence on screen -- `guidance`
    /// stays `private(set)` so no caller can otherwise clobber the authorization sentence
    /// `ping()` reconciles against it. A drain notice and the authorization notice are different
    /// things: this does not touch `authorizationNotice`, and the `guidance == authorizationNotice`
    /// de-duplication above is unchanged and still runs on the ping path only.
    func show(notice: String) {
        guidance = notice
    }
}
