---
phase: 04-automatic-triggers
status: human_needed
smoke: pass
gaps:
  - "REQ-08 does not fire at RUNTIME, after 04-15. Reproduced twice on the iOS 26 simulator with the signed build: geofence as the ONLY enabled trigger, a cold relaunch (`simctl terminate` then `launch`), `LastPing.json` holding a valid reference (37.33888380,-122.03254703), then 200 m of real interpolated movement (`simctl location start --speed=15 --distance=25`) past the 150 m radius -> NO ping, history empty (\"No pings yet\"), and the store unchanged. 04-15's unit tests pass, including `aColdStartWithNoRegionRecoversFromTheLastPingFileAndArms` which asserts the region IS registered from the file, so the break is between that unit-level state and a delivered CLMonitor event. NOT a platform limitation: the Task 1 probe measured CLMonitor persisting across a process kill AND delivering an event after the same kind of movement. A companion observation, same session: with significant-change also enabled, a ping fired at ~400 m displacement -- under the 500 m gate -- which is best explained by a nil reference producing a bootstrap ping rather than by a geofence exit, i.e. the runtime reference recovery may also not be taking effect. Cause unknown; needs /flow-debug, not another replan."
unverified:
  - "04-05: `QueueDrainCoordinator.hydrate()` copies queue entries into `PingHistoryLog` vs ARCHITECTURE.md:72 'never copied anywhere else' — still present (QueueDrainCoordinator.swift:86-110), deliberately not ruled on."
  - "04-10: `UnqueuedPingSink` (PingSender.swift:67) echoes the classifier's retryable sentence, which `PingSender` then downgrades to `.permanentFailure` — a 429 in the no-queue build still renders as 'Failed: it is waiting and will be sent again.' Conflicts with D-14; untouched on purpose."
  - "04-04: `MKReverseGeocodingRequest` rate-limit/offline semantics. NEW empirical evidence: with no geocoding service reachable, `cancel()` did NOT resume `await request.mapItems` (leaked continuation, indefinite hang) — found by a real hang, fixed at aa039c5 by bounding `label(for:)` by construction. Pins one failure mode, not the throttling contract."
---

## Smoke
`./scripts/smoke.sh` → exit 0, `** TEST SUCCEEDED **`, **267 tests in 29 suites** (re-run after 04-15; 259 after 04-14, 257 before), 13 `==>` steps incl. **9 guards** — the eight before plus the new `last-ping-protection` guard, and the queue-store guard now reads "FileManager/file-writing APIs confined to PingQueueStore.swift **and LastPingStore.swift**", which is what keeps D-16's store from becoming a third file writer. Wire-format order asserted by `PingPayloadTests`. Matches the declared pass condition.

