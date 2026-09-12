import Foundation

/// The one object that owns every drain trigger this phase delivers (REQ-05, SC-02): hydrate the
/// history from the queue file at launch, drain on a foreground return, drain on a connectivity
/// edge while the process is alive, and drain -- without surfacing -- on a background wake.
/// Every trigger folds its result into the SAME `PingModel` the home screen renders, so the queue
/// and the visible history are one story, never two that can disagree.
///
/// `drainForeground()` is the NAMED entry point a later, automatic drain trigger must call --
/// this phase builds three of REQ-05's four drain opportunities (launch, foreground return,
/// connectivity edge) plus `drainBackground()` for a `BGAppRefreshTask` wake (wired in a later
/// plan in this phase). A location-triggered wake is a fourth opportunity REQ-05 names; it is
/// NOT delivered here -- it belongs to the automatic triggers a later phase owns, and when that
/// trigger lands it calls this same `drainForeground()`, which is why the method is `internal`
/// and named rather than folded into `start()`.
///
/// Nothing here prints, logs, names a coordinate, or reads the wall clock on its own -- every
/// notion of "now" comes from the injected `now` closure, so a test can hold time fixed or
/// advance it on demand.
@MainActor
final class QueueDrainCoordinator {
    /// The standing sentence a hydrated row reads until the next drain corrects it. Deliberately
    /// generic, not the original failure text a retry may have recorded days ago: a three-day-old
    /// "The webhook is unavailable (HTTP 503)" is no longer true, and this is the row a user sees
    /// immediately after a relaunch, before any send has been attempted again.
    private static let standingWaitingSentence =
        "Waiting to send. It will go out at the next opportunity."

    private let store: any PingQueueStoring
    private let drain: PingQueueDrain
    private let model: PingModel
    private let connectivity: any ConnectivityObserving
    private let now: @Sendable () -> Date

    /// Guards hydration to exactly once per session -- a later drain must never re-hydrate and
    /// overwrite a live row (already corrected by a real send) with the standing sentence above.
    private var hasHydrated = false
    /// The one connectivity-observing `Task`, started at most once and cancellable via `stop()`.
    private var connectivityTask: Task<Void, Never>?
    /// Explicit, app-set state: is a scene actually on screen right now? Defaults to `false` --
    /// a process that came up for a location event or a background refresh has nobody looking at
    /// it, and a coordinator that defaulted to "present" would announce on exactly the path this
    /// flag exists to silence. Never inferred here from a clock or a UIKit query; the scene-phase
    /// handler is the only writer, via `setUserPresent(_:)`.
    private var userIsPresent = false

    init(
        store: any PingQueueStoring,
        drain: PingQueueDrain,
        model: PingModel,
        connectivity: any ConnectivityObserving,
        now: @Sendable @escaping () -> Date
    ) {
        self.store = store
        self.drain = drain
        self.model = model
        self.connectivity = connectivity
        self.now = now
    }

    /// The manual-launch entry point (REQ-05's relaunch half): hydrate the history from whatever
    /// is on the queue file, attempt a foreground drain of anything due, and start listening for
    /// connectivity edges. Idempotent -- a second call re-runs the foreground drain and leaves
    /// hydration and the connectivity observer exactly as they were.
    func start() async {
        userIsPresent = true
        await hydrate()
        await drainForeground()
        if connectivityTask == nil {
            startObservingConnectivity()
        }
    }

    /// Records whether a scene is actually on screen -- called from the app's scene-phase
    /// handler, nothing else. Sets the flag and nothing more: no drain, no side effect. 04-13's
    /// handler already calls `drainForeground()` separately on `.active`, so triggering a drain
    /// from here too would double it.
    func setUserPresent(_ present: Bool) {
        userIsPresent = present
    }

