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
    /// test calls `release()`, so the in-flight window is directly observable. `@unchecked
    /// Sendable` per `PingSenderTests`'s fakes -- state is only ever touched sequentially
    /// within one awaited test, all on the main actor.
    private final class FakeSender: PingSending, @unchecked Sendable {
        var attemptToReturn = PingAttempt(
            fix: nil, disposition: .sent, statusCode: nil, responseBody: nil)
        var shouldSuspend = false
        private(set) var callCount = 0
        private(set) var labels: [String] = []
        private var continuation: CheckedContinuation<Void, Never>?

        func send(label: String) async -> PingAttempt {
            callCount += 1
            labels.append(label)
            if shouldSuspend {
                await withCheckedContinuation { continuation = $0 }
            }
            return attemptToReturn
        }

        /// Resumes a call suspended by `shouldSuspend`, letting `ping()` complete.
        func release() {
            continuation?.resume()
            continuation = nil
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
    func aRetryableFailureWithAFixAlsoRecordsOneFailedEntry() async {
        // Documented phase-02 mapping: phase 03 (REQ-05) turns this into `.queued`.
        let fakes = Fakes()
        let model = fakes.makeModel()
        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix,
            disposition: .retryable(reason: "The webhook is unavailable (HTTP 503)."),
            statusCode: 503, responseBody: nil)

        await model.ping()

        #expect(model.log.entries.count == 1)
        #expect(model.log.entries[0].outcome == .failed)
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
        let sentAnnouncement = model.lastAnnouncement
        #expect(sentAnnouncement != nil)

        fakes.sender.attemptToReturn = PingAttempt(
            fix: Self.fixtureFix, disposition: .permanentFailure(reason: "nope"), statusCode: 403,
            responseBody: nil)
        await model.ping()
        let failedAnnouncement = model.lastAnnouncement

        #expect(failedAnnouncement != nil)
        #expect(sentAnnouncement != failedAnnouncement)
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