## Truths
| must_have truth | result | evidence |
|---|---|---|
| REQ-05: every location callback drains FIRST and unconditionally | VERIFIED (re-checked after 04-15) | `await drain()` is line 1 of `runSignificantChange`/`runVisit`/`runGeofenceExit` (TriggerCoordinator.swift:169,190,208), above every `guard`. `everyCallbackDrainsEvenWhenItDoesNotPing` runs with **all three triggers OFF** — a drain below the enable guard would assert 0; it asserts 3. `aThreeHundredMetreWakeDrainsButDoesNotPing` asserts 2 drains while the gate refuses the second, so ordering holds above the gate too. Proof is ordering, not count. 04-15 inserted `recoverReferenceIfNeeded()` into `runSignificantChange` BELOW `await drain()`, so the ordering is unchanged; the test still passes by name. |
| REQ-05: drain closure actually wired | VERIFIED | GrokBotLocatorApp.swift:122-124 `drain = { await queueCoordinator?.drainForeground() }` → `TriggerCoordinator(drain:)`. |
| REQ-06: 500 m computed in app code, not trusted from the OS | VERIFIED | `DisplacementGate.shouldPing` is pure over two coordinates, `>= 500` via `CLLocation.distance` (TriggerCoordinator.swift:181 calls it after the callback). `aThreeHundredMetreMoveDoesNotPing`, `aMoveOfExactlyFiveHundredMetresPings`, `theThresholdIsFiveHundredMetres` (`static let`, no setter). 300 m → no ping proven at gate and coordinator. |
| REQ-07: arrival only | VERIFIED | `isArrival == (departureDate == .distantFuture)`; `anArrivalPingsOnceAndADepartureDoesNot`, `TriggerEventsTests`. Fix stamped with `arrivalDate`, not now. |
| REQ-08: one region, exit-only, re-registered at the new ping | VERIFIED | Fixed `conditionIdentifier` so `add` replaces (GeofenceMonitor.swift:70-76); `anExitFiresTheCallbackExactlyOnce`, `concurrentRegistrationsDoNotLeaveTwoRegions`, `aGeofenceExitPingsAndReRegistersAtTheNewPosition`. |
| REQ-08: the region arms on a COLD RELAUNCH in a geofence-only configuration | VERIFIED (closed by 04-15) | `recoverReferenceIfNeeded()` now sits ABOVE the register condition inside `applySettings`'s geofence branch (TriggerCoordinator.swift:133), the path that runs in a geofence-only config, and is the ONE definition `runSignificantChange` (:238) also calls — no second copy to drift. **Both cold-start paths tested**: region survived → `aColdStartWithOnlyTheGeofenceEnabledRecoversTheReference` (recovers from `currentCentre()`, asserts `registrations.count == 1` so `start()` does not re-register over a live region); region gone, file seeded → `aColdStartWithNoRegionRecoversFromTheLastPingFileAndArms` (asserts the region is registered FROM the file). The `(await lastPing?.load() ?? nil) ?? centre` double unwrap is load-bearing: without `?? nil`, an existing-but-empty store yields `.some(nil)` and `centre` is never reached. |
| D-16: exactly ONE coordinate, overwritten in place, never appended | VERIFIED | `save` encodes a single private `StoredCoordinate` object and replaces the file (LastPingStore.swift:104-110). `savingTwiceOverwritesAndNeverAppends` reads the real file back and asserts `hasPrefix("{")` and `!contains("[")` — structural, not just a load-value check. |
| D-16: excluded from backups | VERIFIED | `isExcludedFromBackup` reasserted on every `save` (an atomic replace does not inherit resource values); `theLastPingFileIsExcludedFromBackup` reads it back off the real file. Also held by the new `last-ping-protection` smoke guard. |
| D-16: protection class `.completeUntilFirstUserAuthentication` | VERIFIED (qualified — NOT a runtime verification) | `FileLastPingStore.writeOptions` contains `.completeFileProtectionUntilFirstUserAuthentication` and is the same named seam `save` passes to `Data.write(to:options:)`. `theLastPingFileCarriesTheStatedProtectionClass` first writes a CONTROL file with no protection option; on the simulator the control ALSO reports `.protectionKey == nil`, so the runtime attribute is unobservable there and the test takes its fallback branch, asserting the constant. **What actually runs on the simulator proves the write options, not the class iOS applied.** On-device reading batched as a human check. |
| D-16: deleted when every trigger is disabled | VERIFIED | `if !s.anyTriggerEnabled { await lastPing?.clear(); reference = nil }` is the LAST statement of `applySettings` (TriggerCoordinator.swift:147-150), after every disable branch. `disablingEveryTriggerDeletesTheLastPingCoordinate` pings for real first (so the store genuinely holds a coordinate), then asserts both the store and the in-memory reference are nil. `clearRemovesTheFile` pins the store-level half. |
| D-16: the implementation does not EXCEED the authorization | VERIFIED | `grep -rn "lastPing" src/` — exactly one `save` (TriggerCoordinator.swift:289, inside `pingAndAdvance` under the same `.pinged` guard as `reference`), one `clear` (:149), one `load` (:173). No other writer, no second coordinate path: the widened queue-store guard confines file-writing APIs to `PingQueueStore.swift` and `LastPingStore.swift`, and the UserDefaults guard is unchanged. |
| REQ-09: 15 s floor unreachable on read and write, defined once | VERIFIED (re-checked after 04-14) | `PingRateLimiter.hardFloor` is the only definition; `TriggerSettings.clamped` and the Stepper's `in: PingRateLimiter.hardFloor...300` both reference it, no restated literal. `theIntervalCannotBeSetBelowFifteenSeconds`, `anIntervalHandEditedBelowTheFloorIsClampedOnRead`, `aNonFiniteIntervalIsClamped`. 04-14 added no `15`/`60` literal: the only bare match in the four settings/wiring files is phase 03's unrelated `15 * 60` BGAppRefresh delay, and the seed at :93 reads the stored value rather than restating a default. |
| REQ-09: a configured interval is honoured by the gate | VERIFIED (closed by 04-14) | `await rateLimiter.setMinimumInterval(s.minimumIntervalSeconds)` is the FIRST statement of `applySettings` (TriggerCoordinator.swift:99), above the Always request, so both entries carry it: `start()` (disk) and `update(_:)` (Settings). `rateLimiter: any PingRateLimiting` on `TriggerCoordinator.init` has no default (:47). Proven with the REAL limiter, not a fake: `anIntervalOnDiskReachesTheGateAtStart` (TriggerCoordinatorTests.swift:413) and `anIntervalChangedInSettingsReachesTheGate` (SettingsModelTests.swift:693) each claim at t, then at 1.5x the default — allowed under the old wiring, `.tooSoon` now. |
| REQ-09: a relaunch honours the interval on disk from the FIRST claim | VERIFIED (test + trace) | Two independent layers. The composition root seeds the single limiter at construction — `PingRateLimiter(minimumInterval: triggerStore.load().minimumIntervalSeconds)` (GrokBotLocatorApp.swift:93) — so the disk value is in force before `start()` even runs; that layer is **code trace only**, no test constructs the app. `start()` re-applies it, and that layer IS tested with no Settings visit (`anIntervalOnDiskReachesTheGateAtStart`). |
| REQ-10: Always only at point of use | VERIFIED (code trace) | `applySettings` requests only when `s.anyTriggerEnabled` and not already Always (TriggerCoordinator.swift:88-91); `disabledTriggersAreNotArmedAndEnablingArmsOnlyThatOne` asserts 0 requests with all off, 1 after enabling one. Refused-Always sentence: `TriggerAuthorizationNotice`. Live prompt sequence → human. |
| SC-04: manual + automatic counted together | VERIFIED (re-checked after 04-15) | Still exactly ONE construction in app code — `grep -rn "PingRateLimiter(" src/` gives GrokBotLocatorApp.swift:93 plus a `#Preview` (PingHomeView.swift:293) — now reaching THREE consumers: `PingModel` (:97), `AutomaticPinger` (:123), `TriggerCoordinator` (:138). The third takes it to configure, not to claim; the two claim sites are unchanged. `manualAndAutomaticShareOneWindow`, `fiftyConcurrentClaimsAtTheSameInstantAllowExactlyOne`, `twoTriggersTwentySecondsApartProduceOnePing`. 04-15 added a collaborator to `TriggerCoordinator` but no limiter construction: `grep -rn "PingRateLimiter(" src/` still returns the one app site plus the `#Preview`. |
| D-15: MapKit confined to one file, reverse geocoding only | VERIFIED | `grep -rn "import MapKit" src/` → one hit; `grep -rnE '\bMK[A-Z]' src/` outside that file → none. smoke.sh:109-135 enforces both import and type, anchored on `^path:`. |
| Empty label never delays or drops a ping | VERIFIED | `label(for:)` is non-throwing, bounded by construction (unstructured fetch + `Mutex` one-shot, never awaited); `aLabelAttemptRespectsItsBudget` measures real elapsed < 2 s at a 50 ms budget against unreachable MapKit. `AutomaticPinger` sends regardless of label value — no branch on empty. |
| 04-01: BUILT plist carries `location`+`fetch` and the Always purpose string | VERIFIED | `PlistBuddy` on `build/dd-smoke/.../GrokBotLocator.app/Info.plist` returned both modes and `NSLocationAlwaysAndWhenInUseUsageDescription`; smoke's background-modes guard reads the same built file. |
| 04-05: a wake drains silently, a foreground drain still announces | VERIFIED | presence is explicit state set from `scenePhase` (GrokBotLocatorApp.swift:145-160), default `false`; `QueueDrainCoordinatorTests` covers both directions. |
| 04-13: no-queue fallback still arms and pings | VERIFIED (code trace only, no test — still unchanged) | `triggerCoordinator` built unconditionally; `queueCoordinator` nil → drain closure is `await nil?.drainForeground()`, a no-op. No test exercises the `queue == nil` composition. |
| 04-11: only a real ping advances the reference | VERIFIED (coincidental-reliance — still unchanged) | `aRateLimitedPingDoesNotAdvanceTheReference`, `twoSimultaneousWakesProduceOnePingAndOneReference`. Holds only because `.pinged` is returned for `.failed` and `.queued` too, and the `.noCredentialsOrFix` arm is decided by **exact string equality** against a sentence duplicated in PingSender.swift:167,180 (AutomaticPinger.swift:91) — `grep -rn noCredentialsOrFix tests/` still returns 0, and a reworded sentence silently turns a credential-less attempt into a reference advance. Neither 04-14 nor 04-15 touched `AutomaticPinger.swift`, and 04-15 put D-16's `lastPing?.save` under that same `.pinged` guard — so the durable coordinate now inherits the reliance too. |
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
- [ ] **REQ-08 cold relaunch — RE-RUN DONE 2026-09-12, still NOT verified; now blocked on real
  hardware.** Two further defects were found and fixed by driving it (debug/001: no
  `CLServiceSession` on an already-Always cold relaunch; debug/002: a stale surviving region was
  never re-centred). After both fixes the region demonstrably arms at the reference — and
  `CLMonitor` still delivered ZERO events over 250 m and then 2 km of real interpolated movement,
  with the events loop confirmed running, in BOTH `add`/`events` orderings. `monitor.add` also
  never updated the monitor file. **Two premises below did not hold and are corrected:** (a) that
  04-15's probe measured events being delivered on the simulator — they are not, for this app;
  (b) that the registered region is a reliable readable-back durable record — on the simulator it
  is not, so D-16's last-ping file is load-bearing here rather than belt-and-braces. Whether
  either holds on real hardware is untested; the 04-15 probe was a throwaway and is gone, so the
  disagreement cannot be settled by re-reading it. Full evidence in `.planning/debug/002-*.md`.
  **Superseded original note follows.**
