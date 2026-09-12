import CoreLocation
import Foundation

/// The app's SECOND `CLLocationManager` -- the first, in `CoreLocationFixProvider.swift`,
/// serves one-shot manual fixes at When-In-Use and must keep working, untouched, at that
/// authorization level. Two are correct here because the two owners have different lifetimes:
/// a manual fix starts, gets one location, and stops; this proxy arms significant-change and
/// visit monitoring once Always is granted and keeps that registration alive for as long as
/// either trigger stays switched on in Settings.
///
/// ARCHITECTURE's Forbidden continuous-background-GPS call pattern -- described here by what it
/// is, never by its literal API names, because scripts/smoke.sh bans those names outright,
/// everywhere, with no exemption for a doc comment -- does not appear anywhere in this file.
/// This proxy only ever arms significant-change and visit monitoring, both wake/hardware-assisted
/// (RESEARCH.md Q3/Q6), never a continuously-polling foreground GPS session.
///
/// `CLLocationManagerDelegate` is a plain, synchronous ObjC-bridged protocol with no isolation
/// annotation of its own (RESEARCH.md Q5); CoreLocation delivers its callbacks "on the runloop
/// from the thread on which you initialized [the manager]". Marking this whole class
/// `@MainActor` both satisfies ARCHITECTURE's rule that all location work sits in one
/// actor-isolated coordinator and keeps the manager on the thread it expects. Swift 6.3.3's
/// strict checking will not accept a `@MainActor` type satisfying an unannotated protocol's
/// requirements silently -- the conformance itself is annotated `@MainActor` below (rather than
/// downgrading the whole conformance with `@preconcurrency`, which would trade a compile-time
/// guarantee for a runtime one) so every delegate method stays statically proven to run on the
/// same actor as the manager and the stored handler closures it calls into.
@MainActor
final class LocationDelegateProxy: NSObject, @MainActor CLLocationManagerDelegate, LocationTriggerSource {
    private let manager = CLLocationManager()

    /// Held for the lifetime of this proxy once ANY trigger is armed. RESEARCH.md Q2/Q5,
    /// quoting WWDC24's "What's new in location authorization": "Always authorization will only
    /// be effective when you hold one of these [`CLServiceSession`], and you can only start
    /// holding one when your app is in the foreground." `beginAlwaysSession()` below is that
    /// foreground touchpoint; this session, once created, is what is supposed to keep Always
    /// effective afterward.
    ///
    /// It is deliberately NOT created inside `requestAlways()` any more (debug/001). A grant is
    /// durable and a session is not: a cold relaunch of an app already holding `.authorizedAlways`
    /// has nothing to request, so hanging session creation off the request skipped it on exactly
    /// the launch that needed it, and REQ-08 never fired. The two concerns are now two calls.
    ///
    /// Spelling confirmed against the live DocC page for `CLServiceSession` on 2026-09-11 (the
    /// page RESEARCH.md's `## Unverified` section could not reach in the research pass):
    /// `final class CLServiceSession: Sendable, SendableMetatype` with
    /// `init(authorization: CLServiceSession.AuthorizationRequirement)`, and
    /// `AuthorizationRequirement` cases `.always`, `.whenInUse`, `.none`. See this plan's
    /// SUMMARY for the fetch. Which of "holding this session" vs. iterating `CLMonitor.events`
    /// (RESEARCH: implicit sessions are on by default) actually keeps Always effective on device
    /// is still unsettled -- that is this plan's backstop truth, not something this session
    /// object resolves by existing.
    private var serviceSession: CLServiceSession?

    private var significantChangeHandler: (@Sendable (SignificantChangeReport) async -> Void)?
    private var visitHandler: (@Sendable (VisitReport) async -> Void)?

    override init() {
        super.init()
        manager.delegate = self
    }

    func setHandlers(
        significantChange: @escaping @Sendable (SignificantChangeReport) async -> Void,
        visit: @escaping @Sendable (VisitReport) async -> Void
    ) async {
        significantChangeHandler = significantChange
        visitHandler = visit
    }

    func startSignificantChange() async {
        manager.startMonitoringSignificantLocationChanges()
    }

    func stopSignificantChange() async {
        manager.stopMonitoringSignificantLocationChanges()
    }

    func startVisits() async {
        manager.startMonitoringVisits()
    }

    func stopVisits() async {
        manager.stopMonitoringVisits()
    }

    func currentAuthorization() async -> CLAuthorizationStatus {
        manager.authorizationStatus
    }

    /// The one place this proxy starts holding a `CLServiceSession`, per the foreground-only rule
    /// in the doc comment above. Asks for nothing: constructing the session is what makes an
    /// existing Always grant effective, and the coordinator calls this on every foreground arming
    /// pass whatever the current status is.
    func beginAlwaysSession() async {
        if serviceSession == nil {
            serviceSession = CLServiceSession(authorization: .always)
        }
    }

    /// The point-of-use Always request (REQ-10): reached only from enabling a trigger while the
    /// app is not already authorized for Always, never at launch and never from a view. iOS
    /// grants Always only as an upgrade from When-In-Use, so an undetermined status asks for
    /// When-In-Use first. Holding the session is `beginAlwaysSession()` above, not this.
    func requestAlways() async -> CLAuthorizationStatus {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        manager.requestAlwaysAuthorization()

        // The SAME bounded poll CoreLocationFixProvider.currentFix() already uses: 250ms x 240 =
        // 60s, then give up and report whatever the status now is. LEARNINGS/that file both
        // record why the bound exists -- an unbounded wait here would hold a Settings toggle
        // spinning for the life of the process if the user backgrounds the app at the prompt.
        var pollCount = 0
        while manager.authorizationStatus == .notDetermined, pollCount < 240 {
            try? await Task.sleep(for: .milliseconds(250))
            pollCount += 1
        }

        return manager.authorizationStatus
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // `CLLocation` conforms to `Sendable` (RESEARCH.md Q5), so no shim is needed to read it
        // here -- but the report crossing into the coordinator via the `Task` below is still
        // built from it at the point of receipt, same as the visit case.
        guard let location = locations.last, let handler = significantChangeHandler else { return }
        let report = SignificantChangeReport(
            coordinate: TriggerCoordinate(
                latitude: location.coordinate.latitude, longitude: location.coordinate.longitude),
            accuracyMetres: location.horizontalAccuracy,
            timestamp: location.timestamp)
        Task { await handler(report) }
    }

    func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
        // CoreLocation's visit type does NOT conform to `Sendable` (RESEARCH.md Q5), so every
        // field this app needs is read out into a local `Sendable` struct HERE, inside this
        // synchronous delegate method, before the `Task` below crosses into the actor-isolated
        // coordinator. The raw value itself never crosses that boundary.
        guard let handler = visitHandler else { return }
        let report = VisitReport(
            coordinate: TriggerCoordinate(
                latitude: visit.coordinate.latitude, longitude: visit.coordinate.longitude),
            accuracyMetres: visit.horizontalAccuracy,
            arrivalDate: visit.arrivalDate,
            departureDate: visit.departureDate)
        Task { await handler(report) }
    }
}
