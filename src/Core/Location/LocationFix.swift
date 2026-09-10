import CoreLocation
import Foundation

/// A successful location measurement, stripped down to exactly what a ping payload needs.
/// Pure data: nothing in this file talks to the location manager, so everything built on top
/// of `LocationFix` is testable without a device (ARCHITECTURE.md -- all location work sits
/// in one actor-isolated coordinator; views never touch the location manager directly).
struct LocationFix: Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let accuracyMetres: Double
    let timestamp: Date

    /// The only bridge from a fix to the wire type. `label` is the caller's, not the fix's --
    /// a `LocationFix` has no notion of who it is being sent for.
    func payload(label: String) -> PingPayload {
        PingPayload(
            latitude: latitude, longitude: longitude, accuracyMetres: accuracyMetres, label: label)
    }

    /// The ONLY constructor 02-06's CoreLocation adapter is allowed to use to turn a raw
    /// location reading into a `LocationFix`. Refuses a negative `horizontalAccuracy` --
    /// CoreLocation's documented signal that the measurement itself is invalid -- as
    /// `LocationFixError.invalidAccuracy` rather than let a negative `accuracy_m` reach the
    /// wire. This is a BACKSTOP decision (see 02-05-PLAN.md backstop_truths): REQUIREMENTS.md's
    /// REQ-02 requires `accuracy_m` in the payload but says nothing about what to do with an
    /// invalid reading, so refusing, clamping to 0, or sending the negative value through were
    /// all defensible. Keeping the guard here, rather than inside the CoreLocation adapter, is
    /// what makes it testable without a device.
    static func validated(
        latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Date
    ) throws -> LocationFix {
        guard horizontalAccuracy >= 0 else {
            throw LocationFixError.invalidAccuracy
        }
        return LocationFix(
            latitude: latitude, longitude: longitude, accuracyMetres: horizontalAccuracy,
            timestamp: timestamp)
    }
}

/// Every way a fix attempt can fail to produce a `LocationFix`. Each case carries a finished
/// sentence -- what happened and what to do next, on screen, never a bare status name
/// (DESIGN.md) -- rather than leaving the view to compose one from a raw error.
enum LocationFixError: Error, Equatable, Sendable {
    case notAuthorized
    case deniedGlobally
    case unavailable
    case timedOut
    case invalidAccuracy

    var reason: String {
        switch self {
        case .notAuthorized:
            return "Location access has not been granted yet. Allow location access to send a manual ping."
        case .deniedGlobally:
            return "Location Services are off for this device. Turn them on in Settings ▸ Privacy & Security ▸ Location Services, then try again."
        case .unavailable:
            return "Location is temporarily unavailable. Try again in a moment."
        case .timedOut:
            return "Could not get a location fix in time. Move somewhere with a clearer view of the sky, then tap again."
        case .invalidAccuracy:
            return "The location reading was invalid. Try again in a moment."
        }
    }
}

/// What a caller above the coordinator needs from location: the current fix, and a standing
/// explanation of what the current authorization level does not allow. A protocol, so every
/// caller above it is testable with no CoreLocation.
protocol LocationFixProvider: Sendable {
    func currentFix() async throws -> LocationFix
    func authorizationNotice() async -> String?
}

/// REQ-10's explanation of what the current `CLAuthorizationStatus` does not allow, as a
/// finished sentence -- or `nil` when there is nothing to explain. Manual pings are fully
/// usable at "When In Use" (ARCHITECTURE.md); `Always` only unlocks automatic triggers, so
/// `.authorizedWhenInUse` gets an explanation of what is *missing*, not an error, and
/// `.denied`/`.restricted` get what happened and what to do next (DESIGN.md), never a bare
/// status name.
enum LocationAuthorizationNotice {
    static func notice(for status: CLAuthorizationStatus) -> String? {
        switch status {
        case .notDetermined, .authorizedAlways:
            return nil
        case .authorizedWhenInUse:
            return "Manual pings work now. Automatic pings while the app is closed need Always — turn on a trigger to be asked for it."
        case .denied:
            return "Location access is off for GrokBotLocator. Turn it on in Settings ▸ Privacy & Security ▸ Location Services ▸ GrokBotLocator ▸ While Using the App to send a manual ping."
        case .restricted:
            return "Location is restricted on this device. Manual pings cannot include a position until that restriction is lifted."
        @unknown default:
            return nil
        }
    }
}