- [ ] **REQ-08 cold relaunch — re-run needed after 04-15.** The earlier NOT-REPRODUCED had two
  candidate causes; 04-15's throwaway probe **ruled out both by measurement** (RESEARCH.md "Q2
  addendum"): `CLMonitor(name:)` recovered its condition after a real `simctl terminate`
  (`launch=1`, no re-add), and events ARE delivered on the simulator. What remained was the
  arming gap itself, now closed. Re-run: geofence-only configuration, cold relaunch, move past
  the 150 m radius → exactly one exit ping; then move again → a second (re-registration).
  Still needs a device for the terminated-app wake; `simctl` cannot produce one.
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
- [ ] **D-16 protection class on device** — read `.protectionKey` back off `LastPing.json` on real
  hardware and confirm `.completeUntilFirstUserAuthentication`. The simulator cannot answer this:
  the control file, written with no protection option, also reports nil, so the unit test asserts
  the write-options constant instead. Also the point at which to confirm the deliberate
  weaker-than-the-queue trade D-16 calls out (a geofence exit writing while locked) rather than
  the stronger class.
- [x] Backstop: `hydrate()` copying queue entries into `PingHistoryLog` — **RULED D-17**
  (2026-09-11 17:40, "approved"): the shipped behaviour stands and D-12's clause is narrowed to a
  second *durable* copy. Still wants a test pinning that the copy is session-only.
