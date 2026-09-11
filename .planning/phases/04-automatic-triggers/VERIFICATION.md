---
phase: 04-automatic-triggers
status: gaps
smoke: pass
gaps:
  - "REQ-09: a minimum interval changed in Settings is persisted and displayed but never reaches the gate. `PingRateLimiter.setMinimumInterval` has zero callers in src/ outside its own declaration (`grep -rn setMinimumInterval src/`); the limiter at GrokBotLocatorApp.swift:87 keeps the 60 s default for the process lifetime while SettingsView.swift:213 renders the stored value. Contradicts 04-12's truth 'the user is never shown a value the app will not honour'. The 60 s default and the 15 s floor are unaffected."
unverified:
  - "04-05: `QueueDrainCoordinator.hydrate()` copies queue entries into `PingHistoryLog` vs ARCHITECTURE.md:72 'never copied anywhere else' — still present (QueueDrainCoordinator.swift:86-110), deliberately not ruled on."
  - "04-10: `UnqueuedPingSink` (PingSender.swift:67) echoes the classifier's retryable sentence, which `PingSender` then downgrades to `.permanentFailure` — a 429 in the no-queue build still renders as 'Failed: it is waiting and will be sent again.' Conflicts with D-14; untouched on purpose."
  - "04-04: `MKReverseGeocodingRequest` rate-limit/offline semantics. NEW empirical evidence: with no geocoding service reachable, `cancel()` did NOT resume `await request.mapItems` (leaked continuation, indefinite hang) — found by a real hang, fixed at aa039c5 by bounding `label(for:)` by construction. Pins one failure mode, not the throttling contract."
---

## Smoke
`./scripts/smoke.sh` → exit 0, `** TEST SUCCEEDED **`, 257 tests in 28 suites, 12 `==>` steps incl. 8 guards (type-scale, location, MapKit, UserDefaults, queue-store, queue-protection, background-identifier, background-modes). Wire-format order asserted by `PingPayloadTests`. Matches the declared pass condition.

## Truths
| must_have truth | result | evidence |
|---|---|---|
| REQ-05: every location callback drains FIRST and unconditionally | VERIFIED | `await drain()` is line 1 of `runSignificantChange`/`runVisit`/`runGeofenceExit` (TriggerCoordinator.swift:169,190,208), above every `guard`. `everyCallbackDrainsEvenWhenItDoesNotPing` runs with **all three triggers OFF** — a drain below the enable guard would assert 0; it asserts 3. `aThreeHundredMetreWakeDrainsButDoesNotPing` asserts 2 drains while the gate refuses the second, so ordering holds above the gate too. Proof is ordering, not count. |
| REQ-05: drain closure actually wired | VERIFIED | GrokBotLocatorApp.swift:122-124 `drain = { await queueCoordinator?.drainForeground() }` → `TriggerCoordinator(drain:)`. |
| REQ-06: 500 m computed in app code, not trusted from the OS | VERIFIED | `DisplacementGate.shouldPing` is pure over two coordinates, `>= 500` via `CLLocation.distance` (TriggerCoordinator.swift:181 calls it after the callback). `aThreeHundredMetreMoveDoesNotPing`, `aMoveOfExactlyFiveHundredMetresPings`, `theThresholdIsFiveHundredMetres` (`static let`, no setter). 300 m → no ping proven at gate and coordinator. |
| REQ-07: arrival only | VERIFIED | `isArrival == (departureDate == .distantFuture)`; `anArrivalPingsOnceAndADepartureDoesNot`, `TriggerEventsTests`. Fix stamped with `arrivalDate`, not now. |
| REQ-08: one region, exit-only, re-registered at the new ping | VERIFIED | Fixed `conditionIdentifier` so `add` replaces (GeofenceMonitor.swift:70-76); `anExitFiresTheCallbackExactlyOnce`, `concurrentRegistrationsDoNotLeaveTwoRegions`, `aGeofenceExitPingsAndReRegistersAtTheNewPosition`. |
| REQ-09: 15 s floor unreachable on read and write, defined once | VERIFIED | `PingRateLimiter.hardFloor` is the only definition; `TriggerSettings.clamped` and the Stepper's `in: PingRateLimiter.hardFloor...300` both reference it, no restated literal. `theIntervalCannotBeSetBelowFifteenSeconds`, `anIntervalHandEditedBelowTheFloorIsClampedOnRead`, `aNonFiniteIntervalIsClamped`. |
| REQ-09: a configured interval is honoured by the gate | **GAP** | see `gaps` above. |
| REQ-10: Always only at point of use | VERIFIED (code trace) | `applySettings` requests only when `s.anyTriggerEnabled` and not already Always (TriggerCoordinator.swift:88-91); `disabledTriggersAreNotArmedAndEnablingArmsOnlyThatOne` asserts 0 requests with all off, 1 after enabling one. Refused-Always sentence: `TriggerAuthorizationNotice`. Live prompt sequence → human. |
| SC-04: manual + automatic counted together | VERIFIED | ONE `let rateLimiter = PingRateLimiter()` (GrokBotLocatorApp.swift:87) reaches `PingModel` (:91) and `AutomaticPinger` (:117). `manualAndAutomaticShareOneWindow`, `fiftyConcurrentClaimsAtTheSameInstantAllowExactlyOne`, `twoTriggersTwentySecondsApartProduceOnePing`. |
| D-15: MapKit confined to one file, reverse geocoding only | VERIFIED | `grep -rn "import MapKit" src/` → one hit; `grep -rnE '\bMK[A-Z]' src/` outside that file → none. smoke.sh:109-135 enforces both import and type, anchored on `^path:`. |
| Empty label never delays or drops a ping | VERIFIED | `label(for:)` is non-throwing, bounded by construction (unstructured fetch + `Mutex` one-shot, never awaited); `aLabelAttemptRespectsItsBudget` measures real elapsed < 2 s at a 50 ms budget against unreachable MapKit. `AutomaticPinger` sends regardless of label value — no branch on empty. |
| 04-01: BUILT plist carries `location`+`fetch` and the Always purpose string | VERIFIED | `PlistBuddy` on `build/dd-smoke/.../GrokBotLocator.app/Info.plist` returned both modes and `NSLocationAlwaysAndWhenInUseUsageDescription`; smoke's background-modes guard reads the same built file. |
| 04-05: a wake drains silently, a foreground drain still announces | VERIFIED | presence is explicit state set from `scenePhase` (GrokBotLocatorApp.swift:145-160), default `false`; `QueueDrainCoordinatorTests` covers both directions. |
| 04-13: no-queue fallback still arms and pings | VERIFIED (code trace only, no test) | `triggerCoordinator` built unconditionally; `queueCoordinator` nil → drain closure is `await nil?.drainForeground()`, a no-op. No test exercises the `queue == nil` composition. |
| 04-11: only a real ping advances the reference | VERIFIED (coincidental-reliance) | `aRateLimitedPingDoesNotAdvanceTheReference`, `twoSimultaneousWakesProduceOnePingAndOneReference`. Holds only because `.pinged` is returned for `.failed` and `.queued` too, and the `.noCredentialsOrFix` arm is decided by **exact string equality** against a sentence duplicated in PingSender.swift:167,180 (AutomaticPinger.swift:91) — untested, and a reworded sentence silently turns a credential-less attempt into a reference advance. |
| 04-12: new Settings controls meet DESIGN.md at AX5 | HUMAN | `DSMetrics.minTapTarget` + `dsFont`/`DSPalette` tokens on every new control, no line limits — reflow itself needs a device. |
| 04-04 / 04-05 / 04-10 backstop truths | HUMAN (non-inferable) | see `unverified` — spec doesn't settle these; nothing pins them down. |

