# Phase 04 research — automatic triggers (significant-change, visits, CLMonitor, rate limit, reverse geocoding)

Scope: answers Q1–Q6 as asked by the phase-04 plan brief. Sourced against Apple's live DocC JSON
(`https://developer.apple.com/tutorials/data/documentation/...`) fetched 2026-09-11, which reflects
the current iOS 26.0 SDK documentation, plus WWDC24 session content and community corroboration
where DocC prose was thin. Every claim below is dated 2026-09-11 unless marked otherwise.

---

## Q1 — Reverse geocoding: `CLGeocoder` vs `MKReverseGeocodingRequest` (MANDATORY — resolves REQUIREMENTS.md:34)

**`CLGeocoder` is soft-deprecated as of iOS 26.0.** Apple's own DocC metadata for the class carries,
for every platform (iOS, iPadOS, Mac Catalyst, macOS, tvOS, visionOS, watchOS):
```json
{"deprecatedAt":"26.0","introducedAt":"5.0","message":"Use MapKit"}
```
Source: https://developer.apple.com/documentation/corelocation/clgeocoder (DocC JSON, fetched
2026-09-11). Note the `deprecated` boolean itself reads `false` in that same payload — this is
Apple's doc-tooling convention for "deprecated as of the version this doc build documents," and the
build in question documents iOS 26.0, i.e. `deprecatedAt` and the SDK version are the same number.
Practically: building against the iOS 26 SDK will show a deprecation warning on `CLGeocoder`,
message "Use MapKit." No numbered replacement method is named on the class page itself, but the
message is unambiguous.

Oddly, `CLPlacemark` — the type `CLGeocoder` returns — is *not yet* deprecated at 26.0; its
`deprecatedAt` is **27.0**, one cycle later, message "Use either GeoToolbox.PlaceDescriptor or
MapKit." So as of today's SDK, `CLGeocoder` is flagged but its own return type technically is not
yet. Apple's replacement path is MapKit regardless of that inconsistency; do not lean on the
CLPlacemark grace period.

**`MKReverseGeocodingRequest` exists on iOS 26, in `MapKit`** (not CoreLocation):
```json
{"introducedAt":"26.0","deprecated":false}
```
Source: https://developer.apple.com/documentation/mapkit/mkreversegeocodingrequest (DocC JSON).

API shape, confirmed from the DocC page's own declarations and Apple's sample code on that page:
```swift
// Failable init — nil if the location is invalid
if let request = MKReverseGeocodingRequest(location: someCLLocation) {
    let mapItems = try? await request.mapItems        // Apple's own sample uses this form
    // or, per the declared member list: request.getMapItems(completionHandler:)
    if let item = mapItems?.first {
        let locality = item.addressRepresentations?.cityName   // String?
    }
}
```
- `init(location: CLLocation)` is a **failable** initializer (`init?`).
- The declared, DocC-listed instance members are: `location`, `isLoading`, `isCancelled`,
  `cancel()`, `preferredLocale`, and `getMapItems(completionHandler:) -> Void`. Apple's own sample
  code on the same page calls `try? await request.mapItems` as an async throwing property — this is
  the standard completion-handler→async bridging Swift/Apple applies, and it is Apple's own
  recommended usage even though the topic list surfaces the completion-handler form. Trust the
  sample; both are the same request.
- Result type: `[MKMapItem]`.
- **Getting a locality string**: `MKMapItem` does **not** have a `.locality`/`.city` field directly.
  Use `mapItem.addressRepresentations?.cityName: String?` (from `MKAddressRepresentations`, new in
  iOS 26 alongside this API) — that is the structured city field. `mapItem.address?.fullAddress` /
  `.shortAddress` are full formatted strings, not a locality alone.
  `mapItem.placemark` (an `MKPlacemark`) also exists but **`MKPlacemark` is itself deprecated at
  26.0**, message: "Use `MKMapItem`'s location, address and addressRepresentations properties
  instead." Do not route through `mapItem.placemark.locality`.

**Critical architectural consequence — flagged, not decided here:** ARCHITECTURE.md's
`## Frameworks & libraries` list (lines 24–30) names CoreLocation, Security, Foundation `URLSession`,
Network `NWPathMonitor`, BackgroundTasks, and Swift Testing. **It does not list MapKit.** Following
Apple's own guidance for reverse geocoding on iOS 26 means importing `MapKit`, a framework not
currently on the allowlist. MapKit is first-party Apple SDK, so it does **not** trip the "Zero
third-party dependencies" principle — but the Frameworks & libraries list is itself treated as
closed/binding by this document's own framing, so adding to it is a change to law, not an
implementation detail. See **Needs a human ruling** below for the exact line.

