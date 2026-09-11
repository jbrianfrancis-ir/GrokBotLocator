---
phase: 04-automatic-triggers
status: gaps
smoke: pass
gaps:
  - "REQ-08 circular arming: on a COLD RELAUNCH with only the geofence trigger enabled, the region can never arm. `reference` is in-memory and nil in a fresh process; `applySettings` registers only `if currentCentre() == nil, let reference` (TriggerCoordinator.swift:121-122); and the ONLY reference-recovery from `geofence.currentCentre()` sits inside `runSignificantChange` (:191), which is disabled in that configuration. So with no persisted region there is nothing to register and nothing that will ever set a reference — the trigger is dead until the user taps I'm here or enables another trigger. Per-trigger toggles are a shipped REQ-09 feature, so geofence-only is a supported configuration. Found by machine-driven simulator run, not by review."
unverified:
  - "04-05: `QueueDrainCoordinator.hydrate()` copies queue entries into `PingHistoryLog` vs ARCHITECTURE.md:72 'never copied anywhere else' — still present (QueueDrainCoordinator.swift:86-110), deliberately not ruled on."
  - "04-10: `UnqueuedPingSink` (PingSender.swift:67) echoes the classifier's retryable sentence, which `PingSender` then downgrades to `.permanentFailure` — a 429 in the no-queue build still renders as 'Failed: it is waiting and will be sent again.' Conflicts with D-14; untouched on purpose."
  - "04-04: `MKReverseGeocodingRequest` rate-limit/offline semantics. NEW empirical evidence: with no geocoding service reachable, `cancel()` did NOT resume `await request.mapItems` (leaked continuation, indefinite hang) — found by a real hang, fixed at aa039c5 by bounding `label(for:)` by construction. Pins one failure mode, not the throttling contract."
---

## Smoke
`./scripts/smoke.sh` → exit 0, `** TEST SUCCEEDED **`, **259 tests in 28 suites** (re-run after 04-14; 257 before), 12 `==>` steps incl. 8 guards (type-scale, location, MapKit, UserDefaults, queue-store, queue-protection, background-identifier, background-modes). Wire-format order asserted by `PingPayloadTests`. Matches the declared pass condition.

