import Foundation
import Testing
@testable import GrokBotLocator

/// Proves `PingModel`'s state machine with no view, no network and no CoreLocation: label
/// memory round-trips through a fake `PingLabelStore`, `isInFlight` brackets exactly one
/// `ping()` at a time, a delivered attempt records one `.sent` row and a rejected one records
/// one `.failed` row with its reason, a fix-less attempt records nothing and sets `guidance`
/// instead, and every outcome sets `lastAnnouncement` (DESIGN.md -- announced, not just drawn).
@MainActor
@Suite
struct PingModelTests {

    // MARK: Fakes

    /// Replays a caller-set `PingAttempt` and can suspend inside `send(label:)` until the
    /// test calls `release()`, so the in-flight window is directly observable.
    ///
    /// `PingSending.send` is a nonisolated async requirement, so its body runs OFF this
    /// `@MainActor` suite while `release()` runs on it -- every field here is therefore
    /// lock-guarded rather than merely sequential. `release()` is also order-independent: it
    /// latches `released`, so a test that calls it before `send` reaches
    /// `withCheckedContinuation` still resumes the call. Without that latch the suite hung
    /// intermittently (2 runs in 5): `callCount` is bumped BEFORE the continuation is stored,
    /// so a test spinning on `callCount` could release into a nil continuation and nothing
    /// would ever resume it.
    private final class FakeSender: PingSending, @unchecked Sendable {
        private let lock = NSLock()
        private var _attemptToReturn = PingAttempt(
            fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
        private var _shouldSuspend = false
        private var _callCount = 0
        private var _labels: [String] = []
        private var continuation: CheckedContinuation<Void, Never>?
        private var released = false

        var attemptToReturn: PingAttempt {
            get { lock.withLock { _attemptToReturn } }
            set { lock.withLock { _attemptToReturn = newValue } }
        }

        var shouldSuspend: Bool {
            get { lock.withLock { _shouldSuspend } }
            set { lock.withLock { _shouldSuspend = newValue } }
        }

        var callCount: Int { lock.withLock { _callCount } }
        var labels: [String] { lock.withLock { _labels } }

        func send(label: String) async -> PingAttempt {
            let suspend: Bool = lock.withLock {
                _callCount += 1
                _labels.append(label)
                return _shouldSuspend
            }
            if suspend {
                await withCheckedContinuation { c in
                    let resumeNow: Bool = lock.withLock {
                        if released { return true }
                        continuation = c
                        return false
                    }
                    if resumeNow { c.resume() }
                }
            }
            return attemptToReturn
        }

        /// Resumes a call suspended by `shouldSuspend`, letting `ping()` complete. Safe to call
        /// before `send` has suspended -- the `released` latch makes the order irrelevant.
        func release() {
            let c: CheckedContinuation<Void, Never>? = lock.withLock {
                released = true
                let pending = continuation
                continuation = nil
                return pending
            }
            c?.resume()
        }
    }

    /// In-memory stand-in for `UserDefaultsPingLabelStore`: seeded with a caller-set label,
    /// and records every value `save` is handed.
    private final class FakeLabelStore: PingLabelStore, @unchecked Sendable {
        private var label: String
        private(set) var savedValues: [String] = []

        init(initialLabel: String) {
            label = initialLabel
        }

        func loadLabel() -> String { label }

        func save(_ newLabel: String) {
            label = newLabel
            savedValues.append(newLabel)
        }
    }

    /// Returns a caller-set authorization notice. `currentFix()` is never expected to be
    /// called by `PingModel` -- only `PingSender` calls it -- so a call here is a test bug,
    /// not a valid path, and is counted rather than stubbed with a real fix.
    private final class FakeLocationFixProvider: LocationFixProvider, @unchecked Sendable {
        var notice: String?
        private(set) var currentFixCallCount = 0

        func currentFix() async throws -> LocationFix {
            currentFixCallCount += 1
            throw LocationFixError.unavailable
        }

        func authorizationNotice() async -> String? { notice }
    }

    // MARK: Fixtures -- synthetic values only, none resolves anywhere.

    private static let fixtureFix = LocationFix(
        latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5,
        timestamp: Date(timeIntervalSince1970: 1_700_000_000))

    @MainActor
    private struct Fakes {
        let sender = FakeSender()
        let labelStore: FakeLabelStore
        let fixes = FakeLocationFixProvider()

        init(initialLabel: String = "") {
            labelStore = FakeLabelStore(initialLabel: initialLabel)
        }

        func makeModel() -> PingModel {
            PingModel(sender: sender, labelStore: labelStore, fixes: fixes)
        }
    }

    // MARK: Label memory (REQ-03)

    @Test
    func modelStartsWithTheLabelTheStoreLastHeld() {
        let fakes = Fakes(initialLabel: "Gallipoli")
        let model = fakes.makeModel()

        #expect(model.label == "Gallipoli")
    }

    @Test
    func settingLabelWritesThroughToTheStore() {
        let fakes = Fakes(initialLabel: "Gallipoli")
        let model = fakes.makeModel()

        model.label = "Otranto"

        #expect(fakes.labelStore.savedValues.last == "Otranto")
    }

