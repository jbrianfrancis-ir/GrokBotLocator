# iOS 26 CoreLocation + Liquid Glass + Background Delivery — Research

Verified against live Apple Developer Documentation JSON (fetched 2026-09-09) and Apple HIG pages. Every API's `platforms`/`deprecated` metadata below was read directly from `developer.apple.com/tutorials/data/documentation/...json` for that symbol — not inferred from blog posts. Blog/forum sources are used only for framing and are flagged as such.

---

## Q1 — Current non-deprecated APIs for the four location tasks, and coexistence

**Actionable answer:**

| Task | API to use | Deprecated on iOS 26? |
|---|---|---|
| (a) One-shot fix | `CLLocationUpdate.liveUpdates(_:)` (async, preferred for an actor-isolated coordinator) **or** `CLLocationManager.requestLocation()` (delegate-based) | Neither deprecated |
| (b) Significant-change monitoring | `CLLocationManager.startMonitoringSignificantLocationChanges()` (delegate-based; no async replacement exists) | Not deprecated |
| (c) Visit monitoring | `CLLocationManager.startMonitoringVisits()` (delegate-based; no async replacement exists) | Not deprecated |
| (d) Circular-region exit monitoring | `CLMonitor` with a `CLMonitor.CircularGeographicCondition` (async `actor`-based; **is** the required path) | N/A — `CLLocationManager.startMonitoring(for:)` still works on iOS 26 but is scheduled for deprecation in iOS 27 |

**They coexist in one app.** All four are independent CoreLocation services keyed off the same `CLLocationManager`/authorization state; nothing about adopting `CLMonitor` for regions requires giving up `startMonitoringSignificantLocationChanges()`/`startMonitoringVisits()`, and `CLLocationUpdate.liveUpdates()` is a separate async stream layered on top. Apple's own "Adopting live updates in Core Location" and "Monitoring the user's proximity to geographic regions" articles describe these as complementary services, not alternatives to each other.

### Evidence

- **`CLLocationManager.startMonitoring(for:)`** — fetched `startmonitoring(for:).json`: `"platforms":[{"name":"iOS","deprecated":false,"introducedAt":"5.0","deprecatedAt":"27.0"}, ...]`, with `deprecationSummary`: "Use `CLMonitor.addConditionForMonitoring(identifier:)` instead." **This is the key nuance: as of the iOS 26 SDK it is not yet marked deprecated — `deprecatedAt` is iOS 27 — but Apple has already committed to deprecating it and is steering all new geofence code at `CLMonitor` today.**
  https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoring(for:)
- **`CLMonitor`** — introduced iOS 17.0, not deprecated, declared as `actor CLMonitor`. It's the async replacement for circular-region and beacon-region monitoring: create with `init(_ name: String) async`, register work with `add(_ condition: any CLCondition, identifier: String)`, and iterate the `events` async sequence for satisfied/unsatisfied (entry/exit) transitions via `CLMonitor.Event.state`.
  https://developer.apple.com/documentation/corelocation/clmonitor-2r51v
  https://developer.apple.com/documentation/corelocation/clmonitor-2r51v/circulargeographiccondition
- **`startMonitoringSignificantLocationChanges()`** — fetched JSON: `introducedAt: 4.0`, `deprecated: false`, `deprecationSummary: null`. No async-sequence alternative exists; it is still delegate-callback only (`CLLocationManagerDelegate.locationManager(_:didUpdateLocations:)`).
  https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringsignificantlocationchanges()
- **`startMonitoringVisits()`** — fetched JSON: `introducedAt: 8.0`, `deprecated: false`. Same story: delegate-only (`locationManager(_:didVisit:)`), no async equivalent.
  https://developer.apple.com/documentation/corelocation/cllocationmanager/startmonitoringvisits()
- **`CLLocationUpdate.liveUpdates(_:)`** — `static func liveUpdates(_ configuration: CLLocationUpdate.LiveConfiguration = .default) -> CLLocationUpdate.Updates`, introduced iOS 17.0, not deprecated. This is a continuous async stream (for a one-shot fix, take the first non-`isStationary` update from the sequence and stop iterating, or just use `requestLocation()` which is simpler for a single fix and also not deprecated). It is **not** a substitute for significant-change, visits, or region monitoring — it's Apple's modern replacement specifically for the old `startUpdatingLocation()`/delegate continuous-tracking pattern, and is explicitly forbidden continuous background use per this project's ARCHITECTURE.md anyway.
  https://developer.apple.com/documentation/corelocation/cllocationupdate
  https://developer.apple.com/documentation/corelocation/adopting-live-updates-in-core-location
