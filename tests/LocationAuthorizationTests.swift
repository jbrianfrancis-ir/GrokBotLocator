import CoreLocation
import Foundation
import Testing
@testable import GrokBotLocator

/// Pins REQ-10's explanation of what the current authorization level does not allow, the
/// `LocationFix` -> `PingPayload` bridge, `LocationFixError`'s finished sentences, and both
/// branches of the `validated(...)` accuracy guard (see 02-05-PLAN.md backstop_truths --
/// refusing a negative `horizontalAccuracy` is a backstop decision, and these two tests are
/// its verification path). Every fixture is synthetic; none is a real coordinate or credential.
@Suite
struct LocationAuthorizationTests {

    @Test
    func noticeIsNilWhenThereIsNothingToExplain() {
        #expect(LocationAuthorizationNotice.notice(for: .notDetermined) == nil)
        #expect(LocationAuthorizationNotice.notice(for: .authorizedAlways) == nil)
    }

    @Test
    func noticeAtWhenInUseExplainsWhatAlwaysWouldAdd() {
        let notice = LocationAuthorizationNotice.notice(for: .authorizedWhenInUse)
        #expect(notice != nil)
        #expect(notice?.contains("Always") == true)
        #expect(notice?.contains("denied") == false)
    }

    @Test(arguments: [CLAuthorizationStatus.denied, .restricted])
    func noticeAtDeniedOrRestrictedSaysWhatHappenedAndWhatToDoNext(status: CLAuthorizationStatus) {
        let notice = LocationAuthorizationNotice.notice(for: status)
        #expect(notice != nil)
        #expect(notice?.hasSuffix(".") == true)
        #expect((notice?.count ?? 0) >= 30)
    }

    @Test
    func everyNonNilNoticeIsDistinct() {
        let statuses: [CLAuthorizationStatus] = [
            .notDetermined, .authorizedAlways, .authorizedWhenInUse, .denied, .restricted,
        ]
        let notices = statuses.compactMap { LocationAuthorizationNotice.notice(for: $0) }
        #expect(Set(notices).count == notices.count)
    }

    @Test
    func fixBecomesAPayloadCarryingItsOwnFieldsAndTheCallersLabel() {
        let fix = LocationFix(
            latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5, timestamp: .init())
        #expect(
            fix.payload(label: "Gallipoli")
                == PingPayload(
                    latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5,
                    label: "Gallipoli"))
        #expect(fix.payload(label: "").label == "")
    }

    @Test(arguments: [
        LocationFixError.notAuthorized,
        .deniedGlobally,
        .unavailable,
        .timedOut,
        .invalidAccuracy,
    ])
    func everyFixErrorReasonIsAFinishedSentence(error: LocationFixError) {
        let reason = error.reason
        #expect(!reason.isEmpty)
        #expect(reason.hasSuffix("."))
        #expect(reason.rangeOfCharacter(from: .letters) != nil)
    }

    @Test
    func validatedAcceptsANonNegativeAccuracy() throws {
        let date = Date()
        let fix = try LocationFix.validated(
            latitude: 40.77465, longitude: 17.23107, horizontalAccuracy: 12.5, timestamp: date)
        #expect(fix.latitude == 40.77465)
        #expect(fix.longitude == 17.23107)
        #expect(fix.accuracyMetres == 12.5)
        #expect(fix.timestamp == date)

        let zeroAccuracy = try LocationFix.validated(
            latitude: 40.77465, longitude: 17.23107, horizontalAccuracy: 0, timestamp: date)
        #expect(zeroAccuracy.accuracyMetres == 0)
    }

    @Test
    func validatedRefusesANegativeAccuracy() {
        #expect(throws: LocationFixError.invalidAccuracy) {
            try LocationFix.validated(
                latitude: 40.77465, longitude: 17.23107, horizontalAccuracy: -1, timestamp: .init())
        }
    }
}