**Rate limits / offline behavior:**
- `CLGeocoder`: "Geocoding requests are rate-limited for each app, so making too many requests in a
  short period of time may cause some of the requests to fail. When the maximum rate is exceeded,
  the geocoder passes an error object with the value `CLError.Code.network`." No numeric rate is
  published. Offline behavior is documented similarly: the geocoder needs network access for full
  placemark detail; without it, it "may still report an error to your completion block" — using the
  **same** generic network-flavored error surface as rate-limiting. Source:
  https://developer.apple.com/documentation/corelocation/clgeocoder and
  .../clgeocoder/reversegeocodelocation(_:completionhandler:) (DocC JSON).
  Practical consequence: the app **cannot reliably distinguish** "offline" from "rate-limited" from
  the error alone with `CLGeocoder`.
- `MKReverseGeocodingRequest`: no numeric rate limit or offline-specific error documentation was
  found on its DocC page in this pass (it does expose `isLoading`/`isCancelled` and a plain
  `cancel()`, and is `async throws`, implying failures surface as a thrown `Error`, presumably an
  `MKError` case) — **this is unverified**; the phase 04 plan should not assume MapKit's replacement
  has looser or better-documented rate/offline semantics than `CLGeocoder` just because it's newer.

---

## Q2 — `CLMonitor` on iOS 26 (REQ-08)

Source: https://developer.apple.com/documentation/corelocation/clmonitor (redirects to the
hash-suffixed canonical page; DocC JSON fetched from the resolved URL) plus
https://twocentstudios.com/2024/12/02/core-location-modern-api-tips/ and Apple Developer Forum
threads 736099 / 769113 / 731294 for corroboration where Apple's own DocC prose was thin/empty.

**Creating/obtaining a monitor:**
```swift
let monitor = await CLMonitor("last-ping-region")   // init(_ name: String) async
```
The initializer is `async` and keyed by a `name: String`. Apple's own DocC prose for this
initializer is empty in the current build, so the persistence claim below is **not a direct Apple
quote** — it is inferred from the `async` signature (implies I/O) and corroborated by community
sources describing `CLMonitor(name:)` as reattaching to a monitor's previously-registered condition
set when called again with the same name, including after a relaunch. Treat "persists to disk under
its name across launches" as **moderately confident, not Apple-prose-verified**.

**Adding a condition:**
```swift
struct CircularGeographicCondition {
    let center: CLLocationCoordinate2D
    let radius: CLLocationDistance
    init(center: CLLocationCoordinate2D, radius: CLLocationDistance)
}
await monitor.add(CLMonitor.CircularGeographicCondition(center: coord, radius: 150),
                   identifier: "last-ping-region")
```
`add(_:identifier:)` wraps the condition into a `CLMonitor.Record` and starts state `.unknown`.

**Consuming events — genuinely async-sequence-native, no delegate:**
```swift
for try await event in await monitor.events {
    switch event.state {
    case .satisfied:   // entered
    case .unsatisfied: // exited
    default: break
    }
}
```
`events: CLMonitor.Events` (declared `final let events: CLMonitor.Events`) is the async sequence.
`CLMonitor.Event` fields (from its DocC member list): `identifier: String`, `state:
CLMonitor.Event.State`, `date: Date`, `refinement: (any CLCondition)?`, plus diagnostic booleans
`accuracyLimited`, `authorizationDenied`, `authorizationDeniedGlobally`,
`authorizationRequestInProgress`, `authorizationRestricted`, `conditionLimitExceeded`,
`conditionUnsupported`, `insufficientlyInUse`, `persistenceUnavailable`, `serviceSessionRequired`.
**`CLMonitor.Event` conforms to `Sendable`** (see Q5).

**Enumerating / removing to avoid leaking regions:**
```swift
let existing: [String] = await monitor.identifiers      // var identifiers: [String] { get }
await monitor.remove("old-region-id")                     // func remove(_ identifier: String)
```
To re-register at a new location (REQ-08: "re-registers at the new location"): either reuse a fixed
identifier (`add` with the same identifier replaces the prior condition under it) or read
`identifiers`, `remove` the stale one, then `add` the new one. Either avoids leaking regions.