- Apple's region-monitoring guide confirms the wake behavior: "In iOS, the system monitors regions and wakes up your app as needed when conditions change between satisfied and unsatisfied states... If an iOS app isn't running when a condition is satisfied, the system tries to launch it. When the app relaunches, recreate the monitor with the same identifier."
  https://developer.apple.com/documentation/corelocation/monitoring-the-user-s-proximity-to-geographic-regions

### Caveats

- `startMonitoring(for:)` is still callable on iOS 26 without a compiler warning, but treat it as a dead end for new code — Apple has published its iOS 27 deprecation date already, and `CLMonitor` is a strict superset of its functionality (regions + beacons) with better diagnostics (`CLMonitor.Record`, `CLMonitor.Event` state enum).
- `CLMonitor` requires an `actor` context (its initializer and mutating methods are `async`), which fits this project's "one actor-isolated coordinator" architecture directly.
- Regardless of which region API is used, monitoring only resumes "after the user unlocks the device after a reboot" per Apple's docs — a plan-level detail worth noting for the trip scenario.

---

## Q2 — Authorization, Info.plist, background modes, and entitlements for background wake by (b)/(c)/(d)

**Actionable answer:**

- **Authorization required:** `Always` (`NSLocationAlwaysAndWhenInUseUsageDescription`). `When In Use` never wakes a terminated app for any location event.
- **Info.plist keys:**
  - `NSLocationWhenInUseUsageDescription` — required whenever the app requests When in Use *or* Always.
  - `NSLocationAlwaysAndWhenInUseUsageDescription` — required whenever the app requests Always. (Both keys are required together for an Always request; there is no longer a standalone "Always only" key — that was retired years before iOS 26.)