## Truths
| must_have truth | result | evidence |
|---|---|---|
| REQ-05: every location callback drains FIRST and unconditionally | VERIFIED | `await drain()` is line 1 of `runSignificantChange`/`runVisit`/`runGeofenceExit` (TriggerCoordinator.swift:169,190,208), above every `guard`. `everyCallbackDrainsEvenWhenItDoesNotPing` runs with **all three triggers OFF** — a drain below the enable guard would assert 0; it asserts 3. `aThreeHundredMetreWakeDrainsButDoesNotPing` asserts 2 drains while the gate refuses the second, so ordering holds above the gate too. Proof is ordering, not count. |
| REQ-05: drain closure actually wired | VERIFIED | GrokBotLocatorApp.swift:122-124 `drain = { await queueCoordinator?.drainForeground() }` → `TriggerCoordinator(drain:)`. |
| REQ-06: 500 m computed in app code, not trusted from the OS | VERIFIED | `DisplacementGate.shouldPing` is pure over two coordinates, `>= 500` via `CLLocation.distance` (TriggerCoordinator.swift:181 calls it after the callback). `aThreeHundredMetreMoveDoesNotPing`, `aMoveOfExactlyFiveHundredMetresPings`, `theThresholdIsFiveHundredMetres` (`static let`, no setter). 300 m → no ping proven at gate and coordinator. |
| REQ-07: arrival only | VERIFIED | `isArrival == (departureDate == .distantFuture)`; `anArrivalPingsOnceAndADepartureDoesNot`, `TriggerEventsTests`. Fix stamped with `arrivalDate`, not now. |
| REQ-08: one region, exit-only, re-registered at the new ping | VERIFIED | Fixed `conditionIdentifier` so `add` replaces (GeofenceMonitor.swift:70-76); `anExitFiresTheCallbackExactlyOnce`, `concurrentRegistrationsDoNotLeaveTwoRegions`, `aGeofenceExitPingsAndReRegistersAtTheNewPosition`. |
| REQ-09: 15 s floor unreachable on read and write, defined once | VERIFIED (re-checked after 04-14) | `PingRateLimiter.hardFloor` is the only definition; `TriggerSettings.clamped` and the Stepper's `in: PingRateLimiter.hardFloor...300` both reference it, no restated literal. `theIntervalCannotBeSetBelowFifteenSeconds`, `anIntervalHandEditedBelowTheFloorIsClampedOnRead`, `aNonFiniteIntervalIsClamped`. 04-14 added no `15`/`60` literal: the only bare match in the four settings/wiring files is phase 03's unrelated `15 * 60` BGAppRefresh delay, and the seed at :93 reads the stored value rather than restating a default. |
| REQ-09: a configured interval is honoured by the gate | VERIFIED (closed by 04-14) | `await rateLimiter.setMinimumInterval(s.minimumIntervalSeconds)` is the FIRST statement of `applySettings` (TriggerCoordinator.swift:99), above the Always request, so both entries carry it: `start()` (disk) and `update(_:)` (Settings). `rateLimiter: any PingRateLimiting` on `TriggerCoordinator.init` has no default (:47). Proven with the REAL limiter, not a fake: `anIntervalOnDiskReachesTheGateAtStart` (TriggerCoordinatorTests.swift:413) and `anIntervalChangedInSettingsReachesTheGate` (SettingsModelTests.swift:693) each claim at t, then at 1.5x the default — allowed under the old wiring, `.tooSoon` now. |
| REQ-09: a relaunch honours the interval on disk from the FIRST claim | VERIFIED (test + trace) | Two independent layers. The composition root seeds the single limiter at construction — `PingRateLimiter(minimumInterval: triggerStore.load().minimumIntervalSeconds)` (GrokBotLocatorApp.swift:93) — so the disk value is in force before `start()` even runs; that layer is **code trace only**, no test constructs the app. `start()` re-applies it, and that layer IS tested with no Settings visit (`anIntervalOnDiskReachesTheGateAtStart`). |
| REQ-10: Always only at point of use | VERIFIED (code trace) | `applySettings` requests only when `s.anyTriggerEnabled` and not already Always (TriggerCoordinator.swift:88-91); `disabledTriggersAreNotArmedAndEnablingArmsOnlyThatOne` asserts 0 requests with all off, 1 after enabling one. Refused-Always sentence: `TriggerAuthorizationNotice`. Live prompt sequence → human. |
| SC-04: manual + automatic counted together | VERIFIED (re-checked after 04-14) | Still exactly ONE construction in app code — `grep -rn "PingRateLimiter(" src/` gives GrokBotLocatorApp.swift:93 plus a `#Preview` (PingHomeView.swift:293) — now reaching THREE consumers: `PingModel` (:97), `AutomaticPinger` (:123), `TriggerCoordinator` (:138). The third takes it to configure, not to claim; the two claim sites are unchanged. `manualAndAutomaticShareOneWindow`, `fiftyConcurrentClaimsAtTheSameInstantAllowExactlyOne`, `twoTriggersTwentySecondsApartProduceOnePing`. |
| D-15: MapKit confined to one file, reverse geocoding only | VERIFIED | `grep -rn "import MapKit" src/` → one hit; `grep -rnE '\bMK[A-Z]' src/` outside that file → none. smoke.sh:109-135 enforces both import and type, anchored on `^path:`. |
| Empty label never delays or drops a ping | VERIFIED | `label(for:)` is non-throwing, bounded by construction (unstructured fetch + `Mutex` one-shot, never awaited); `aLabelAttemptRespectsItsBudget` measures real elapsed < 2 s at a 50 ms budget against unreachable MapKit. `AutomaticPinger` sends regardless of label value — no branch on empty. |
| 04-01: BUILT plist carries `location`+`fetch` and the Always purpose string | VERIFIED | `PlistBuddy` on `build/dd-smoke/.../GrokBotLocator.app/Info.plist` returned both modes and `NSLocationAlwaysAndWhenInUseUsageDescription`; smoke's background-modes guard reads the same built file. |
| 04-05: a wake drains silently, a foreground drain still announces | VERIFIED | presence is explicit state set from `scenePhase` (GrokBotLocatorApp.swift:145-160), default `false`; `QueueDrainCoordinatorTests` covers both directions. |
| 04-13: no-queue fallback still arms and pings | VERIFIED (code trace only, no test — unchanged by 04-14) | `triggerCoordinator` built unconditionally; `queueCoordinator` nil → drain closure is `await nil?.drainForeground()`, a no-op. No test exercises the `queue == nil` composition. |
| 04-11: only a real ping advances the reference | VERIFIED (coincidental-reliance — unchanged by 04-14) | `aRateLimitedPingDoesNotAdvanceTheReference`, `twoSimultaneousWakesProduceOnePingAndOneReference`. Holds only because `.pinged` is returned for `.failed` and `.queued` too, and the `.noCredentialsOrFix` arm is decided by **exact string equality** against a sentence duplicated in PingSender.swift:167,180 (AutomaticPinger.swift:91) — `grep -rn noCredentialsOrFix tests/` still returns 0, and a reworded sentence silently turns a credential-less attempt into a reference advance. 04-14 did not touch `AutomaticPinger.swift`. |
| 04-12: new Settings controls meet DESIGN.md at AX5 | HUMAN | `DSMetrics.minTapTarget` + `dsFont`/`DSPalette` tokens on every new control, no line limits — reflow itself needs a device. |
| 04-04 / 04-05 / 04-10 backstop truths | HUMAN (non-inferable) | see `unverified` — spec doesn't settle these; nothing pins them down. |

