import Foundation
import Testing
@testable import GrokBotLocator

/// Pins REQ-09/SC-04 against `PingRateLimiter`: the 15s floor, the 60s default, the `>=`
/// boundary at exactly one interval, the shared-window claim (SC-04: manual and automatic
/// counted together), and the concurrency guarantee the actor exists to provide. All dates
/// are fixed and nothing sleeps -- `now` is always a parameter, the house pattern set by
/// `PingRetryPolicyTests`.
@Suite
struct PingRateLimiterTests {
    private static let referenceDate = Date(timeIntervalSince1970: 1_700_000_000)

    @Test
    func theFirstClaimIsAlwaysAllowed() async {
        let limiter = PingRateLimiter()
        let decision = await limiter.claim(at: Self.referenceDate)
        #expect(decision == .allowed)
    }

    @Test
    func twoEventsTwentySecondsApartProduceOnePingAtTheDefault() async {
        let limiter = PingRateLimiter()
        let t = Self.referenceDate
        #expect(await limiter.claim(at: t) == .allowed)

        let second = await limiter.claim(at: t.addingTimeInterval(20))
        guard case .tooSoon(let retryAfter, _) = second else {
            Issue.record("expected .tooSoon, got \(second)")
            return
        }
        #expect(retryAfter == 40)
    }

    @Test
    func aClaimExactlyOneIntervalLaterIsAllowed() async {
        let limiter = PingRateLimiter()
        let t = Self.referenceDate
        #expect(await limiter.claim(at: t) == .allowed)
        #expect(await limiter.claim(at: t.addingTimeInterval(60)) == .allowed)
    }

    @Test(arguments: [5.0, 0.0, -100.0, Double.nan])
    func theIntervalCannotBeSetBelowFifteenSeconds(requested: Double) async {
        let t = Self.referenceDate

        let limiter = PingRateLimiter()
        await limiter.setMinimumInterval(requested)
        #expect(await limiter.claim(at: t) == .allowed)
        #expect(await limiter.claim(at: t.addingTimeInterval(15)) == .allowed)

        let freshLimiter = PingRateLimiter()
        await freshLimiter.setMinimumInterval(requested)
        #expect(await freshLimiter.claim(at: t) == .allowed)

        let tooEarly = await freshLimiter.claim(at: t.addingTimeInterval(14))
        guard case .tooSoon = tooEarly else {
            Issue.record(
                "expected .tooSoon at t+14 for requested interval \(requested), got \(tooEarly)"
            )
            return
        }
    }

    @Test
    func aRefusalExplainsItselfInASentence() async {
        let limiter = PingRateLimiter()
        let t = Self.referenceDate
        #expect(await limiter.claim(at: t) == .allowed)

        let refusal = await limiter.claim(at: t.addingTimeInterval(1))
        guard case .tooSoon(_, let reason) = refusal else {
            Issue.record("expected .tooSoon, got \(refusal)")
            return
        }
        #expect(reason.hasSuffix("."))
        #expect(reason.count > 20)
        #expect(!reason.contains("nil"))
        #expect(!reason.contains("Optional"))
    }

    @Test
    func manualAndAutomaticShareOneWindow() async {
        // One limiter, two callers that identify themselves only in this test's comments --
        // nothing in the type distinguishes them, which is what SC-04's "counted together"
        // means in practice.
        let limiter = PingRateLimiter()
        let t = Self.referenceDate

        let manualTap = await limiter.claim(at: t)
        #expect(manualTap == .allowed)

        let automaticTrigger = await limiter.claim(at: t.addingTimeInterval(10))
        guard case .tooSoon = automaticTrigger else {
            Issue.record("expected the automatic trigger to be refused by the manual tap's window, got \(automaticTrigger)")
            return
        }
    }

    @Test
    func fiftyConcurrentClaimsAtTheSameInstantAllowExactlyOne() async {
        // Real concurrent callers against the real actor, not a fake that returns without
        // suspending -- the reentrancy test .planning/LEARNINGS.md asks for.
        let limiter = PingRateLimiter()
        let t = Self.referenceDate

        let decisions = await withTaskGroup(of: RateLimitDecision.self) { group in
            for _ in 0..<50 {
                group.addTask {
                    await limiter.claim(at: t)
                }
            }
            var collected: [RateLimitDecision] = []
            for await decision in group {
                collected.append(decision)
            }
            return collected
        }

        #expect(decisions.count == 50)
        #expect(decisions.filter { $0 == .allowed }.count == 1)
    }
}