**Region limit:** Apple's own DocC exposes a `conditionLimitExceeded: Bool` diagnostic flag directly
on `CLMonitor.Event`, confirming a limit exists and is surfaced per-event rather than as a hard
rejection at `add()` time. The specific figure — **still 20 simultaneous conditions**, with
overflow conditions delivered one event each at state `.unmonitored` and `conditionLimitExceeded ==
true` — is corroborated by two independent forum threads (736099, 769113) but was **not found
stated as a number in Apple's own CLMonitor DocC prose** in this pass; treat "20" as
community-sourced, not Apple-quoted. It doesn't matter much for REQ-08: the app needs exactly one
active geofence at a time, far under any plausible limit.

**Persistence across app launches / process death, and what wakes a terminated app:** `CLMonitor`
conditions ride the same underlying region-monitoring wake mechanism as classic
`CLLocationManager` region monitoring — a terminated app is relaunched into the background when a
condition's state changes. This is corroborated (not Apple-DocC-quoted for `CLMonitor` specifically)
by community source: "`.always` permission gives your app the opportunity to be cold launched in the
background in response to significant location change, visits, and region monitoring services" if
previously terminated. **Depends on holding an Always `CLServiceSession`** — see Q5's
`CLServiceSession` note: per Apple's WWDC24 "What's new in location authorization" session, "Always
authorization will only be effective when you hold one of these [`CLServiceSession`], and you can
only start holding one when your app is in the foreground." Implicit sessions are enabled by
default when you iterate `CLMonitor.events`, so this may already be handled unless the app opts out
via `NSLocationRequireExplicitServiceSession` in Info.plist (do not set that key unless a later
plan deliberately wants explicit session control). **Operational consequence for phase 04:** the
Always-authorization session needs to be live while the app is foregrounded at the moment triggers
are (re-)armed; it cannot be freshly acquired from a background wake.

## Q2 addendum — CLMonitor persistence, measured

**2026-09-11.** A throwaway probe app (XcodeGen 2.46.0, iOS 26 simulator, outside this repo, never
committed — bundle id `com.throwaway.clmonitorprobe`) replaced the inference above with a
measurement. The probe's `.task` builds `let m = await CLMonitor("CLMonitorPersistenceProbe")`,
appends `launch=\(await m.identifiers.count)` to `probe.log`, adds a 150 m circular condition when
that count is 0 and appends `after-add=\(await m.identifiers.count)`, then consumes `await
m.events` and appends `event=\(event.state)` per event. Counts and identifiers only — never a
coordinate — in anything written or printed, matching Task 1's constraint.

Commands run, in order (`UDID` resolved via the throwaway project's own simulator, an iPhone 17
Pro):
```
xcodegen generate
xcodebuild build -project CLMonitorProbe.xcodeproj -scheme CLMonitorProbe \
  -destination "id=$UDID" CODE_SIGNING_ALLOWED=NO
xcrun simctl install "$UDID" <built .app>
xcrun simctl privacy "$UDID" grant location-always com.throwaway.clmonitorprobe
xcrun simctl launch "$UDID" com.throwaway.clmonitorprobe          # first launch
xcrun simctl terminate "$UDID" com.throwaway.clmonitorprobe
xcrun simctl launch "$UDID" com.throwaway.clmonitorprobe          # cold relaunch under test
xcrun simctl location "$UDID" set 40.0559000,17.9925000            # settle at the region centre
xcrun simctl location "$UDID" start --speed=20 --distance=50 \
  40.0559000,17.9925000 40.0577012,17.9925000                     # req06-start.gpx -> req08-hop1.gpx waypoints
```
**Deviation from the plan's literal command:** `xcrun simctl location start` on this Xcode/simctl
build takes `lat,lon` pairs as positional arguments, not `.gpx` file paths (`--help` confirms only
`set <lat,lon>` / `start <lat1,lon1> <latN,lonN>...`; passing a `.gpx` path fails with `Invalid
latitude,longitude pair`). The two waypoints above are the exact coordinates
`scripts/gpx/req06-start.gpx` and `scripts/gpx/req08-hop1.gpx` carry, extracted and passed as
pairs so the movement is still the real interpolated kind (`--speed=20 --distance=50`), never a
teleport — the same substance VERIFICATION.md's REQ-06 evidence used. This is a CLI-syntax
correction, not a change to what was measured.