- **Background Modes / entitlements:** The `UIBackgroundModes` → `location` Info.plist array entry (the "Location updates" capability in Xcode's Signing & Capabilities) is **not required** for (b)/(c)/(d) to wake a suspended or terminated app. That capability exists for *continuous* delivery while suspended (`CLBackgroundActivitySession` + `CLLocationUpdate.liveUpdates()`/`startUpdatingLocation()`), which this project's architecture explicitly forbids. Significant-change, visits, and region (`CLMonitor`) monitoring relaunch the app via the system's own location daemon regardless of that capability.
- **`CLServiceSession` / `CLBackgroundActivitySession` — do they apply here?** Yes, but only at the moment the app is *running* (foreground or freshly relaunched) and wants to keep processing events without being immediately re-suspended — they are not required merely to *receive* a wake-up event. Apple's background-handling guide states plainly: **"Core Location sets When in Use authorization implicitly when you process events from `CLMonitor`, `CLLocationUpdate`, or use a `CLBackgroundActivitySession`. The exception is if you set `NSLocationRequireExplicitServiceSession`."** In other words, for this project's use case (respond to a wake event, take a fix, POST, go back to sleep) you generally do **not** need to construct a `CLServiceSession`/`CLBackgroundActivitySession` at all — those exist for apps that need to hold the process open across a longer stretch of background time. If a trigger handler needs more than a few seconds to complete work in the background, wrap it in a `CLBackgroundActivitySession` (constructible only from the foreground; from the background you can only continue an already-running one).
- **What stops working at When In Use vs Always** (from Apple's official capability table, reproduced verbatim below): at When In Use, the system will **not** relaunch a terminated app for any location event — "the user must launch the app." At Always, the system **does** relaunch a terminated app for significant location change, visits, and region monitoring specifically (not for plain continuous updates). This matches REQ-10/REQ-08 exactly: manual pings work at When In Use; only automatic triggers need Always.
- **Provisional/temporary Always changes:** the old "provisional Always" grant (where accepting a When-in-Use-only prompt after requesting Always silently upgraded the app for a limited window) was eliminated back in iOS 13.4 — that mechanism does not exist on iOS 26. What iOS 26 (inherited from iOS 18's `CLServiceSession` model, introduced WWDC24) does instead: **Always authorization is only actually effective while the app holds a live `CLServiceSession` with `.always` as its goal**, and a session can only be *created* while the app is in the foreground; Core Location "requests a person's authorization to meet those requirements if possible, including automatically re-asking as needed after temporary authorization lapses due to time your app spends in the background." No iOS 26–specific change to this flow beyond what iOS 18 introduced was found in current documentation.

### Evidence

- Capability table, "Requesting authorization to use location services":

  | Capability | When in Use | Always |
  |---|---|---|
  | Supported platforms | All | All platforms except tvOS and visionOS |
  | Supported location services | All | All |
  | Launches a terminated app automatically | No. The user must launch the app. | Yes for significant location change, visits, and region monitoring services; no for others |

  Usage-key table from the same page:

  | Usage key | Required when |
  |---|---|
  | `NSLocationWhenInUseUsageDescription` | The app requests When in Use or Always authorization |
  | `NSLocationAlwaysAndWhenInUseUsageDescription` | The app requests Always authorization |
  | `NSLocationUsageDescription` | (macOS only) |

  https://developer.apple.com/documentation/corelocation/requesting-authorization-to-use-location-services

- "Handling location updates in the background" — the article that defines when the `location` background mode is actually needed, and how `CLServiceSession`/`CLBackgroundActivitySession` fit in: "The background mode capability lets the system know whether your app uses background updates... Create an instance of `CLBackgroundActivitySession` to start a background activity session so that you can receive location updates... Create a `CLServiceSession` requiring the relevant form of authorization... Create the session while your app is in the foreground. If your app terminates, you must recreate the `CLServiceSession` immediately upon launch in the background. Core Location sets When in Use authorization implicitly when you process events from `CLMonitor`, `CLLocationUpdate`, or use a `CLBackgroundActivitySession`. The exception is if you set the `NSLocationRequireExplicitServiceSession` in your app's Info.plist."
  https://developer.apple.com/documentation/corelocation/handling-location-updates-in-the-background
- `CLBackgroundActivitySession` — introduced iOS 17.0, not deprecated: "An object that manages a visual indicator that keeps your app in use in the background, allowing it to receive updates or events... Use to start a background activity session that allows a when-in-use authorized app to receive location updates or monitoring events." Creatable only `init()` from the foreground; from the background you may only continue an already-running session.
  https://developer.apple.com/documentation/corelocation/clbackgroundactivitysession-3mzv3
- `CLServiceSession` — introduced iOS 18.0, not deprecated: "A `CLServiceSession` object represents your app's current goal for location authorization... requests a person's authorization to meet those requirements if possible, including automatically re-asking as needed after temporary authorization lapses due to time your app spends in the background." Constructed via `init(authorization: CLServiceSession.AuthorizationRequirement)` where `AuthorizationRequirement` is `.always`, `.whenInUse`, or `.none`.
  https://developer.apple.com/documentation/corelocation/clservicesession-pt7n
- WWDC24 "What's new in location authorization" is the session that introduced `CLServiceSession` and this "session-driven Always" model for iOS 18 (carried forward unchanged into iOS 26 per current docs): https://developer.apple.com/videos/play/wwdc2024/10212/
- `UIBackgroundModes` (`Information Property List` key) possible value `location` exists and is unchanged; enabling it via Xcode's Signing & Capabilities "Location updates" toggle is what "updates your app's Info.plist file with the keys needed to indicate your app supports background updates" per the handling-background-updates article above.
  https://developer.apple.com/documentation/bundleresources/information-property-list/uibackgroundmodes
- Provisional-Always history (elimination in iOS 13.4): corroborated by multiple long-standing developer-forum threads on `requestAlwaysAuthorization` behavior; no current Apple doc still describes a provisional-Always window, and the "Requesting authorization" article above describes only the two discrete levels (When in Use, Always) with no intermediate state.

### Caveats

- No dedicated WWDC25/iOS 26 CoreLocation "what's new" session was found; the authorization model documented above is the iOS 18 `CLServiceSession` model as it stands, unchanged, in the current (iOS 26) documentation. Treat "iOS 26 changes" to authorization as **none found** rather than **confirmed none exist** — see Unverified section.
- A forum thread (not an official doc) claims that as of iOS 26, significant-location-change and region-monitoring relaunch of a **force-quit** (swiped away in the app switcher) app has become unreliable, whereas it still works reliably for an app merely *suspended* in the background. This is plausible — force-quit has never guaranteed relaunch for background location events even on older iOS versions per Apple's own background-URLSession docs pattern (see Q4) — but I could not confirm it against an official Apple source. Flagged in Unverified.
- Background App Refresh (the global/per-app Settings toggle) gates all of this: if the user disables it, the system does not relaunch the app for any location event even with Always granted. This is long-standing, widely-corroborated behavior but I could not locate it stated in the current CoreLocation doc pages fetched for this research; flagged in Unverified pending an official citation.

---

## Q3 — Liquid Glass in SwiftUI and accessibility for a glasses-free-readable UI

**Actionable answer:**

- **Adopt Liquid Glass on chrome, not on primary content.** Apple's HIG is explicit that Liquid Glass is a distinct functional layer for controls/navigation (tab bars, toolbars, sidebars) that floats *above* the content layer; putting it in the content layer ("app backgrounds") is called out as a design mistake — use **standard materials** there instead. This directly answers "is glass appropriate behind primary content": **no**, reserve `.glassEffect()` for toolbars, buttons, and floating controls; use `.background(.regularMaterial)`/standard materials or solid colors behind text-heavy primary content (ping history rows, settings form).
- **APIs that adopt it:**
  - `View.glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View` — introduced **iOS 26.0** (confirmed via live metadata). https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
  - `GlassEffectContainer` — groups multiple `glassEffect` views so they share a render pass, blend/morph shapes together, and animate coherently; use whenever more than one glass element appears near another. https://developer.apple.com/documentation/swiftui/glasseffectcontainer
  - `GlassEffectTransition`, `glassEffectID(_:in:)`, `glassEffectUnion(id:namespace:)` — coordinate morph animations between glass elements inside a container.
  - `Glass` struct (`.regular`, `.clear`, `.tint(_:)`, `.interactive(_:)`) — the effect configuration passed to `glassEffect`.
  - Toolbars, tab bars, sidebars, and standard buttons/sheets pick up Liquid Glass automatically from system frameworks with no code change — you opt in explicitly only for *custom* controls.
  - This app's realistic touch points: the "I'm here" button can use `.buttonStyle(.glass)` (system button style, automatic), and any custom floating action row could use `.glassEffect()`; the settings form and ping-history list should stay on standard materials/solid backgrounds since they're primary content, per the HIG rule above.
- **Reduce Transparency / Increase Contrast:** both are handled automatically by system Liquid Glass components. Reduce Transparency makes the glass "frostier" (more opaque, reduces content bleed-through); Increase Contrast "makes elements predominantly black or white and highlights them with a contrasting border." For custom `.glassEffect()` usage, read the environment values `accessibilityReduceTransparency: Bool` and `colorSchemeContrast: ColorSchemeContrast` (both confirmed live in `EnvironmentValues`) if a custom component needs a manual fallback beyond what the system material already does; most apps don't need to — "letting the system handle this automatically is the right choice."
- **Text-over-glass contrast minimum:** Apple's own Accessibility Inspector enforces WCAG-AA-derived thresholds (from the HIG Accessibility page, table reproduced below): **4.5:1 for text up to 17pt (any weight), 3:1 for 18pt+ or any bold text.** These are the same values used to judge any foreground-over-background pairing, including text over a glass surface. HIG's Materials page separately advises: if the *default* pairing doesn't clear this bar, "ensure it at least provides a higher contrast color scheme when the system setting Increase Contrast is turned on."
- **Dynamic Type up to the largest accessibility size (AX5 / `accessibilityExtraExtraExtraLarge`):** this is a text-scaling concern orthogonal to glass materials — glass surfaces don't cap type size, but Apple's guidance is to design as if the largest size is normal: "aim to display as much useful text at the largest accessibility font size as you do at the largest standard font size," avoid truncation, avoid multi-column layouts at large sizes, and keep primary elements near the top of the view so they don't scroll off-screen as rows grow tall. Apple's official guidance is to give people the option to enlarge text by **at least 200%** via Dynamic Type; standard SwiftUI `Text`/`Font.TextStyle` API gets this for free, custom fonts must replicate it manually.
- **Tap-target size — no iOS 26 change found.** HIG's Layout page specification table (fetched live) still gives, for iOS/iPadOS: **default control size 44×44pt, minimum 44×44pt as the design target, with an absolute floor of 28×28pt** for controls that can't reach the default (its own table header literally reads "Default control size" 44×44 / "Minimum control size" 28×28 — i.e. 44×44 remains the number to design to; 28×28 is the "don't go below this even in a pinch" floor, not a relaxed new default). No changelog entry mentions iOS 26 changing these numbers.

### Evidence

- HIG Materials — Liquid Glass placement rule: "Liquid Glass works best when it provides a clear distinction between interactive elements and content, and including it in the content layer can result in unnecessary complexity and a confusing visual hierarchy. Instead, use Standard materials for elements in the content layer, such as app backgrounds." Also: two variants, `regular` ("Use... when background content might create legibility issues, or when components have a significant amount of text, such as alerts, sidebars, or popovers") and `clear` (media-forward, needs a 35%-opacity dimming layer over bright content).
  https://developer.apple.com/design/human-interface-guidelines/materials
- `glassEffect(_:in:)` live doc — `nonisolated func glassEffect(_ glass: Glass = .regular, in shape: some Shape = DefaultGlassEffectShape()) -> some View`, platforms all show `introducedAt: 26.0`, `deprecated: false`.
  https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:)
- `GlassEffectContainer` and the "Applying Liquid Glass to custom views" developer article — container purpose, spacing-driven blend/morph behavior, `glassEffectUnion`, `glassEffectID`, performance guidance ("Limit the use of Liquid Glass effects onscreen at the same time").
  https://developer.apple.com/documentation/swiftui/glasseffectcontainer
  https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views
- `EnvironmentValues.accessibilityReduceTransparency: Bool` — "Whether the system preference for Reduce Transparency is enabled."
  https://developer.apple.com/documentation/swiftui/environmentvalues/accessibilityreducetransparency
- `EnvironmentValues.colorSchemeContrast: ColorSchemeContrast` — "The contrast associated with the color scheme of this environment."
  https://developer.apple.com/documentation/swiftui/environmentvalues/colorschemecontrast
- WWDC25 "Meet Liquid Glass" session content (accessibility behavior descriptions, corroborated by multiple independent write-ups of the same session): Reduce Transparency → "frostier," obscures more background; Increase Contrast → predominantly black/white elements with a contrasting border; Reduce Motion → disables elastic/lensing behavior. These are automatic for system-provided glass.
  https://developer.apple.com/videos/play/wwdc2025/219/
- HIG Accessibility — Vision section text-contrast table (fetched live table):

  | Text size | Text weight | Minimum contrast ratio |
  |---|---|---|
  | Up to 17 pts | All | 4.5:1 |
  | 18 pts | All | 3:1 |
  | All | Bold | 3:1 |

  and: "Ideally, give people the option to enlarge text by at least 200 percent... Your interface can support font size enlargement either through custom UI, or by adopting Dynamic Type... If your app doesn't provide this minimum contrast by default, ensure it at least provides a higher contrast color scheme when the system setting Increase Contrast is turned on."
  https://developer.apple.com/design/human-interface-guidelines/accessibility
- HIG Typography — Dynamic Type guidance: "aim to display as much useful text at the largest accessibility font size as you do at the largest standard font size," avoid truncation, reduce multi-column layouts at large sizes, keep primary elements near the top. The "iOS, iPadOS larger accessibility type sizes" table (the AX-range table) confirms Body scales from 17pt default up to 29pt at the largest accessibility category, Title 1 up to 76pt, etc.
  https://developer.apple.com/design/human-interface-guidelines/typography
- HIG Layout — control-size specification table (fetched live):

  | Platform | Default control size | Minimum control size |
  |---|---|---|
  | iOS, iPadOS | 44×44 pt | 28×28 pt |

  and, from the Accessibility page's Mobility section: "Strive to meet the recommended minimum control size for each platform... it works well to add about 12 points of padding around elements that include a bezel [and] about 24 points of padding... for elements without a bezel."
  https://developer.apple.com/design/human-interface-guidelines/layout

### Caveats

- The Accessibility HIG page's own change log shows its last content revision was June 9, 2025 (before the iOS 26 GM); the Materials/Layout Liquid-Glass-specific content is dated to the iOS 26 cycle, but I found no evidence of a *tap-target-size* change specifically tied to Liquid Glass — treat "no change" as verified against current live docs, not as a promise nothing shifted in a later iOS 26 point release.
- `.buttonStyle(.glass)` as a named SwiftUI `ButtonStyle` was reported in multiple third-party WWDC25 write-ups but I did not independently fetch its live doc JSON in this pass (time-boxed); before pinning it in ARCHITECTURE.md, confirm `developer.apple.com/documentation/swiftui/buttonstyle/glass` directly.

---

## Q4 — Surviving suspension/termination and retrying a queued webhook POST

**Actionable answer:**

- **When the app is woken by a location event (foreground-launched-in-background via SLC/visits/`CLMonitor`):** do the POST directly with a normal (non-background) `URLSession` data task from inside the actor-isolated coordinator's handler, with your own retry/backoff loop gated by `NWPathMonitor`. The app is already running at that point (the system launched or resumed it specifically to deliver the event) — you have a background execution window (a few tens of seconds) to attempt the send and, if it succeeds or fails permanently, persist the outcome to the durable queue file before the window closes. This satisfies REQ-05/REQ-08 without needing a background `URLSession` at all for the common case.
- **When the app is not running and no location event is pending** (e.g., the phone regains signal in a pocket with nothing forcing a wake) — nothing wakes the app to retry. The durable queue on disk simply waits; the next event that *does* wake the app (a manual open, a new SLC/visit/region event, or a periodic `BGAppRefreshTask` if you choose to schedule one) is what flushes it. This is the honest architectural limit: iOS provides no "wake me when connectivity returns" primitive by itself.
- **Background `URLSessionConfiguration.background(withIdentifier:)`** is the mechanism to reach for only if a *send already in flight* needs to survive the app being suspended/terminated mid-transfer — it hands the actual HTTP transfer to `nsurlsessiond`, a separate system process, so the upload continues even if the app is killed by the system afterward. **Caveat that matters directly for REQ-05's "queue survives force-quit" acceptance criterion:** Apple's own doc is explicit that this protection does **not** cover a user swiping the app away in the app switcher — "If the user terminates the app from the multitasking screen, the system cancels all of the session's background transfers... the system does not automatically relaunch apps that were force quit by the user." So a background URLSession, by itself, does not make "queued ping survives force-quit" true; what makes it true is that **the queue itself is a file on disk** (this project's `Codable` array in Application Support) — force-quit never deletes that file, and the *next* time the app runs (manually, or via a location wake) it re-reads the queue and retries. Background URLSession is an optimization for in-flight transfers, not the durability mechanism.
- **`BGTaskScheduler` (`BGAppRefreshTask`/`BGProcessingTask`)** is the right tool for opportunistic, periodic "flush the queue" attempts *while the app is not otherwise being woken by location events* — e.g., schedule a `BGAppRefreshTask` each time the app goes to background to get an occasional extra chance to drain the queue. It is not a substitute for a location-triggered wake (the system decides if/when to run it, with no guarantee, and typically not more than a few times a day for a low-usage app) and should be treated as a supplementary retry path, not the primary one.
- **`NWPathMonitor`** only runs while your process is alive; it's the right tool to gate retry attempts (don't hammer the network while offline) during any of the above windows, but it cannot itself wake a suspended/terminated app — it's a foreground/background-window connectivity signal, not a wake mechanism.
- **Recommended architecture for this app:** durable queue file (already decided) → on every wake (manual launch, SLC/visit/CLMonitor event, or app-refresh task) attempt to drain the queue with a plain foreground `URLSession` data task, guarded by `NWPathMonitor.currentPath.status == .satisfied` and your existing backoff/failure-classification rules → optionally register a `BGAppRefreshTask` as a secondary drain trigger for the "phone regains signal while the app is merely backgrounded, not launched by anything" gap. Background `URLSessionConfiguration.background` is worth adding only if a single ping's *upload itself* is large/slow enough that you specifically need it to survive a mid-transfer suspend — for a small JSON POST this is unlikely to matter and adds delegate-callback complexity (`application(_:handleEventsForBackgroundURLSession:completionHandler:)`) for little benefit.

### Evidence

- `URLSessionConfiguration.background(withIdentifier:)` — live doc, not deprecated (iOS 8.0+): "A session configured with this object hands control of the transfers over to the system, which handles the transfers in a separate process. In iOS, this configuration makes it possible for transfers to continue even when the app itself is suspended or terminated... If the user terminates the app from the multitasking screen, the system cancels all of the session's background transfers. In addition, the system does not automatically relaunch apps that were force quit by the user."
  https://developer.apple.com/documentation/foundation/urlsessionconfiguration/background(withidentifier:)
- `BGTaskScheduler`, `BGAppRefreshTask`, `BGProcessingTask` — all live, not deprecated (introduced iOS 13.0): "Background tasks give your app a way to run code even when the app is suspended." `BGAppRefreshTask`: "a short task typically used to refresh content that's run while the app is in the background." `BGProcessingTask`: "a time-consuming processing task that runs while the app is in the background" (deferrable, for larger maintenance work, not for time-sensitive pings).
  https://developer.apple.com/documentation/backgroundtasks/bgtaskscheduler
  https://developer.apple.com/documentation/backgroundtasks/bgapprefreshtask
  https://developer.apple.com/documentation/backgroundtasks/bgprocessingtask
- New in iOS 26: `BGContinuedProcessingTask` — lets a **foreground, user-initiated** task (explicit tap, e.g. "Export video") keep running briefly after the app backgrounds, with a system-owned progress UI. Not applicable to this project's use case (no user-initiated long transfer; pings are small and either succeed immediately or get queued) but worth knowing it exists as the new iOS 26 background-tasks primitive. It's explicitly exempt from the "must register before `applicationDidFinishLaunching` returns" rule that the other `BGTaskScheduler` task types require.
  https://developer.apple.com/documentation/backgroundtasks/bgcontinuedprocessingtask
  WWDC25 "Finish tasks in the background": https://developer.apple.com/videos/play/wwdc2025/227/
- Region/SLC/visits wake behavior (repeated from Q1/Q2) is what actually gives this app its background execution windows — see the capability table in Q2 and the region-monitoring article in Q1.

### Caveats

- Apple does not document a specific "background task budget" number for iOS 26 (this has never been publicly quantified for `BGTaskScheduler`; it's a black-box scheduler based on usage patterns, battery, and Low Power Mode). Third-party sources described `BGTaskScheduler` as "successfully running periodically" on iOS 26 betas but gave no hard iOS-26-specific quota change; treat "no published budget change" as the finding, not "confirmed unchanged internals."
- The location-event wake execution window's exact duration (how many seconds you have to complete the POST before the system re-suspends you) is not published as a fixed number by Apple for any iOS version, iOS 26 included — design the retry/backoff logic to complete fast (seconds, not tens-of-seconds of guaranteed budget) and rely on the durable queue + next-wake retry rather than assuming a generous window.

---

## Unverified

These claims could not be confirmed against an official Apple source in this research pass. Do not pin them into ARCHITECTURE.md without further verification:

1. **A dedicated WWDC25/iOS 26 "What's New in Core Location" session.** No such session was found in Apple's WWDC25 video index; CoreLocation-adjacent iOS 26 news found was limited to MapKit's new geocoding classes (`MKGeocodingRequest` etc., replacing `CLGeocoder`/`CLPlacemark` — not used by this app's plan, which already specifies `CLGeocoder` for reverse geocoding per REQUIREMENTS.md; worth a follow-up check on whether `CLGeocoder` is itself now deprecated, since it wasn't checked in this pass).
2. **Forum claim that iOS 26 specifically weakened force-quit relaunch reliability for significant-location-change/region-monitoring events**, versus a suspended (not force-quit) app which reportedly still relaunches reliably. This is plausible given the long-standing force-quit-cancels-background-work pattern (confirmed for background URLSession, Q4), but I found no official Apple documentation stating this as an iOS-26-specific regression or intentional change — only a developer-forum thread.
3. **Background App Refresh's effect on location-triggered wakes.** Widely repeated across the developer community (disabling Background App Refresh, globally or per-app, is said to block all location-driven background relaunches even with Always granted) but not stated in the specific CoreLocation doc pages fetched for this research. Worth confirming directly against `developer.apple.com/documentation/uikit/uiapplication/backgroundrefreshstatus` or an authorization/background-modes overview page before relying on it in the plan.
4. **`.buttonStyle(.glass)`** — referenced by multiple secondary sources as the SwiftUI button style that opts a custom button into Liquid Glass, but its live doc JSON was not independently fetched in this pass; confirm signature and iOS-26 introduction directly before use.
5. **Exact background-execution-window duration after a CoreLocation-triggered wake** (Q4) — not published by Apple as a fixed number for any iOS version; the "design for a short window, rely on durable queue for the rest" recommendation is an inference from the absence of a published guarantee, not a cited number.