- [x] Backstop: `UnqueuedPingSink`'s 429 sentence vs D-14 — **RULED D-18** (2026-09-11 17:40,
  "downgrade ratified"), and the forced copy change is now DONE: the sink supplies its own
  `noQueueReason` instead of echoing the classifier's retry promise, pinned by
  `theNoQueueSinkDoesNotEchoTheRetryablePromise` (2026-09-12).
- [x] Backstop: `MKReverseGeocodingRequest` throttling/offline contract — **RULED D-19**
  (2026-09-11 17:40, "empty label"): any failure ⇒ empty label, bounded by construction. Still
  wants a test pinning the rule generally rather than per-error-case.

<!-- 2026-09-12 correction: an earlier STATE.md "Next" line said these three needed RULING. They
did not — they were ruled on 2026-09-11 17:40. What was outstanding was tests, plus D-18's copy
change. D-18 is now closed; D-17 and D-19 still want their pinning tests. -->

## Learnings
- A bound that depends on a vendor API honouring `cancel()` is not a bound: `MKReverseGeocodingRequest.mapItems` did not resume on `cancel()` with no service reachable and hung indefinitely. The pattern that works is an unstructured, never-awaited fetch plus a `Mutex`-guarded one-shot continuation — bounded by construction. Any future "race X against a timeout" should copy this shape, not `withTaskGroup`.
- Persisting a setting, displaying it, and enforcing it are three separate wirings. Phase 04 shipped the first two for the minimum interval and missed the third (closed by 04-14) because no plan owned the seam between `TriggerSettings` (the stored value) and `PingRateLimiter` (the enforcer). When a value is stored in one type and enforced in another, a plan must name the call that carries it across — and the test for it must use the REAL enforcer: every fake `PingRateLimiting` in this suite returns `.allowed` unconditionally, so a fake-based test would have passed against the broken wiring.
- A premise stated in a doc comment is not a verified fact. `GeofenceMonitor.swift` asserted "the registered region IS the durable record ... rather than this app keeping a second coordinate file", resting on a CLMonitor persistence claim RESEARCH listed as UNVERIFIED — and that premise is what left REQ-08 unable to arm in a geofence-only cold start. A throwaway probe settled it in one afternoon; the gap was found by running the app, not by reading it.
- Serialized execution kept commit attribution clean: every phase-04 commit touches only its own plan's files (the 04-09/04-10 spillover is protocol-widening fan-out, declared in both SUMMARYs), and no trailer crosses plans. 04-11's five commits carry no `Co-Authored-By` trailer at all — a convention miss, not crossed attribution.
