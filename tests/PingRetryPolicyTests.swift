import Foundation
import Testing
@testable import GrokBotLocator

/// Pins every number in `PingRetryPolicy.standard`'s schedule against fixed dates -- no
/// `Date()`, no sleeping, nothing but the pure function. Includes the 1920-at-attempt-7 value
/// and the 7-day give-up horizon, both called out in 03-02-PLAN.md as the ones most likely to
/// drift back to a wrong-but-plausible number.
@Suite
struct PingRetryPolicyTests {
    private let policy = PingRetryPolicy.standard

    @Test
    func delayGrowsStrictlyUntilItCaps() {
        let expected: [TimeInterval] = [30, 60, 120, 240, 480, 960, 1920, 3600]
        let actual = (1...8).map { policy.delay(afterAttempts: $0) }
        #expect(actual == expected)

        for index in 1..<actual.count {
            #expect(actual[index] > actual[index - 1])
        }
    }

    @Test(arguments: [8, 9, 20, 500])
    func delayIsCappedForeverAfter(attemptsMade: Int) {
        #expect(policy.delay(afterAttempts: attemptsMade) == 3600)
    }

    @Test(arguments: [0, -1])
    func delayIsSaneForZeroOrNegativeAttempts(attemptsMade: Int) {
        #expect(policy.delay(afterAttempts: attemptsMade) == 30)
    }

    @Test(arguments: [1, 8])
    func nextAttemptDateIsNowPlusTheDelay(attemptsMade: Int) {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let expected = now.addingTimeInterval(policy.delay(afterAttempts: attemptsMade))
        #expect(policy.nextAttemptDate(afterAttempts: attemptsMade, now: now) == expected)
    }

    @Test
    func givesUpOnlyAfterSevenDaysFromTheFirstAttempt() {
        let firstAttemptAt = Date(timeIntervalSince1970: 1_700_000_000)

        #expect(policy.hasGivenUp(firstAttemptAt: firstAttemptAt, now: firstAttemptAt) == false)
        #expect(
            policy.hasGivenUp(
                firstAttemptAt: firstAttemptAt,
                now: firstAttemptAt.addingTimeInterval(6 * 86_400 + 86_399)
            ) == false
        )
        #expect(
            policy.hasGivenUp(
                firstAttemptAt: firstAttemptAt,
                now: firstAttemptAt.addingTimeInterval(7 * 86_400)
            ) == true
        )
        #expect(
            policy.hasGivenUp(
                firstAttemptAt: firstAttemptAt,
                now: firstAttemptAt.addingTimeInterval(30 * 86_400)
            ) == true
        )
    }

    @Test
    func theGiveUpReasonIsAFinishedSentence() {
        let reason = PingRetryPolicy.gaveUpReason
        #expect(!reason.isEmpty)
        #expect(reason.hasSuffix("."))
        #expect(!reason.contains("HTTP "))
        #expect(reason.count > 40)
    }
}
