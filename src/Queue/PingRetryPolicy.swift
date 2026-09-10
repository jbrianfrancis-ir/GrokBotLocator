import Foundation

/// The retry schedule as a pure value: when the next attempt for a queued ping is due, and
/// when enough time has passed that retrying stops and the ping is recorded as a permanent
/// failure. A pure function of (attempts made, first attempt time, now) -- it reads no clock,
/// no network and no disk of its own, so `now` is always a parameter and every schedule is
/// testable without waiting. `PingQueueDrain` (03-09) is the one caller: every next-attempt
/// date and every give-up decision goes through here, so the schedule exists in exactly one
/// place. This type does not decide retryable vs. permanent for a given response -- that is
/// `PingClassifier`'s job, one layer down; this type decides only WHEN a retryable ping is
/// next attempted and when retrying stops.
///
/// Two decisions below are BACKSTOP, not derived from REQUIREMENTS.md, and a later reader
/// should not mistake either for a settled rule:
/// - The 7-day give-up horizon in `hasGivenUp`. SC-02 names a 7-day trip but sets no give-up
///   horizon of its own; never giving up, and giving up after a day, are both equally
///   defensible readings of it.
/// - `PingClassifier`'s treatment of the non-401/403 4xx range (404, 410, 422, 429 ...) as
///   PERMANENT, never retried. REQUIREMENTS.md settles only 401/403; 429 in particular is the
///   documented "retry later" code, so retrying part of the 4xx range is equally defensible.
///   Phase 02 carried this as an unresolved backstop (02-manual-ping/VERIFICATION.md
///   `unverified`); this type does not change that decision, only notes it, since the give-up
///   clock only ever starts ticking on ping the classifier has already called retryable.
struct PingRetryPolicy: Sendable, Equatable {
    static let standard = PingRetryPolicy()

    private static let giveUpHorizon: TimeInterval = 604_800 // 7 days

    /// A finished sentence: what happened and what to do next (DESIGN.md). Never a bare
    /// status code or status word on its own.
    static let gaveUpReason =
        "This ping could not be delivered after a week of retries and has been given up. " +
        "Check the webhook URL in Settings, then tap I'm here again."

    /// The wait before the NEXT attempt, given how many have already been made. The formula
    /// is the definition: `min(30 * pow(2, attemptsMade - 1), 3600)`, in whole seconds --
    /// 30, 60, 120, 240, 480, 960, 1920, 3600 for attempts 1 through 8, then 3600 forever
    /// after (30 * 2^7 = 3840 is where the cap first bites). `attemptsMade <= 0` is treated
    /// as 1 rather than trapping, so it returns 30.
    func delay(afterAttempts attemptsMade: Int) -> TimeInterval {
        let effectiveAttempts = max(attemptsMade, 1)
        let uncapped = 30 * pow(2.0, Double(effectiveAttempts - 1))
        return min(uncapped, 3600)
    }

    /// The next attempt date, given how many attempts have already been made and the current
    /// time. `now` is always a parameter -- this type never reads the system clock itself.
    func nextAttemptDate(afterAttempts attemptsMade: Int, now: Date) -> Date {
        now.addingTimeInterval(delay(afterAttempts: attemptsMade))
    }

    /// True once `now` is at or past `firstAttemptAt` plus 7 days. Time-based, not
    /// count-based, on purpose: a phone in airplane mode for two days makes no attempts at
    /// all, so a count-based limit would give up in minutes on the one day it was briefly
    /// online and never at all on the days it was not.
    func hasGivenUp(firstAttemptAt: Date, now: Date) -> Bool {
        now >= firstAttemptAt.addingTimeInterval(Self.giveUpHorizon)
    }
}
