import CoreLocation
import Foundation
import MapKit

/// The ONE file in the app permitted to import MapKit (D-15, ARCHITECTURE.md Forbidden). D-15
/// authorized MapKit for reverse geocoding ONLY -- because `CLGeocoder`/`CLPlacemark` are
/// soft-deprecated at iOS 26.0 ("Use MapKit", RESEARCH.md Q1) -- and nothing else: no map view,
/// no map tile, no MapKit type anywhere in the ping path. `scripts/smoke.sh`'s MapKit guard
/// enforces both the import and MapKit type names outside this file.
///
/// REQUIREMENTS.md:34 also records, as a known property rather than a later discovery: reverse
/// geocoding sends a coordinate to Apple's geocoding service. That is real network egress,
/// inherent to the feature -- it is not "storing or logging" under ARCHITECTURE's Forbidden
/// entry. Nothing in this file writes, logs, or prints a coordinate itself.
struct MapKitTriggerLabelProvider: TriggerLabelProviding {
    /// A label attempt may hold the ping path for at most 3 seconds -- a CHOSEN bound, not a
    /// derived one (RESEARCH.md `## Unverified`: MapKit's rate-limit and offline error
    /// semantics are not established, so this is not tuned against any documented behaviour).
    /// REQUIREMENTS.md:34 requires only that geocoding never delay delivery; 3 s is generous
    /// for decoration while leaving an automatic ping on a background wake almost all of the
    /// system time it is given.
    static let budget: Duration = .seconds(3)

    let budget: Duration

    init(budget: Duration = MapKitTriggerLabelProvider.budget) {
        self.budget = budget
    }

    /// Every failure path lands on "": a nil failable init, a thrown error swallowed by
    /// `try?`, an empty result list, a nil locality, a whitespace-only name, and the budget
    /// expiring. There is no other outcome and this function cannot throw.
    func label(for coordinate: TriggerCoordinate) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return ""
        }

        // The request is a class and not `Sendable`. Boxing it lets the timeout side of the
        // race below call `cancel()` on the loser -- its own documented lifecycle method
        // (RESEARCH.md Q1: `isLoading`/`isCancelled`/`cancel()`) -- without the two concurrent
        // accesses (the fetch task's `await request.mapItems`, the timeout task's
        // `request.cancel()`) being an unproven race to the compiler. Calling `cancel()` on the
        // loser is not decoration: `withTaskGroup` implicitly awaits every child before
        // returning, so without it a slow-to-respond fetch could hold this function past its
        // own budget rather than merely being ignored.
        let box = UncheckedSendableBox(request)

        let winner: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                (try? await box.value.mapItems)?.first?.addressRepresentations?.cityName
            }
            group.addTask {
                try? await Task.sleep(for: budget)
                box.value.cancel()
                return nil
            }

            defer { group.cancelAll() }
            let first = await group.next() ?? nil
            return first
        }

        return normalisedTriggerLabel(winner ?? "")
    }
}

/// A minimal box for moving a single known-safe-to-share reference across a concurrency
/// boundary that Swift cannot itself verify is race-free. Used here for exactly one value,
/// `MKReverseGeocodingRequest`, whose own `cancel()` is meant to be callable while a `mapItems`
/// fetch is in flight elsewhere.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}