## Human checks
- [ ] REQ-06 on device/sim — GPX route crossing 500 m, app backgrounded → one ping; a 300 m route → none.
- [ ] REQ-07 on device — simulated visit arrival, backgrounded → exactly one ping shown as Arrival.
- [ ] REQ-08 on device — after one manual ping, move >150 m → one exit ping; move >150 m again → a second (proves re-registration).
- [ ] REQ-05 fourth drain end to end — airplane mode on, tap "I'm here" to queue, background, airplane off, drive a location wake → queued ping goes out with NO announcement; history reads Sent on reopen.
- [ ] REQ-10 live prompt — with all three off nothing is requested; enabling one raises the Always prompt; choosing "While Using" shows the distinct sentence and "I'm here" still sends.
- [ ] REQ-12/AX5 — the new "Automatic pings" section (three toggles, interval Stepper, notice) at AX5 in light and dark: no truncation, clipping or overlap, all targets still tappable; Accessibility Inspector reports no contrast or hit-target failure.
- [ ] SC-03 — a full sightseeing day with all three triggers on, Settings ▸ Battery share under 5%. Watch significant-change first.
- [ ] Backstop: `hydrate()` copying queue entries into `PingHistoryLog` — narrow ARCHITECTURE.md:72's "never copied anywhere else", or drop the copy and accept losing queued rows on relaunch. State the rule, then pin it with a test.
- [ ] Backstop: `UnqueuedPingSink`'s 429 sentence vs D-14 — write honest no-queue copy, or ratify the current downgrade. Then pin it.
- [ ] Backstop: `MKReverseGeocodingRequest` throttling/offline contract — state what the app may assume, or accept "any failure ⇒ empty label, bounded by construction" as the standing rule.

## Learnings
- A bound that depends on a vendor API honouring `cancel()` is not a bound: `MKReverseGeocodingRequest.mapItems` did not resume on `cancel()` with no service reachable and hung indefinitely. The pattern that works is an unstructured, never-awaited fetch plus a `Mutex`-guarded one-shot continuation — bounded by construction. Any future "race X against a timeout" should copy this shape, not `withTaskGroup`.
- Persisting a setting, displaying it, and enforcing it are three separate wirings. Phase 04 did the first two for the minimum interval and missed the third because no plan owned the seam between `TriggerSettings` (the stored value) and `PingRateLimiter` (the enforcer). When a value is stored in one type and enforced in another, a plan must name the call that carries it across.
- Serialized execution kept commit attribution clean: every phase-04 commit touches only its own plan's files (the 04-09/04-10 spillover is protocol-widening fan-out, declared in both SUMMARYs), and no trailer crosses plans. 04-11's five commits carry no `Co-Authored-By` trailer at all — a convention miss, not crossed attribution.