    // MARK: Outcome mapping and history (REQ-04)

    @Test
    func aSentAttemptRecordsOneEntryWithNoReason() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        model.label = "Home"
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: "{}")

        await model.ping()

        #expect(model.log.entries.count == 1)
        let entry = model.log.entries[0]
        #expect(entry.outcome == .sent)
        #expect(entry.reason == nil)
        #expect(entry.latitude == Self.fixtureFix.latitude)
        #expect(entry.longitude == Self.fixtureFix.longitude)
        #expect(entry.label == "Home")
    }

    @Test
    func aPermanentFailureWithAFixRecordsOneFailedEntry() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix,
            disposition: .permanentFailure(reason: "Rejected by the webhook (HTTP 401)."),
            statusCode: 401, responseBody: nil)

        await model.ping()

        #expect(model.log.entries.count == 1)
        #expect(model.log.entries[0].outcome == .failed)
        #expect(model.log.entries[0].reason == "Rejected by the webhook (HTTP 401).")
    }

    @Test
    func aRetryableFailureWithAFixRecordsOneQueuedEntry() async {
        // The phase-02 mapping (retryable -> .failed) is now live as phase 03 (REQ-05) intended:
        // the sink has already accepted the payload by the time this arm is reached, so it reads
        // Queued, not Failed.
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix,
            disposition: .retryable(reason: "The webhook is unavailable (HTTP 503)."),
            statusCode: 503, responseBody: nil)

        await model.ping()

        #expect(model.log.entries.count == 1)
        #expect(model.log.entries[0].outcome == .queued)
        #expect(model.log.entries[0].reason == "The webhook is unavailable (HTTP 503).")
    }

    @Test
    func anAttemptWithNoFixRecordsNoEntryAndSetsGuidanceInstead() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: nil,
            disposition: .permanentFailure(
                reason: "Add your webhook URL and sender key in Settings before pinging."),
            statusCode: nil, responseBody: nil)

        await model.ping()

        #expect(model.log.entries.isEmpty)
        #expect(model.guidance == "Add your webhook URL and sender key in Settings before pinging.")
    }

    @Test
    func twoPingsLeaveTwoDistinctEntriesNewestFirst() async {
        let fakes = Fakes()
        let model = fakes.makeModel()

        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)
        await model.ping()

        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .permanentFailure(reason: "nope"), statusCode: 403,
            responseBody: nil)
        await model.ping()

        #expect(model.log.entries.count == 2)
        #expect(model.log.entries[0].outcome == .failed)
        #expect(model.log.entries[1].outcome == .sent)
    }

    // MARK: In-flight exclusivity

    @Test
    func aSecondPingWhileOneIsInFlightIsIgnored() async {
        let fakes = Fakes()
        fakes.sender.shouldSuspend = true
        let model = fakes.makeModel()

        let task = Task { await model.ping() }
        while fakes.sender.callCount == 0 {
            await Task.yield()
        }

        #expect(model.isInFlight == true)
        await model.ping()
        #expect(fakes.sender.callCount == 1)

        fakes.sender.release()
        await task.value

        #expect(model.isInFlight == false)
        #expect(fakes.sender.callCount == 1)
    }

    // MARK: Announcement (DESIGN.md -- announced, not just drawn)

    @Test
    func sentAndFailedPingsProduceDistinctAnnouncements() async {
        let fakes = Fakes()
        let model = fakes.makeModel()

        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)
        await model.ping()
        let sentAnnouncement = model.lastAttempt
        #expect(sentAnnouncement != nil)

        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .permanentFailure(reason: "nope"), statusCode: 403,
            responseBody: nil)
        await model.ping()
        let failedAnnouncement = model.lastAttempt

        #expect(failedAnnouncement != nil)
        #expect(sentAnnouncement != failedAnnouncement)
    }

    /// The defect this pins: `lastAnnouncement` was a plain `String?` and the view announces on
    /// change, so a SECOND ping with the same outcome produced the same sentence, `onChange` did
    /// not fire, and nothing was spoken. Two successes in a row is the ordinary case (ping, walk,
    /// ping), and two identical failures is the first-run case (no credentials saved). DESIGN.md
    /// requires the outcome announced, not just drawn. The old test could not see this: it only
    /// ever compared two DIFFERENT outcomes.
    @Test
    func twoIdenticalOutcomesStillProduceTwoDistinctAnnouncements() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)

        await model.ping()
        let first = model.lastAttempt
        await model.ping()
        let second = model.lastAttempt

        #expect(first != nil)
        #expect(second != nil)
        // Same words -- that is the point -- but distinct values, so the view announces both.
        #expect(first?.spoken == second?.spoken)
        #expect(first != second)
    }

    /// Two identical FAILURES too: the reason string is identical every time for a persistent
    /// 401 or missing credentials, which is the shape a value-keyed announcement silenced.
    @Test
    func twoIdenticalFailuresStillProduceTwoDistinctAnnouncements() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .permanentFailure(reason: "Add your webhook URL."),
            statusCode: 401, responseBody: nil)

        await model.ping()
        let first = model.lastAttempt
        await model.ping()
        let second = model.lastAttempt

        #expect(first?.spoken == second?.spoken)
        #expect(first != second)
    }

    /// One sentence per state. An authorization-caused failure sets `guidance` to the very
    /// sentence the standing notice already shows; rendering both stacked two tall blocks saying
    /// the same thing (and, before the sentences were unified, two that disagreed).
    @Test
    func guidanceIsDroppedWhenItWouldRepeatTheAuthorizationNotice() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        let denied = LocationFixError.deniedForApp.reason
        fakes.fixes.notice = denied
        fakes.sender.attemptToReturn = PingAttempt(
            fix: nil, disposition: .permanentFailure(reason: denied), statusCode: nil,
            responseBody: nil)

        await model.ping()

        #expect(model.authorizationNotice == denied)
        #expect(model.guidance == nil)
        #expect(model.log.entries.isEmpty)
    }

    /// The complement: a guidance sentence that is NOT the notice survives, so suppression is
    /// scoped to the duplicate rather than swallowing every fix-less explanation.
    @Test
    func guidanceSurvivesWhenItDiffersFromTheNotice() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.fixes.notice = "Manual pings work now."
        fakes.sender.attemptToReturn = PingAttempt(
            fix: nil, disposition: .permanentFailure(reason: LocationFixError.timedOut.reason),
            statusCode: nil, responseBody: nil)

        await model.ping()

        #expect(model.guidance == LocationFixError.timedOut.reason)
        #expect(model.authorizationNotice == "Manual pings work now.")
    }

    /// Survived a mutation: deleting `guidance = nil` at the top of `ping()` passed the gate,
    /// because no test ever pinged successfully AFTER a fix-less failure. User-visible effect is
    /// "Add your webhook URL…" still on screen under a ping that just succeeded.
    @Test
    func aSuccessfulPingClearsGuidanceLeftByAnEarlierFailure() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: nil, disposition: .permanentFailure(reason: LocationFixError.timedOut.reason),
            statusCode: nil, responseBody: nil)
        await model.ping()
        #expect(model.guidance != nil)

        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)
        await model.ping()

        #expect(model.guidance == nil)
    }

    /// Survived a mutation: deleting `refreshAuthorizationNotice()` from `ping()` passed, because
    /// the notice tests call that method directly. A first ping is when the system prompt gets
    /// answered, so the notice can only be right afterwards -- REQ-10's first-run path.
    @Test
    func pingRefreshesTheAuthorizationNoticeAfterwards() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)
        // The prompt is answered during the ping, so the notice only becomes available now.
        fakes.fixes.notice = "Manual pings work now."

        await model.ping()

        #expect(model.authorizationNotice == "Manual pings work now.")
    }

    /// Survived a mutation: dropping the reason from the spoken sentence passed, because the old
    /// test only compared a success against a failure and "Ping sent." vs "Ping failed." stay
    /// distinct. DESIGN.md wants the outcome announced -- a bare "Ping failed." tells a VoiceOver
    /// user nothing about what to do next.
    @Test
    func aFailureAnnouncementCarriesItsReason() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix,
            disposition: .permanentFailure(reason: "Check the sender key in Settings."),
            statusCode: 401, responseBody: nil)

        await model.ping()

        let spoken = model.lastAttempt?.spoken
        #expect(spoken?.contains("Check the sender key in Settings.") == true)
    }

    /// S1: the badge pinned beside the button reads its outcome from this one property, so the
    /// thing the user sees in the bottom third and the thing VoiceOver says cannot disagree. Before
    /// the first tap there is nothing to report and nothing is drawn.
    @Test
    func thereIsNoLastAttemptBeforeTheFirstTap() {
        let fakes = Fakes()
        let model = fakes.makeModel()

        #expect(model.lastAttempt == nil)
    }

    /// And it carries the outcome itself, not just a sentence -- the badge needs the symbol, word
    /// and colour triple that `PingOutcome` supplies together.
    @Test
    func theLastAttemptCarriesItsOutcomeAndReason() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .permanentFailure(reason: "Check the key."),
            statusCode: 401, responseBody: nil)

        await model.ping()

        #expect(model.lastAttempt?.outcome == .failed)
        #expect(model.lastAttempt?.reason == "Check the key.")

        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .sent, statusCode: 200, responseBody: nil)
        await model.ping()

        #expect(model.lastAttempt?.outcome == .sent)
        #expect(model.lastAttempt?.reason == nil)
    }

    // MARK: Authorization notice (REQ-10)

    @Test
    func refreshAuthorizationNoticeCopiesTheProvidersSentence() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.fixes.notice = "Manual pings work now. Automatic pings need Always."

        await model.refreshAuthorizationNotice()

        #expect(model.authorizationNotice == "Manual pings work now. Automatic pings need Always.")
    }

    @Test
    func aNilNoticeLeavesThePropertyNil() async {
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.fixes.notice = nil

        await model.refreshAuthorizationNotice()

        #expect(model.authorizationNotice == nil)
    }
}
