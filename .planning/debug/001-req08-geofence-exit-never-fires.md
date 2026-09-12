<!-- .planning/debug/NNN-slug.md — persistent debug state; resumable across sessions. -->
---
status: resolved            # open | resolved
symptom: REQ-08 geofence exit never fires at runtime despite 04-15's unit tests passing
started: 2026-09-12
---

## Repro
From STATE.md Blockers (reproduced twice on device before this session):
1. Settings: geofence trigger ON, significant-change OFF, visits OFF. Always granted.
2. Force-quit, cold relaunch. Valid `LastPing.json` on disk.
3. Drive real interpolated movement 200 m past the 150 m radius
   (`xcrun simctl location "$UDID" start --speed=20 --distance=50 <from> <to>`).
4. Expected: one ping marked geofence exit. Actual: no ping, no history row.

Key precondition, easy to miss: Always was ALREADY granted before this launch.

## Hypotheses
| ID | Hypothesis | Status | Evidence |
|----|-----------|--------|----------|
| H1 | No `CLServiceSession` is ever held on a cold relaunch when Always is already granted, so Always is not effective and `CLMonitor` delivers nothing to a backgrounded app | confirmed | `LocationDelegateProxy.swift:96-98` is the ONLY site assigning `serviceSession`, reachable ONLY from `requestAlways()`. `TriggerCoordinator.swift:108-111` is the ONLY caller, behind `currentAuthorization() != .authorizedAlways`. Already-Always ⇒ guard false ⇒ no request ⇒ `serviceSession` nil for the whole process. RESEARCH Q2/Q5 (WWDC24): "Always authorization will only be effective when you hold one of these." |
| H2 | The unit suite cannot see H1 because every fake starts at When-In-Use | confirmed | `TriggerCoordinatorTests.swift:37` `init(authorization: CLAuthorizationStatus = .authorizedWhenInUse)`. Every `makeCoordinator()` uses the default, so the arming guard is always TRUE under test and `requestAlways()` always runs. No test enters `start()` at `.authorizedAlways`. |
| H3 | `startObserving`'s `event.authorizationDenied` branch `return`s and permanently kills the only observation task; nothing re-arms it | untested — LATENT, not this bug | `GeofenceMonitor.swift:116-118` returns out of the `for try await` loop. `startObserving` is called exactly once, from `TriggerCoordinator.start()` (`:83`). A denial early in the process would silence every later exit even after authorization recovers. Compounds H1 rather than competing with it. |
| H4 | `CLMonitorGeofence`'s real body is unexercised, so any defect in it ships green | confirmed | Every case in `GeofenceMonitorTests.swift` drives the `InMemoryGeofence` fake. The only lines touching the real type are two static-constant assertions (`:86`, `:141`). `register`/`currentCentre`/`startObserving` have zero coverage. |

<!-- Status: untested | testing | refuted | confirmed -->

## Evidence log
- 2026-09-12: Traced the arming path end to end. `serviceSession` has exactly one assignment site
  and one reachable caller, and that caller is gated on NOT already being Always. The repro's
  stated precondition (Always already granted) is precisely the branch that skips it.
- 2026-09-12: Root-caused the green suite: the fake source's default authorization is
  `.authorizedWhenInUse`, so the skipped-request branch has never been executed by a test.
  This is why 04-15's tests pass while the device does not fire.
- 2026-09-12: Confirmed the plist is not at fault — `UIBackgroundModes: [location, fetch]`,
  `NSLocationAlwaysAndWhenInUseUsageDescription` present (`project.yml:31-45`).

## Evidence log (continued)
- 2026-09-12: H1 confirmed EMPIRICALLY, not by reading. Added a coordinator test that enters
  `start()` at `.authorizedAlways` with the geofence trigger on. It failed against the shipped
  code (268 tests, 1 issue — the new one; all 267 pre-existing tests still green).
- 2026-09-12: After the fix, smoke GREEN at 269 tests / 29 suites, every guard passing.
- 2026-09-12: Verified the regression test pins BEHAVIOUR, not merely the new API's existence.
  Re-gated only `beginAlwaysSession()` behind the old `!= .authorizedAlways` condition, leaving
  everything else in place: `startingAlreadyAlwaysStillHoldsTheAlwaysSession()` went red at
  `TriggerCoordinatorTests.swift:404` (`beginAlwaysSessionCount == 1`). Restored, green again.