## Human checks
- [x] **REQ-06 — PASS (2026-09-11, simulator, machine-driven, both halves).** Driven with
  `xcrun simctl location start --speed=20 --distance=50` (real interpolated movement, NOT a
  teleport). Origin 40.05590,17.99250 → 520 m north: exactly ONE new row appeared, at
  **40.06041** = **500.8 m** displacement, i.e. the first update at/past the 500 m threshold.
  Then 300 m north of that NEW reference, after waiting out the 15 s rate limit so the limiter
  could not be the cause: **no new row**. Screenshots sim-02/sim-03. The automatic row's label
  read "Gallipoli" while the manual label field read "test", so D-15's MapKit reverse geocoding
  also worked on a real send path. Rows read Queued (webhook unreachable on that simulator),
  which does not affect what this proves: the trigger fired, and the gate refused the 300 m move.
  **Correction to an earlier claim in this file's own guidance: significant-change DOES work in
  the simulator.** A teleport (Features ▸ Location ▸ Custom) produces nothing; `location start`
  with interpolated waypoints works. Fixtures in `scripts/gpx/`.
- [ ] REQ-07 on device — simulated visit arrival, backgrounded → exactly one ping shown as Arrival.
- [ ] **REQ-08 — NOT REPRODUCED (2026-09-11, simulator).** With significant-change and visits
  disabled so any ping had to be a geofence exit, a 300 m move past the 150 m radius produced
  no row. Two candidate causes, NOT yet distinguished: (a) `CLMonitor` events may not be
  delivered in the simulator; (b) the region may not have persisted across the relaunch, which
  RESEARCH already lists as UNVERIFIED. Still needs a device. See the new gap below — found
  while investigating this, and true independently of which cause holds.
- [ ] REQ-05 fourth drain end to end — airplane mode on, tap "I'm here" to queue, background, airplane off, drive a location wake → queued ping goes out with NO announcement; history reads Sent on reopen.
- [x] **REQ-10 live prompt — PASS (2026-09-11, simulator, human-attested).** With all three
  triggers off nothing is requested; enabling one raises the Always prompt; choosing "While
  Using" shows the distinct sentence and "I'm here" still sends. Attested by Brian Francis as
  part of batch 1; not machine-evidenced. **Caveat:** if `xcrun simctl privacy booted reset
  location` was not run beforehand, the "nothing is requested with all toggles off" half was
  not genuinely exercised — a previously-answered prompt does not re-raise.
- [x] **REQ-12/AX5 — PASS (2026-09-11, simulator, human-attested).** The new "Automatic pings"
  section (three toggles, interval Stepper, notice) at AX5 in light and dark: no truncation,
  clipping or overlap; targets tappable. Attested by Brian Francis as part of batch 1; not
  machine-evidenced, and the Accessibility Inspector audit result was not reported separately.
  The accepted `actionLabel` > `screenTitle` inversion at AX5 (15:30 decision) remains accepted.
- [ ] SC-03 — a full sightseeing day with all three triggers on, Settings ▸ Battery share under 5%. Watch significant-change first.
- [ ] Backstop: `hydrate()` copying queue entries into `PingHistoryLog` — narrow ARCHITECTURE.md:72's "never copied anywhere else", or drop the copy and accept losing queued rows on relaunch. State the rule, then pin it with a test.
- [ ] Backstop: `UnqueuedPingSink`'s 429 sentence vs D-14 — write honest no-queue copy, or ratify the current downgrade. Then pin it.
- [ ] Backstop: `MKReverseGeocodingRequest` throttling/offline contract — state what the app may assume, or accept "any failure ⇒ empty label, bounded by construction" as the standing rule.

## Learnings
- A bound that depends on a vendor API honouring `cancel()` is not a bound: `MKReverseGeocodingRequest.mapItems` did not resume on `cancel()` with no service reachable and hung indefinitely. The pattern that works is an unstructured, never-awaited fetch plus a `Mutex`-guarded one-shot continuation — bounded by construction. Any future "race X against a timeout" should copy this shape, not `withTaskGroup`.
- Persisting a setting, displaying it, and enforcing it are three separate wirings. Phase 04 shipped the first two for the minimum interval and missed the third (closed by 04-14) because no plan owned the seam between `TriggerSettings` (the stored value) and `PingRateLimiter` (the enforcer). When a value is stored in one type and enforced in another, a plan must name the call that carries it across — and the test for it must use the REAL enforcer: every fake `PingRateLimiting` in this suite returns `.allowed` unconditionally, so a fake-based test would have passed against the broken wiring.
- Serialized execution kept commit attribution clean: every phase-04 commit touches only its own plan's files (the 04-09/04-10 spillover is protocol-widening fan-out, declared in both SUMMARYs), and no trailer crosses plans. 04-11's five commits carry no `Co-Authored-By` trailer at all — a convention miss, not crossed attribution.
