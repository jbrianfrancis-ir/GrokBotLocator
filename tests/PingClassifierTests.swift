import Foundation
import Testing
@testable import GrokBotLocator

/// Pins every branch of `PingClassifier` against `PingResponse` values built directly -- no
/// `URLSession`, no stub, nothing but the pure function. The 4xx split was an open backstop
/// truth (02-03-PLAN.md) until D-14 settled it: 408/429 retryable, the rest of the range
/// permanent. These now pin a STATED rule, not merely the code's own choice.
@Suite
struct PingClassifierTests {

    @Test(arguments: [200, 201, 202, 204, 299])
    func successCodesAreSent(code: Int) {
        let response = PingResponse(statusCode: code, body: "")
        #expect(PingClassifier.disposition(for: response) == .sent)
    }

    @Test(arguments: [401, 403])
    func authFailuresArePermanentAndPointAtSettings(code: Int) {
        let response = PingResponse(statusCode: code, body: "")
        guard case .permanentFailure(let reason) = PingClassifier.disposition(for: response) else {
            Issue.record("expected .permanentFailure for \(code)")
            return
        }
        #expect(reason.contains("\(code)"))
        #expect(reason.contains("Settings"))
    }

    /// Was `theUndecided4xxRangeIsPermanent` while the rule was an open backstop truth. D-14
    /// settled it, so this now pins a STATED rule rather than merely recording the code's choice:
    /// a 4xx other than 401/403/408/429 means the request itself is wrong, and no number of
    /// retries fixes a wrong URL or a malformed body. 408 and 429 are the exceptions and are
    /// covered by `theTwoTemporary4xxCodesAreRetryable` below.
    @Test(arguments: [400, 404, 409, 410, 422, 499])
    func a4xxThatCannotSucceedLaterIsPermanent(code: Int) {
        let response = PingResponse(statusCode: code, body: "")
        guard case .permanentFailure = PingClassifier.disposition(for: response) else {
            Issue.record("expected .permanentFailure for \(code)")
            return
        }
    }

    /// D-14: 429 asks the caller to slow down and 408 timed the request out. Both mean "not now"
    /// and both succeed on a later attempt, so they queue and ride the backoff rather than being
    /// shown as a failure and dropped. Treating them as permanent lost a ping that would have
    /// gone through 30s later, which is the loss SC-02 exists to forbid.
    @Test(arguments: [408, 429])
    func theTwoTemporary4xxCodesAreRetryable(code: Int) {
        let response = PingResponse(statusCode: code, body: "")
        guard case .retryable(let reason) = PingClassifier.disposition(for: response) else {
            Issue.record("expected .retryable for \(code)")
            return
        }
        #expect(reason.contains("\(code)"))
        // A queued ping's reason is a standing sentence the user reads under a Queued badge, so
        // it must not tell them to go fix something -- there is nothing for them to fix.
        #expect(!reason.contains("Settings"))
        #expect(reason.hasSuffix("."))
    }

    @Test(arguments: [500, 502, 503])
    func serverErrorsAreRetryable(code: Int) {
        let response = PingResponse(statusCode: code, body: "")
        guard case .retryable = PingClassifier.disposition(for: response) else {
            Issue.record("expected .retryable for \(code)")
            return
        }
    }

    @Test(arguments: [302, 600])
    func codesOutsideTheKnownRangesArePermanent(code: Int) {
        let response = PingResponse(statusCode: code, body: "")
        guard case .permanentFailure = PingClassifier.disposition(for: response) else {
            Issue.record("expected .permanentFailure for \(code)")
            return
        }
    }

    @Test
    func aThrownTransportErrorIsRetryableAndNeverEchoesTheError() {
        let error = URLError(.notConnectedToInternet)
        guard case .retryable(let reason) = PingClassifier.disposition(forTransportError: error) else {
            Issue.record("expected .retryable")
            return
        }
        #expect(!reason.contains("notConnectedToInternet"))
        #expect(!reason.contains("Error Domain"))
    }

    @Test
    func everyReasonIsAFinishedSentence() {
        let codes = [401, 403, 408, 400, 404, 409, 410, 422, 429, 499, 500, 502, 503, 302, 600]
        var reasons: [String] = codes.compactMap { code in
            switch PingClassifier.disposition(for: PingResponse(statusCode: code, body: "")) {
            case .permanentFailure(let reason), .retryable(let reason):
                return reason
            case .sent:
                return nil
            }
        }
        if case .retryable(let reason) = PingClassifier.disposition(forTransportError: URLError(.timedOut)) {
            reasons.append(reason)
        }

        for reason in reasons {
            #expect(reason.hasSuffix("."))
            #expect(reason.count >= 20)
        }
    }
}