Verbatim `probe.log` lines, in order:
```
launch=0
after-add=1
launch=1
event=CLMonitoringState(rawValue: 1)
```

**Verdict:** `launch=0` / `after-add=1` on the first install confirms the condition was added.
`launch=1` on the SECOND launch — after `simctl terminate` genuinely killed the process — confirms
the condition **survived the process death and was recovered by a freshly-constructed
`CLMonitor(name:)` in the new process**, with no `add` call in that run. That settles cause (b)
from VERIFICATION.md's REQ-08 entry: on the simulator, `CLMonitor(name:)` DOES persist its
condition set across a cold relaunch. The `event=` line, produced only after driving real
interpolated movement out of the 150 m radius, settles cause (a) the same direction: `CLMonitor`
events ARE delivered to a running simulator process — the earlier REQ-08 non-reproduction was not
"the simulator never delivers these events at all."

This does not, by itself, explain VERIFICATION's original NOT-REPRODUCED result — that run's app
was not observing `CLMonitor.events` at all in a geofence-only cold-relaunch configuration, which
is exactly the gap D-16 and this plan's Tasks 2-3 close. D-16 authorizes the durable last-ping
file regardless of this verdict: belt-and-braces here (the region persisted on its own in this
measurement), load-bearing wherever it does not (a real device, a different iOS build, or a
simulator reset that clears CLMonitor's own state).

---

## Q3 — Significant-change (REQ-06) and visits (REQ-07) monitoring on iOS 26

Both `CLLocationManager.startMonitoringSignificantLocationChanges()` (introduced iOS 4.0) and
`.startMonitoringVisits()` (introduced iOS 8.0) show **`deprecated: false`** in the current DocC
JSON — both remain the supported, delegate-based path. **No async-sequence replacement exists for
either.** `CLLocationUpdate.liveUpdates()` (iOS 17.0+) is a separate, continuous-location-updates
API — it is not a drop-in modern form of significant-change or visits, and using it continuously
would itself risk brushing against ARCHITECTURE's Forbidden continuous-GPS clause; it is not
recommended as a substitute here.
Sources: https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()
and .../startmonitoringvisits() (DocC JSON).

**Terminated-app wake, named launch key (significant-change, quoted from Apple's own doc):**
> "If you start this service and your app is subsequently terminated, the system automatically
> relaunches the app into the background if a new event arrives. In such a case, the options
> dictionary passed to the `application(_:willFinishLaunchingWithOptions:)` and
> `application(_:didFinishLaunchingWithOptions:)` methods of your app delegate contains the key
> `location` to indicate that your app was launched because of a location event."

That is `UIApplication.LaunchOptionsKey.location`. **Visits' own doc text says the system relaunches
the app the same way** ("If your app is terminated while this service is active, the system
relaunches your app when new visit events are ready to be delivered... You don't need to call this
method again to restart the delivery of visit events") but **does not itself name the launch-options
key** in the fetched text — attributing the same `.location` key to a visits-triggered launch is
reasonable by convention (same subsystem) but is **not independently Apple-quoted for visits**; mark
as moderate confidence, not verified.

A merely-**suspended** (not terminated) app receives both via the ordinary delegate callback on the
still-running process — no special launch path, no launch-options key involved.

**REQ-06's 500 m threshold — OS-determined, not app-controllable, and only approximate:**
Significant-change explicitly "does not rely on the value in the `distanceFilter` property to
generate events" (Apple's own doc, quoted above the launch-key excerpt). The ~500 m figure itself
comes from Apple's classic "Getting the User's Location" guide and is corroborated across multiple
sources as: the service fires "as soon as the device moves 500 meters **or more** from its previous
notification" **or when the device changes cell towers** — i.e. a cell-tower handoff alone can fire
the callback even when physical displacement is under 500 m. **State plainly, as the brief asked:
the distance is OS-determined, and it is not a hard, exact 500.00 m cutoff.** REQ-06's acceptance
clause ("a 300 m move delivers none") cannot be satisfied by trusting the raw callback — phase 04's
plan must have the app record the coordinate of the last ping and compute actual displacement
against each new fix delivered by the significant-change callback, only proceeding to ping when that
computed distance is ≥ 500 m. The callback is the *wake signal*; the *threshold* must be enforced in
app code.

**`CLBackgroundActivitySession`** (iOS 17.0+, not deprecated) is a *`.whenInUse`* convenience — "Use
`CLBackgroundActivitySession` to start a background activity session that allows a when-in-use
authorized app to receive location updates or monitoring events" — it keeps a when-in-use app alive
in the background without a Live Activity. It is **not** a substitute for Always authorization and
does not itself enable the terminated-app relaunch behavior REQ-06/07/08 depend on; it's out of
scope for these three triggers, which need `.always`.

---

## Q4 — `Info.plist` / `project.yml` (XcodeGen 2.46.0) requirements

**Usage-description keys** (both still current at iOS 26.0 min deployment target; verified via DocC):
- `NSLocationWhenInUseUsageDescription` (introduced iOS 11.0, not deprecated) — baseline, already
  needed by phase 02's manual ping.
- `NSLocationAlwaysAndWhenInUseUsageDescription` (introduced iOS 11.0, not deprecated) — required
  additionally to request `.always`.
- `NSLocationAlwaysUsageDescription` is **deprecated since iOS 10** and only relevant for targets
  deploying below iOS 11 — irrelevant here at a 26.0 minimum; do not add it.

**`UIBackgroundModes`** must include the string **`location`** for the app to be woken/relaunched for
significant-change, visits, and `CLMonitor` region events while suspended or terminated. The full,
current enumerated set of legal values (from Apple's `UIBackgroundModes` DocC page) is: `audio,
bluetooth-central, bluetooth-peripheral, external-accessory, fetch, location, nearby-interaction,
network-authentication, newsstand-content, processing, push-to-talk, remote-notification,
screen-capture, voip`.

**`BGAppRefreshTask`** requires the separate string **`fetch`** in the same array — Apple's own doc:
"Executing app refresh tasks requires setting the `fetch` `UIBackgroundModes` capability" — plus a
`BGTaskSchedulerPermittedIdentifiers` array in Info.plist naming the refresh task's identifier
string. `fetch` and `location` are independent flags; phase 04 needs both (queue drain via
`BGAppRefreshTask` was already scoped to phase 03/04 per ROADMAP; location wake is new in phase 04).

**Collision check — the specific ask in the brief:** the background-mode string required for
wake-based monitoring is **`location`** — this **is the exact same `UIBackgroundModes` string** a
continuous-background-GPS app would also declare (there's only one `location` background mode;
Apple doesn't have a separate flag for "continuous" vs "wake-based"). **Flagging this loudly as
requested:** ARCHITECTURE.md's Forbidden list bans the *API call pattern* — `startUpdatingLocation` +
`allowsBackgroundLocationUpdates` — not the Info.plist key, and the key itself is unavoidable for any
`.always`-based wake mechanism, forbidden or not. But ARCHITECTURE.md currently says nothing at all
about `UIBackgroundModes`, so nothing on paper currently distinguishes "we declared `location` for
compliant wake-based monitoring" from "we declared `location` for the forbidden continuous-GPS
pattern" — a future reviewer scanning `project.yml` for the string `location` could reasonably flag
it against the Forbidden clause without the code-level distinction spelled out anywhere in law. This
needs a documented allowance, not a workaround. See **Needs a human ruling**.

**`project.yml` shape** (XcodeGen 2.46.0 — plain Info.plist array, no special "capability" object
needed):
```yaml
targets:
  GrokBotLocator:
    info:
      properties:
        NSLocationWhenInUseUsageDescription: "..."
        NSLocationAlwaysAndWhenInUseUsageDescription: "..."
        UIBackgroundModes: [location, fetch]
        BGTaskSchedulerPermittedIdentifiers: ["<reverse-dns task id>"]
```

---

## Q5 — Swift 6 strict concurrency: bridging `CLLocationManagerDelegate` into one actor

`CLLocationManagerDelegate` remains a plain `NSObjectProtocol`-based delegate with synchronous,
non-`async` methods and no `@MainActor`/isolation annotation visible in its DocC metadata.
`CLLocationManager`'s own doc states callbacks are delivered "on the runloop from the thread on
which you initialized [it]" — i.e., whatever thread you create the manager on (conventionally main),
not a fixed global-actor guarantee the compiler can check.

**Bridge pattern:** keep a small, non-actor `final class` (e.g. `LocationDelegateProxy: NSObject,
CLLocationManagerDelegate`) that owns the `CLLocationManager`, is created on the main thread, and
whose delegate methods do nothing but hop into the actor-isolated coordinator:
```swift
func locationManager(_ manager: CLLocationManager, didVisit visit: CLVisit) {
    let payload = VisitPayload(coordinate: visit.coordinate,
                                horizontalAccuracy: visit.horizontalAccuracy,
                                arrivalDate: visit.arrivalDate,
                                departureDate: visit.departureDate)   // Sendable struct
    Task { await coordinator.handleVisit(payload) }
}
```
An `actor` cannot itself conform to `CLLocationManagerDelegate` cleanly (the protocol's methods are
synchronous/non-async, so an actor would need `nonisolated` methods that then schedule actor work
anyway) — the small delegate-proxy class doing exactly that hop is the standard, and effectively
only, idiom.

**Sendable status, verified from each type's DocC "Conforms To" list:**
- **`CLLocation` conforms to `Sendable`** (and `SendableMetatype`) — safe to pass directly across the
  actor boundary with no wrapping needed.
- **`CLVisit` does NOT conform to `Sendable`** in its DocC conformance list (only `CVarArg,
  CustomDebugStringConvertible, CustomStringConvertible, Equatable, Hashable, NSCoding, NSCopying,
  NSObjectProtocol, NSSecureCoding`). Under complete Swift 6 concurrency checking, handing a raw
  `CLVisit` into an actor-isolated method will not type-check as Sendable. **The delegate proxy must
  extract the needed fields into a local `Sendable` struct before crossing into the actor** — as
  shown above.
- **`CLMonitor.Event` conforms to `Sendable`** (and `SendableMetatype`) — safe to pass directly. This
  matters less than it sounds: `CLMonitor.events` is already consumed via `for try await event in
  monitor.events`, which the coordinator actor can iterate directly inside its own async method — no
  delegate/proxy bridging is needed for the `CLMonitor` path at all, only for significant-change and
  visits.
- Community source (twocentstudios) describes `CLMonitor` itself as implemented as an `actor` ("every
  one of its APIs requires an `await`") — consistent with the `async` `init(_:)` and `await
  monitor.add(...)` shapes found directly in its own DocC declarations.

---

## Q6 — SC-03 battery guidance (brief, sourced)

Apple's Energy Efficiency Guide for iOS Apps explicitly ranks these mechanisms and, somewhat
counter-intuitively, does **not** put significant-change at the top of the efficiency list: "Region
and visit monitoring are sufficient for most use cases and should always be considered before
significant-change location updates," because "significant-change location updates run continuously,
around the clock, until you stop them, and can actually result in higher energy use if not employed
effectively." Source:
https://developer.apple.com/library/archive/documentation/Performance/Conceptual/EnergyGuide-iOS/LocationBestPractices.html
(archived but still Apple's own published guidance; no iOS-26-specific replacement document was
found). All three mechanisms are wake/hardware-assisted (cell/Wi-Fi radios, not continuous GPS
polling), consistent with ARCHITECTURE's ban on continuous background GPS. **Practical read for
SC-03: REQ-06 (significant-change) is, by Apple's own admission, the least battery-friendly of
phase 04's three triggers, not the other two** — worth extra scrutiny in the phase 04 plan and in
SC-03's eventual measurement, even though REQ-06 is a Must-have and not optional.

---

## Unverified

- **`MKReverseGeocodingRequest`'s rate-limit and offline error semantics** — no numeric limit or
  offline-specific documentation found; do not assume it is more forgiving than `CLGeocoder` just
  because it is newer (Q1).
- **`CLMonitor(name:)`'s disk-persistence behavior** — settled by measurement — see Q2 addendum:
  on the iOS 26 simulator, a condition added in one process was recovered (`launch=1`, no re-add)
  by a fresh `CLMonitor(name:)` after `simctl terminate` killed the process, and a real
  interpolated move out of the region produced a delivered `event=` line in that same fresh
  process. Not yet checked on a real device or across a simulator/OS reset.
- **CLMonitor's 20-region limit as a specific number** — corroborated by two forum threads, not
  found stated as a number in Apple's own current CLMonitor DocC prose; Apple's DocC does confirm
  the *concept* via the `conditionLimitExceeded` event flag (Q2).
- **Visits' terminated-launch options key** — assumed to be the same `UIApplication.LaunchOptionsKey.location`
  used by significant-change, by convention; not independently quoted from Apple's visits doc text
  in this pass (Q3).
- **`CLServiceSession`'s exact Swift API surface** (initializer parameter names/cases) — the
  behavioral claims used above (implicit sessions on by default; Always "only effective when you
  hold one... and you can only start holding one when your app is in the foreground";
  `NSLocationRequireExplicitServiceSession` opt-out key) come from a WWDC24 session-transcript fetch
  and a corroborating forum thread, not from a directly fetched `CLServiceSession` DocC page (the
  page could not be located at a working URL in this pass). The **behavior** is reasonably
  well-corroborated by two independent sources; the **exact code spelling** is not. Whoever writes
  the phase 04 plan should pull the live `CLServiceSession` DocC page before committing to exact
  method/initializer names.

---

## Consequences for planning

1. **Reverse geocoding must go through `MapKit`'s `MKReverseGeocodingRequest`, not `CLGeocoder`** —
   but this cannot be finalized in a phase 04 plan until the ARCHITECTURE amendment below is
   authorized (adding MapKit to the Frameworks & libraries list). Until authorized, phase 04 planning
   should treat "empty label" as the safe default and not block on geocoding succeeding.
2. **REQ-06's 500 m threshold must be enforced in app code, not trusted from the OS callback.** Store
   the coordinate of the last ping (or last significant-change fix) and compute displacement against
   each new fix; only ping when computed distance ≥ 500 m. This directly affects how the plan
   partitions "receive wake" from "decide whether to ping."
3. **REQ-08's `CLMonitor` re-registration** should reuse a single fixed condition identifier (or
   explicitly `remove` before `add`) to avoid leaking regions across repeated ping-triggered
   re-registrations — trivial given the 20-region ceiling isn't close to being hit, but still worth
   a named test.
4. **The Always `CLServiceSession` must be (re)armed in the foreground.** Because Always is "only
   effective when you hold one, and you can only start holding one when your app is in the
   foreground" (Q2/Q5), phase 04's plan needs an explicit foreground touchpoint — app launch and/or
   whenever a trigger toggle is flipped on in Settings — rather than assuming background wakes can
   self-sustain authorization.
5. **`CLVisit` needs a `Sendable` shim before crossing into the actor-isolated coordinator;
   `CLLocation` and `CLMonitor.Event` do not.** The delegate-proxy class for significant-change and
   visits should convert payloads to local `Sendable` structs at the point of receipt; the
   `CLMonitor.events` async sequence can be consumed directly inside the coordinator with no proxy.
6. **SC-03 battery risk concentrates in REQ-06 (significant-change), not REQ-07/REQ-08**, per
   Apple's own energy guidance (Q6) — worth explicit attention (and possibly its own measurement)
   in the phase 04 plan rather than treating "all triggers on" as one uniform cost.
7. **`UIBackgroundModes: [location, fetch]` is required and expected** — this should be stated
   plainly in the phase 04 plan (and ideally in ARCHITECTURE.md, see below) so it is never mistaken
   for evidence of the Forbidden continuous-GPS pattern during a later audit.

## Needs a human ruling

- **Add MapKit to `ARCHITECTURE.md`'s `## Frameworks & libraries` list (currently lines 24–30).**
  `CLGeocoder` is soft-deprecated at iOS 26.0 ("Use MapKit"), and its replacement,
  `MKReverseGeocodingRequest`, lives in `MapKit`, a framework not currently on that list. Proposed
  line to add under the existing bullet list: `- MapKit — reverse geocoding
  (\`MKReverseGeocodingRequest\`); CLGeocoder/CLPlacemark are soft-deprecated as of iOS 26.0 SDK`.
  MapKit is first-party Apple SDK and does not violate "Zero third-party dependencies," but the
  Frameworks & libraries list is treated as a closed allowlist and a human should authorize the
  addition before phase 04's plan relies on it.
- **Document `UIBackgroundModes: location` as an expected, compliant declaration**, distinct from
  the Forbidden continuous-GPS *code pattern*. ARCHITECTURE.md currently says nothing about
  `UIBackgroundModes` at all, so there is no written line separating "declared for compliant
  wake-based monitoring" from "declared for the forbidden pattern" — both would produce the
  identical plist string. A one-line addition near the Forbidden entry (e.g., "`UIBackgroundModes:
  location` is required for significant-change/visits/`CLMonitor` wake and is compliant; the
  Forbidden entry bans the `startUpdatingLocation` + `allowsBackgroundLocationUpdates` call pattern,
  not this plist key") would close that gap before a future audit trips over it.
