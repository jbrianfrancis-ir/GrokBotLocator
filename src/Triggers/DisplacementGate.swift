import CoreLocation
import Foundation

/// A coordinate pair with no dependency on CoreLocation's own type: `CLLocationCoordinate2D` is
/// not `Equatable` and carries no `Sendable` guarantee, both of which this codebase wants to
/// lean on for a value passed between an actor-isolated coordinator and a pure decision type.
struct TriggerCoordinate: Sendable, Equatable {
    let latitude: Double
    let longitude: Double

    init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }

    /// The only bridge from a fix to a coordinate the gate can compare.
    init(fix: LocationFix) {
        self.latitude = fix.latitude
        self.longitude = fix.longitude
    }
}

/// REQ-06's 500 m decided in app code, never taken on trust from the significant-change
/// callback. RESEARCH.md Q3: significant-change is OS-determined and approximate -- it also
/// fires on a cell-tower handoff, so the callback is a WAKE signal, not evidence of 500 m of
/// travel. "The callback is the wake signal; the threshold must be enforced in app code." This
/// type is that enforcement: a pure function of two coordinates, with no location manager, no
/// clock and no disk, so a 300 m move and a 500 m move are both provable with no device.
///
/// With NO reference coordinate -- a fresh install, or a cold background relaunch before the
/// reference is rehydrated -- `shouldPing` returns `true`. This is a BACKSTOP decision, not
/// derived from REQUIREMENTS.md: REQ-06 defines the move as "from the last ping" and says
/// nothing about there being no last ping. Adopting the fix silently and waiting for the next
/// wake is equally defensible, and would mean a phone that never had a manual ping tapped never
/// auto-pings at all. See this plan's `backstop_truths`.
struct DisplacementGate: Sendable, Equatable {
    /// REQ-06: "at least 500 m (fixed, not configurable)". A `static let` with no initialiser
    /// parameter and no setter, so "fixed" is enforced by the type rather than promised in a
    /// comment.
    static let minimumMetres: Double = 500

    /// The ellipsoidal distance between two coordinates, in metres -- `CLLocation.distance(from:)`
    /// is the same measurement CoreLocation itself uses, so this type does not invent its own
    /// notion of distance.
    static func distanceMetres(from: TriggerCoordinate, to: TriggerCoordinate) -> Double {
        let fromLocation = CLLocation(latitude: from.latitude, longitude: from.longitude)
        let toLocation = CLLocation(latitude: to.latitude, longitude: to.longitude)
        return fromLocation.distance(from: toLocation)
    }

    /// `true` when there is no reference to compare against (the backstop above), or when the
    /// candidate is at least `minimumMetres` from the reference. `false` for anything short of
    /// that, regardless of why the significant-change callback fired.
    static func shouldPing(from reference: TriggerCoordinate?, to candidate: TriggerCoordinate) -> Bool {
        guard let reference else {
            return true
        }
        return distanceMetres(from: reference, to: candidate) >= minimumMetres
    }
}
