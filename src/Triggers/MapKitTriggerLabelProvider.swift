import CoreLocation
import Foundation
import MapKit
import Synchronization

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
    ///
    /// DEVIATION from this plan's own description (found by an actual hang, not by review):
    /// the plan called for racing the fetch and the timeout as two children of a
    /// `withTaskGroup`, relying on `request.cancel()` to make the loser finish so the group's
    /// implicit "await every child before returning" would not itself outlive the budget. In
    /// this simulator, with no geocoding service reachable, `cancel()` did not make `await
    /// request.mapItems` resume -- its underlying continuation was reported leaked by the
    /// runtime -- and the whole function hung indefinitely instead of returning within budget.
    /// RESEARCH.md `## Unverified` already declined to assume MapKit resumes cleanly under
    /// throttling or offline conditions; this is now empirical evidence of exactly that failure
    /// mode, stronger than what RESEARCH could establish on its own.
    ///
    /// The fix bounds this function BY CONSTRUCTION rather than by trusting MapKit's
    /// cancellation: the fetch runs as an UNSTRUCTURED task that this function never awaits, so
    /// if it never completes it is simply abandoned rather than held open. A `Mutex`-guarded
    /// one-shot flag (`Synchronization.Mutex`, not `NSLock` + `@unchecked Sendable`, per
    /// LEARNINGS.md) lets whichever of {fetch, timeout} finishes first resume the continuation
    /// exactly once; the other's resume attempt is a no-op. `request.cancel()` is still called
    /// on timeout as hygiene that may free resources sooner, but correctness no longer depends
    /// on it working.
    func label(for coordinate: TriggerCoordinate) async -> String {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard let request = MKReverseGeocodingRequest(location: location) else {
            return ""
        }

        // The request is a class and not `Sendable`; boxing it lets both the fetch and the
        // timeout below touch it (`.mapItems`, `.cancel()`) without that being an unproven race
        // to the compiler.
        let box = UncheckedSendableBox(request)
        // `Mutex` is itself unconditionally `Sendable`, but it is also noncopyable, so the
        // compiler cannot verify a plain `let` capture shared by two separate escaping `Task`
        // closures below is safe -- the SAFETY here comes from the mutex's own locking, not
        // from the region checker, so `nonisolated(unsafe)` is the sanctioned way to say that
        // rather than working around it with an unchecked wrapper type.
        nonisolated(unsafe) let resumed = Mutex(false)

        let winner = await withCheckedContinuation { (continuation: CheckedContinuation<String?, Never>) in
            // Deliberately unstructured and never awaited by this function -- if it never
            // completes, it is abandoned, not held open past the budget.
            Task {
                let name = (try? await box.value.mapItems)?.first?.addressRepresentations?.cityName
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    guard !alreadyResumed else { return false }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    continuation.resume(returning: name)
                }
            }

            Task {
                try? await Task.sleep(for: budget)
                let shouldResume = resumed.withLock { alreadyResumed -> Bool in
                    guard !alreadyResumed else { return false }
                    alreadyResumed = true
                    return true
                }
                if shouldResume {
                    box.value.cancel()
                    continuation.resume(returning: nil)
                }
            }
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
