import CoreLocation
import Foundation

/// REQ-06's significant-change wake, stripped to exactly what a ping decision needs. Pure data
/// -- this file knows nothing about the location manager that produces one (ARCHITECTURE: all
/// location work sits in one actor-isolated coordinator; the delegate proxy is what converts a
/// callback into this struct, at the point of receipt, before anything crosses that boundary).
struct SignificantChangeReport: Sendable, Equatable {
    let coordinate: TriggerCoordinate
    let accuracyMetres: Double
    let timestamp: Date

    /// The only bridge from a report to a `LocationFix`. Delegates the negative-accuracy guard
    /// to `LocationFix.validated(...)` rather than re-deciding it here -- a negative
    /// `accuracyMetres` (CoreLocation's documented invalid-measurement signal) yields `nil`
    /// instead of a fix that would carry it to the wire.
    func locationFix() -> LocationFix? {
        try? LocationFix.validated(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            horizontalAccuracy: accuracyMetres, timestamp: timestamp)
    }
}

/// REQ-07's visit wake. CoreLocation's own visit type does NOT conform to `Sendable`
/// (RESEARCH.md Q5) and has no public value initializer, which is exactly why this shim
/// exists: the delegate proxy builds one of these from that type at the point of receipt, and
/// everything above the proxy -- including every test in this phase -- deals only in this
/// struct, never the CoreLocation one.
struct VisitReport: Sendable, Equatable {
    let coordinate: TriggerCoordinate
    let accuracyMetres: Double
    let arrivalDate: Date
    let departureDate: Date

    /// CoreLocation's documented sentinel for "the visit is still in progress": a visit that
    /// has not yet ended reports `departureDate == Date.distantFuture`. REQ-07 pings on arrival
    /// only, and this is the value that decides it.
    var isArrival: Bool { departureDate == Date.distantFuture }

    /// The only bridge from a report to a `LocationFix`, stamped with `arrivalDate` -- never
    /// `departureDate` and never "now". ARCHITECTURE pins `at` as the time of the FIX, and for a
    /// visit the fix this ping reports is the arrival, not whatever moment the wake happened to
    /// be handled.
    func locationFix() -> LocationFix? {
        try? LocationFix.validated(
            latitude: coordinate.latitude, longitude: coordinate.longitude,
            horizontalAccuracy: accuracyMetres, timestamp: arrivalDate)
    }
}

/// The seam between the actor-isolated coordinator and whatever owns the real location
/// manager. A protocol so the coordinator (04-11) is testable with a fake and no device --
/// exactly the shape `LocationFixProvider` already gives manual pings.
protocol LocationTriggerSource: Sendable {
    func setHandlers(
        significantChange: @escaping @Sendable (SignificantChangeReport) async -> Void,
        visit: @escaping @Sendable (VisitReport) async -> Void
    ) async
    func startSignificantChange() async
    func stopSignificantChange() async
    func startVisits() async
    func stopVisits() async
    func currentAuthorization() async -> CLAuthorizationStatus
    func requestAlways() async -> CLAuthorizationStatus
}

/// REQ-10's explanation of what the current `CLAuthorizationStatus` does not allow, once
/// automatic triggers are in the picture -- a finished sentence, or `nil` when there is nothing
/// to explain. Every other status delegates to the existing `LocationAuthorizationNotice`
/// rather than authoring a second sentence for the same state; the one truly new state is
/// `.authorizedWhenInUse` after Always was asked for and refused, which needs a DISTINCT
/// sentence from the one shown before Always was ever requested (this plan's must_haves).
enum TriggerAuthorizationNotice {
    static func notice(for status: CLAuthorizationStatus, alwaysWasRequested: Bool) -> String? {
        switch status {
        case .authorizedAlways:
            return nil
        case .authorizedWhenInUse where alwaysWasRequested:
            // The user was asked for Always and chose While Using -- distinct from the
            // "you could ask" sentence `LocationAuthorizationNotice` shows before Always was
            // ever requested. Manual pings are unaffected (ARCHITECTURE: fully usable at
            // When In Use), and this sentence says so.
            return "Automatic pings need Always. You chose While Using, so triggers only fire while GrokBotLocator is open — the I'm here button works exactly as before. To change it: Settings ▸ Privacy & Security ▸ Location Services ▸ GrokBotLocator ▸ Always."
        default:
            return LocationAuthorizationNotice.notice(for: status)
        }
    }
}