## Resolution
**Root cause.** `TriggerCoordinator.applySettings` conflated two different things behind one
condition: REQ-10's Always *prompt*, and the `CLServiceSession` that makes an Always grant
*effective*. Session creation lived inside `LocationDelegateProxy.requestAlways()` — its only
assignment site — and the only caller was gated on `currentAuthorization() != .authorizedAlways`.

A grant is durable across launches; the session dies with the process. So a cold relaunch of an
app that had already been granted Always took NEITHER branch — nothing to request, therefore no
session either — and per RESEARCH Q2/Q5 (WWDC24) "Always authorization will only be effective
when you hold one of these", the OS delivered no geofence exit to the backgrounded app. The
region armed and the event loop spun; nothing was ever going to arrive. This is why the symptom
required the already-granted precondition, and why it presented as geofence-only: it is the one
trigger whose acceptance test is run from a cold relaunch.

**Why 04-15's suite could not see it.** `FakeTriggerSource.init` defaults to
`.authorizedWhenInUse`, and every `makeCoordinator()` call used that default — so the arming
guard was TRUE in every single test and the skipped branch had never once been executed. The
tests were green because they only ever drove the working path, not because the path they
asserted about worked.

**Fix.** Split the two concerns into two protocol calls. `LocationTriggerSource` gains
`beginAlwaysSession()`, implemented in `LocationDelegateProxy` as the sole (idempotent,
foreground-only) session-holding touchpoint; `requestAlways()` no longer creates the session.
`applySettings` now calls `beginAlwaysSession()` unconditionally whenever any trigger is enabled
and keeps the prompt gated, so `alwaysWasRequested` still means "we actually asked" and
`authorizationNotice()` is unaffected. All three off still holds no session (REQ-10), now pinned
by an assertion.

**Regression tests** (`TriggerCoordinatorTests`): `startingAlreadyAlwaysStillHoldsTheAlwaysSession`
(the repro, red before / green after), `startingAtWhenInUseBothHoldsTheSessionAndRequestsAlways`
(the other half of the split), plus `beginAlwaysSessionCount` assertions added to the two
existing REQ-10 arming tests. `makeCoordinator` gained an `authorization:` parameter so the
already-granted state is reachable from a test at all — the gap that hid this.

**What this does NOT settle.** The fix removes a proven defect on REQ-08's arming path; it is not
a device pass. Whether holding the session is SUFFICIENT for the OS to deliver an exit to a
backgrounded/terminated app is still open — it is the unsettled truth recorded in
`LocationDelegateProxy`'s own doc comment ("Which of 'holding this session' vs. iterating
`CLMonitor.events` actually keeps Always effective on device is still unsettled"). REQ-08's
acceptance clause still needs the device run in `GeofenceMonitor.swift`'s reproduction steps.

**Correction (2026-09-12).** An earlier version of this file attributed that open question to
D-17/18/19. That was wrong and is retracted: D-17/18/19 were already RULED by the human on
2026-09-11 17:40 ("1 approved / 2 downgrade ratified / 3 empty label") and concern `hydrate()`'s
in-memory copy, the no-queue 429 sentence, and reverse-geocoding failures — none of them the
geofence. What they still needed was TESTS pinning them, not a ruling.

**Latent, deliberately not fixed here (H3).** `GeofenceMonitor.swift:116-118` returns out of the
`for try await` loop on `conditionLimitExceeded || authorizationDenied`, permanently killing the
only observation task — and `startObserving` is called exactly once per process, from
`TriggerCoordinator.start():83`, so nothing re-arms it if authorization later recovers. Never
observed firing, so it is not this bug; worth a todo.

**Also worth knowing:** `CLMonitorGeofence`'s real body (`register`, `currentCentre`,
`startObserving`) has zero test coverage — every `GeofenceMonitorTests` case drives the
`InMemoryGeofence` fake, and the only lines touching the concrete type are two static-constant
assertions. H4 confirmed. Any defect in that file still ships green.
