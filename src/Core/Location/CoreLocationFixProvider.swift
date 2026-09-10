import CoreLocation
import Foundation

/// The one file in the app that touches `CLLocationManager` / `CLLocationUpdate`
/// (ARCHITECTURE.md -- all location work sits in one actor-isolated coordinator; views never
/// touch CLLocationManager directly). Main-actor isolation both satisfies that rule and keeps
/// Core Location on the thread it expects.
///
/// Requests When-In-Use at the point of use -- inside `currentFix()`, never at launch -- takes
/// a single fix, and stops. Never requests the Always authorization (phase 04's triggers do
/// that) and never switches on continuous background updating -- ARCHITECTURE's Forbidden
/// continuous-background-GPS combination.
@MainActor
final class CoreLocationFixProvider: LocationFixProvider {
    private let manager = CLLocationManager()

    /// REQ-10's standing explanation of what the current authorization level does not allow.
    func authorizationNotice() async -> String? {
        LocationAuthorizationNotice.notice(for: manager.authorizationStatus)
    }

    func currentFix() async throws -> LocationFix {
        if manager.authorizationStatus == .notDetermined {
            // The point-of-use request: this is the only place in the app that asks for
            // location authorization of any kind this phase.
            manager.requestWhenInUseAuthorization()

            // Bounded wait for the user to answer the system prompt. 250ms x 240 = 60s. The
            // bound is not optional: a user who backgrounds the app at the prompt leaves the
            // status `.notDetermined` indefinitely, and an unbounded wait would hold
            // 02-09's `isInFlight` true for the life of the process -- a spinning button with
            // no sentence, which DESIGN.md forbids.
            var pollCount = 0
            while manager.authorizationStatus == .notDetermined, pollCount < 240 {
                try await Task.sleep(for: .milliseconds(250))
                pollCount += 1
            }

            if manager.authorizationStatus == .notDetermined {
                throw LocationFixError.notAuthorized
            }
        }

        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            break
        case .restricted:
            throw LocationFixError.deniedGlobally
        case .denied:
            throw LocationFixError.notAuthorized
        default:
            throw LocationFixError.notAuthorized
        }

        return try await withThrowingTaskGroup(of: LocationFix.self) { group in
            group.addTask {
                for try await update in CLLocationUpdate.liveUpdates(.default) {
                    if update.authorizationRequestInProgress {
                        continue
                    }
                    if update.authorizationDeniedGlobally {
                        throw LocationFixError.deniedGlobally
                    }
                    if update.authorizationDenied {
                        throw LocationFixError.notAuthorized
                    }
                    if update.locationUnavailable {
                        throw LocationFixError.unavailable
                    }
                    if let location = update.location {
                        return try LocationFix.validated(
                            latitude: location.coordinate.latitude,
                            longitude: location.coordinate.longitude,
                            horizontalAccuracy: location.horizontalAccuracy,
                            timestamp: location.timestamp)
                    }
                }
                throw LocationFixError.unavailable
            }
            group.addTask {
                try await Task.sleep(for: .seconds(8))
                throw LocationFixError.timedOut
            }

            // Whichever child finishes first -- a fix or an error -- wins; the other keeps
            // running the live-update stream unless cancelled, so cancel the group on the way
            // out regardless of how this returns or throws.
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
