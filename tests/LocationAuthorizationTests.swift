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
        let fixTimestamp = Date(timeIntervalSince1970: 1_700_000_000)
        let fix = LocationFix(
            latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5, timestamp: fixTimestamp)
        #expect(
            fix.payload(label: "Gallipoli")
                == PingPayload(
                    latitude: 40.77465, longitude: 17.23107, accuracyMetres: 12.5,
                    label: "Gallipoli", capturedAt: fixTimestamp))
        #expect(fix.payload(label: "").label == "")
        // Named claim, not just whole-value equality: the bridge carries the fix's own
        // timestamp specifically into `capturedAt`.
        #expect(fix.payload(label: "Gallipoli").capturedAt == fix.timestamp)
    }

    @Test(arguments: [
        LocationFixError.notAuthorized,
        .deniedForApp,
        .restricted,
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

    /// The defect this pins: `.denied` and `.restricted` used to throw `.notAuthorized` and
    /// `.deniedGlobally`, whose sentences say "has not been granted yet" and "Location Services
    /// are off for this device" -- neither true of those states, and the second unfollowable.
    /// Delegating to `LocationAuthorizationNotice` is what stops the guidance sentence and the
    /// standing notice disagreeing, so assert they are the SAME string, not merely both present.
    @Test
    func deniedAndRestrictedBorrowTheNoticeSentenceVerbatim() {
        #expect(LocationFixError.deniedForApp.reason == LocationAuthorizationNotice.notice(for: .denied))
        #expect(LocationFixError.restricted.reason == LocationAuthorizationNotice.notice(for: .restricted))
    }

    /// Each of the three authorization-shaped errors says something different: "not answered
    /// yet" (the prompt timeout), "this app was refused", and "off for the whole device" are
    /// three different problems with three different routes out.
    @Test
    func theThreeAuthorizationErrorsDoNotShareASentence() {
        let sentences = Set([
            LocationFixError.notAuthorized.reason,
            LocationFixError.deniedForApp.reason,
            LocationFixError.deniedGlobally.reason,
            LocationFixError.restricted.reason,
        ])
        #expect(sentences.count == 4)
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
