import CoreLocation
import Foundation
import Testing
@testable import GrokBotLocator

/// Proves arrival detection, fix stamping, and the refused-Always sentence entirely from the
/// Sendable shim structs. CoreLocation's own visit type has no public value initializer, so
/// these structs -- and the deliberate separation from that type -- are what makes any of this
/// testable without a device.
@Suite
struct TriggerEventsTests {
    private static func coordinate() -> TriggerCoordinate {
        TriggerCoordinate(latitude: 41.1171, longitude: 16.8719)
    }

    @Test
    func aVisitStillInProgressIsAnArrival() {
        let visit = VisitReport(
            coordinate: Self.coordinate(), accuracyMetres: 10, arrivalDate: Date(),
            departureDate: .distantFuture)

        #expect(visit.isArrival == true)
    }

    @Test
    func aVisitWithADepartureIsNotAnArrival() {
        let visit = VisitReport(
            coordinate: Self.coordinate(), accuracyMetres: 10, arrivalDate: Date(),
            departureDate: Date())

        #expect(visit.isArrival == false)
    }

    @Test
    func anArrivalFixIsStampedWithTheArrivalTime() {
        let arrival = Date(timeIntervalSince1970: 1_000)
        let departure = Date(timeIntervalSince1970: 2_000)
        let visit = VisitReport(
            coordinate: Self.coordinate(), accuracyMetres: 10, arrivalDate: arrival,
            departureDate: departure)

        #expect(visit.locationFix()?.timestamp == arrival)
        #expect(visit.locationFix()?.timestamp != departure)
        #expect(visit.locationFix()?.timestamp != Date())
    }

    @Test
    func aNegativeAccuracyYieldsNoFix() {
        let visit = VisitReport(
            coordinate: Self.coordinate(), accuracyMetres: -1, arrivalDate: Date(),
            departureDate: .distantFuture)
        #expect(visit.locationFix() == nil)

        let change = SignificantChangeReport(
            coordinate: Self.coordinate(), accuracyMetres: -1, timestamp: Date())
        #expect(change.locationFix() == nil)
    }

    @Test
    func aSignificantChangeFixCarriesItsOwnCoordinateAndTime() {
        let timestamp = Date(timeIntervalSince1970: 12_345)
        let change = SignificantChangeReport(
            coordinate: Self.coordinate(), accuracyMetres: 12.5, timestamp: timestamp)

        let fix = change.locationFix()
        #expect(fix?.latitude == Self.coordinate().latitude)
        #expect(fix?.longitude == Self.coordinate().longitude)
        #expect(fix?.accuracyMetres == 12.5)
        #expect(fix?.timestamp == timestamp)
    }

    @Test
    func theWhenInUseNoticeChangesOnceAlwaysHasBeenRefused() {
        let beforeAsking = TriggerAuthorizationNotice.notice(
            for: .authorizedWhenInUse, alwaysWasRequested: false)
        let afterRefusing = TriggerAuthorizationNotice.notice(
            for: .authorizedWhenInUse, alwaysWasRequested: true)

        #expect(beforeAsking != nil)
        #expect(afterRefusing != nil)
        #expect(beforeAsking != afterRefusing)
        #expect(beforeAsking?.hasSuffix(".") == true)
        #expect(afterRefusing?.hasSuffix(".") == true)
        #expect(afterRefusing?.contains("nil") == false)
        #expect(afterRefusing?.contains("authorizedWhenInUse") == false)
    }

    @Test
    func alwaysNeedsNoExplanation() {
        #expect(TriggerAuthorizationNotice.notice(for: .authorizedAlways, alwaysWasRequested: false) == nil)
        #expect(TriggerAuthorizationNotice.notice(for: .authorizedAlways, alwaysWasRequested: true) == nil)
    }
}
