import Foundation
import Testing
@testable import GrokBotLocator

/// Pins every branch of `PingClassifier` against `PingResponse` values built directly -- no
/// `URLSession`, no stub, nothing but the pure function. Includes the undecided 4xx backstop
/// branch (02-03-PLAN.md) so a future change to it fails loudly here rather than silently at
/// the network layer.
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

    @Test(arguments: [400, 404, 409, 422, 499])
    func theUndecided4xxRangeIsPermanent(code: Int) {
        let response = PingResponse(statusCode: code, body: "")
        guard case .permanentFailure = PingClassifier.disposition(for: response) else {
            Issue.record("expected .permanentFailure for \(code)")
            return
        }
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
        let codes = [401, 403, 400, 404, 409, 422, 499, 500, 502, 503, 302, 600]
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