    /// Restores whatever is on the queue file into the visible history, SILENTLY -- no badge, no
    /// VoiceOver announcement. A relaunch is not a tap: `PingAttemptFeedback.spoken` renders any
    /// non-`.sent` outcome as "Ping failed. " + reason, so announcing a launch hydration would
    /// tell the user a ping they never tapped had just failed. Runs at most once per session.
    private func hydrate() async {
        guard !hasHydrated else { return }
        hasHydrated = true

        guard let queued = try? await store.load() else {
            // The flag is set BEFORE the await so two concurrent launches cannot both hydrate,
            // but a failed load must not burn the session's one attempt: a launch before the
            // first unlock after a restart throws `.unavailable` here, and leaving `hasHydrated`
            // set meant the rows never came back at all until the app was relaunched. The queue
            // itself is intact either way.
            hasHydrated = false
            return
        }

        // `store.load()` returns the queue oldest first, and the queue's own capacity (200)
        // exceeds the history log's (50). Taking the trailing slice keeps the NEWEST entries --
        // still oldest-first within the slice -- and handing them to `model.apply` in that same
        // order lands them newest-first in the log, because `PingHistoryLog.record` inserts at
        // the front. This cap bounds only what is DISPLAYED: an entry pushed out of it is still
        // on the queue file and still drains on the next trigger, so SC-02 is unaffected by it.
        let capped = queued.suffix(PingHistoryLog.capacity)

        let updates = capped.map { entry -> PingDeliveryUpdate in
            if let reason = entry.permanentFailure {
                return PingDeliveryUpdate(
                    id: entry.id,
                    timestamp: entry.payload.capturedAt,
                    latitude: entry.payload.latitude,
                    longitude: entry.payload.longitude,
                    label: entry.payload.label,
                    outcome: .failed,
                    reason: reason)
            }
            return PingDeliveryUpdate(
                id: entry.id,
                timestamp: entry.payload.capturedAt,
                latitude: entry.payload.latitude,
                longitude: entry.payload.longitude,
                label: entry.payload.label,
                outcome: .queued,
                reason: Self.standingWaitingSentence)
        }

        model.apply(updates, announcing: false)
    }

    /// The NAMED entry point every automatic drain trigger calls -- launch, foreground return,
    /// a connectivity edge, and (04-11) a location wake. Failures are surfaced -- reported to the
    /// log AND, for an already-permanent one, deleted from the queue file now that it has
    /// actually been shown -- regardless of who is present. A budget of 25 seconds leaves
    /// headroom under the transport's own 30-second resource bound for one attempt while still
    /// returning control to the caller promptly.
    ///
    /// Announcing is conditional on `userIsPresent`, not unconditional as it was in phase 03:
    /// a location wake usually arrives with the app backgrounded or cold-launched, and this is
    /// the same method a launch and a foreground return also call, so it cannot simply announce
    /// always or never. This closes the LEARNINGS entry recorded against this file -- "a
    /// background-wake outcome sets `lastAttempt` and can announce a result for a tap the user
    /// never made" -- for the path phase 04 adds. `drainBackground()` is untouched: it already
    /// passes `announcing: false` unconditionally and has its own budget, because a
    /// `BGAppRefreshTask` wake has no notion of on-screen presence to ask.
    func drainForeground() async {
        let report = await drain.drain(
            before: now().addingTimeInterval(25), surfacingFailures: true)
        model.apply(report.updates, announcing: userIsPresent)
        if let notice = report.notice {
            model.show(notice: notice)
        }
    }

    /// A drain nobody is looking at -- a `BGAppRefreshTask` wake. `surfacingFailures: false`
    /// means an entry that gives up for good is reported into the log but stays on the queue
    /// file: there is nothing on screen to show it to yet, so nothing is deleted until a later
    /// foreground drain actually surfaces it. A 20-second budget, tighter than the foreground
    /// drain's: a background-task wake is handed only a few seconds by the system, and the
    /// transport's own 30-second resource bound already caps a single attempt, not the whole
    /// walk through the queue.
    func drainBackground() async {
        let report = await drain.drain(
            before: now().addingTimeInterval(20), surfacingFailures: false)
        // `announcing: false`, matching this method's own name and doc. It passed `true`, so a
        // background wake spoke an outcome for a tap nobody made -- and a retained permanent
        // failure re-announced on EVERY background drain until something surfaced it. The rows
        // still update; only the speaking is withheld until someone is actually looking.
        model.apply(report.updates, announcing: false)
        if let notice = report.notice {
            model.show(notice: notice)
        }
    }

    /// One long-running `Task` translating every online edge (REQ-05: "connectivity returning
    /// while the process is alive") into a foreground drain. `[weak self]` so the task itself --
    /// which only ever ends when cancelled -- does not keep this coordinator alive past its own
    /// usefulness.
    private func startObservingConnectivity() {
        connectivityTask = Task { [weak self] in
            guard let self else { return }
            for await _ in self.connectivity.onlineEdges() {
                await self.drainForeground()
            }
        }
    }

    /// Cancels the connectivity observer, if one is running. Nothing else here needs tearing
    /// down: hydration is a one-shot flag, and neither drain method holds anything open.
    func stop() {
        connectivityTask?.cancel()
        connectivityTask = nil
    }
}
