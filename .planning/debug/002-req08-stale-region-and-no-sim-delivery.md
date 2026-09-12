<!-- .planning/debug/NNN-slug.md — persistent debug state; resumable across sessions. -->
---
status: resolved            # open | resolved
symptom: REQ-08 still does not fire after debug/001 — a stale region is never corrected (fixed), and the simulator's geofence never settles so no exit is ever delivered (platform)
started: 2026-09-12
---

## Repro
Machine-driven, iPhone 17 Pro / iOS 26.5 simulator (E188EA3E), Debug build, instrumented with
temporary `print` probes (reverted; not committed):
1. `simctl install`; `simctl privacy grant location-always`.
2. `defaults write` geofence ON, significant-change OFF, visits OFF, interval 15.
3. `simctl location set 37.33888380,-122.03254703`; seed
   `Library/Application Support/LastPing.json` = `{"latitude":37.33888380,"longitude":-122.03254703}`.
4. `simctl terminate` then `launch --console-pty` (cold relaunch, Always ALREADY granted).
5. `simctl location start --speed=15 --distance=25 37.33888380,-122.03254703 37.34112980,-122.03254703`
   (250 m north, real interpolated movement). Also repeated at 2 km / `--speed=30`.

## Hypotheses
| ID | Hypothesis | Status | Evidence |
|----|-----------|--------|----------|
| H1 | debug/001's session fix works | confirmed | Probe: `beginAlwaysSession called` on the already-Always cold relaunch. |
| H2 | `applySettings` never corrects a region that survived a relaunch centred somewhere else | confirmed | Probe: `centre=37.33527476 reference=37.3388838` (~400 m apart) → `DID NOT register`. `centre == nil` treated "a region exists" as "the right region exists". A region you are already outside of never produces an exit TRANSITION, so REQ-08 could never fire again for that region's life. FIXED. |
| H3 | Event delivery needs `add` BEFORE iterating `monitor.events` | refuted | Swapped `start()` so `applySettings` (and its `monitor.add`) ran before `startObserving`. Probe confirmed the new order (`monitor.add done` then `events loop STARTED`). Still ZERO events after 250 m. Order swap reverted — it changed nothing and is unproven. |
| H4 | `CLMonitor` does not deliver region events to this app on this simulator | **DOWNGRADED - do not trust** | With the region armed at the reference and `events loop STARTED` logged, 250 m AND a 2 km / 67 s route produced ZERO `PROBE: EVENT` lines in both orderings, and the loop never threw. BUT the control run invalidates the attribution: **significant-change, recorded PASSED on this same simulator on 2026-09-11, also fired nothing today** - 520 m past the 500 m gate, geofence off, `location-always` re-granted after the reinstalls, twice. So NO wake-based location trigger is firing on this simulator right now, and the silence cannot be pinned on `CLMonitor`. Cause environmental/unknown. |
| H6 | The simulator (or its location/authorization state) stopped delivering wake-based location events today | untested - most likely explanation | The control above. Not yet eliminated: privacy grants wiped by repeated `simctl install`; a stuck `CLServiceSession`; simulator location state left dirty by many `location start` runs; runtime 26.5 behaviour. A fresh `simctl erase` + one clean run would test it cheaply. |
| H5 | `monitor.add` does not persist on this simulator | confirmed | `Library/CoreLocation/GrokBotLocator/GrokBotLocatorTriggers.monitor` mtime stayed `12:04:02` across several successful `monitor.add` calls at 12:28–12:32, and `currentCentre()` kept reading back the 12:04-era 37.33527476 after a fresh launch had added 37.3388838. |

<!-- Status: untested | testing | refuted | confirmed -->

## Evidence log
- 2026-09-12: Re-ran REQ-08's repro after debug/001. Symptom UNCHANGED at first — history read
  "No pings yet" (screenshot `req08-hop1.png`). Probing localised it in one run.
- 2026-09-12: H2 fixed (`centre != reference`), smoke GREEN 271 tests/29 suites, and the new test
  verified red-before/green-after by reverting only the condition (2 failing expectations at
  `TriggerCoordinatorTests.swift:523,527`).
- 2026-09-12: After the H2 fix the region DOES arm at the reference — and still no exit fires,
  which is H4/H5. That is the remaining blocker and it is not app logic.

## Contradicts VERIFICATION.md — two stated premises did not hold
1. VERIFICATION line 6 / the human-check entry both say 04-15's probe measured that `CLMonitor`
   "events ARE delivered on the simulator". Measured here: they are not, for this app, in either
   `add`/`events` ordering, over 2 km of interpolated movement, with the loop confirmed running.
2. `GeofenceMonitor.swift`'s premise that the registered region is a durable readable-back record
   is not true on the simulator: `add` did not update the monitor file at all (H5), so
   `currentCentre()` returns stale data. D-16's last-ping file is therefore load-bearing here,
   not "belt-and-braces".

Whether either premise holds on real hardware is untested. The 04-15 probe was a throwaway and is
gone, so the disagreement cannot be reconciled by re-reading it.

## Open decision for the human (do not guess)
`centre != reference` uses EXACT equality. If a device round-trips `condition.center` inexactly,
every arming pass re-registers — idempotent under the single fixed identifier, but it also resets
the region's inside/outside baseline, which could itself suppress an exit. A tolerance would be a
new numeric constant (cf. `radiusMetres`'s backstop note) and is a ruling, not an improvisation.

## Controlled re-test on an ERASED simulator (2026-09-12, decisive)
`simctl erase` + one install + one grant removed the dirty-state confound that made H4
untrustworthy. Three runs on that clean device, same build (clean HEAD, no probes), same grant:

| Run | Config | Result |
|-----|--------|--------|
| 1 | significant-change only | **FIRED** — row at 12:47, `Cupertino`, 37.33260,-122.03032, "Failed: add your webhook URL" (no credentials configured; the trigger and the send path both ran). Reverse geocoding worked on a real send path, so D-15 is good. |
| 2 | geofence only, `LastPing.json` seeded at 37.33260,-122.03032, 250 m route | **DID NOT FIRE** — "No pings yet" at 12:51. |
| 3 | both on, same reference, 600 m route | **ONE row**, 12:52, 37.33711,-122.03032 = **502 m** north of the reference. |

Run 3 is the one that settles it, because it carries its own movement witness: 502 m proves the
route actually moved the device (runs 1-2 could not rule out `simctl location` being ignored --
run 1's ping came from the default location at launch, not from the route). The device therefore
crossed the 150 m radius roughly 350 m BEFORE the point that pinged, and nothing fired for it.
The single row is significant-change's 500 m gate landing on the first update at/past 500 m --
the same behaviour VERIFICATION measured at 500.8 m on 2026-09-11.

So, with the confound removed and movement witnessed: **significant-change delivers on the
simulator and the geofence does not.** H4's conclusion is restored, now with the control it
previously lacked; H6 (dirty simulator state) was real but explains only the earlier
significant-change silence, not the geofence's.

`LastPing.json` did not advance in any run (no credentials ⇒ `.noCredentialsOrFix` ⇒
`pingAndAdvance` returns before saving, which is correct). The first exit is still a fair test:
the launch-time registration from the seeded file is what the device then left.

**Not eliminated:** that the region failed to ARM in runs 2-3. These runs carried no probes, so
arming was not observed -- only inferred from the debug/002 fix plus a seeded reference and no
pre-existing region on an erased device. An instrumented run would close that, and is the one
cheap thing left before blaming the platform.

## INSTRUMENTED RUN — the region DOES arm, and locationd explains the silence (2026-09-12)
`NSLog` probes on both trigger paths (reverted, not committed; `print` + `--console-pty` captured
nothing, the unified log via `simctl spawn log show` did). Geofence + significant-change both on,
reference seeded at 37.33260,-122.03032, 600 m interpolated route.

**App side — every step works:**
```
PROBE: auth=3 (3=alwaysAuthorized)
PROBE: beginAlwaysSession called            <- debug/001's fix, confirmed live
PROBE: geofence branch entered
PROBE: centre=37.3326,-122.03032  reference=37.3326,-122.03032
PROBE: DID NOT register (centre already == reference)   <- debug/002's no-churn branch, correct
PROBE: WITNESS sigchange fix 37.3326,-122.03032
PROBE: WITNESS sigchange fix 37.337112599734624,-122.03032   <- 502 m, movement witnessed
```
No `EVENT` line and no `runGeofenceExit REACHED`: `CLMonitor` delivered nothing to the app.

**locationd side — the region is registered, and the OS says why it stays quiet:**
```
Fence: fenceUpdate, com.bfrancis.grokbotlocator::GrokBotLocatorTriggers@last-ping-region,
  bundle com.bfrancis.grokbotlocator, type GPS, distance 598, fence ... 150.0,
  sCount 0, sinceLastLoc 15.0,
  status (Inside) => (Outside)          [2 samples]
  settled state (No) ==> (Unknown)      [25 samples]
  settled state (Unknown) ==> (Unknown) [9 samples]
```
Across 34 fence samples: **`sCount` (settle count) never leaves 0 and the settled state never
leaves `No`/`Unknown`** — even though raw `status` DID compute `(Inside) => (Outside)` twice.

## Root cause of the remaining silence: the fence never SETTLES on the simulator
iOS's geofence state machine keeps a raw status and a *settled* state, and only reports a
transition to the app once the fence has settled. The simulator feeds synthetic fixes roughly
every 15 s (`sinceLastLoc 15.0`), which never satisfies the settling logic, so `sCount` stays 0,
the settled state stays `Unknown`, and locationd never promotes the Inside->Outside crossing it
already computed into a delivered event.

**This is a simulator limitation with a measured mechanism, not an app defect.** Arming,
authorization, the service session, region identity and radius, and the app's view of the movement
are all confirmed correct by the OS's own log. Nothing in `src/` can make the simulator settle a
fence.

## Resolution
**Arming is CONFIRMED — by locationd, not inferred.** The fence is registered under
`GrokBotLocatorTriggers@last-ping-region` at radius 150.0, with Always authorization and the
service session held. The open question from the previous section is closed.

**The two code defects found here are real and fixed:** debug/001's missing `CLServiceSession`
and debug/002's stale region never re-centred. Both verified live in this run — the session probe
fired, and the no-churn branch correctly skipped a redundant re-registration when the region
already sat on the reference.

**REQ-08 cannot be verified on the simulator, for a now-understood reason:** the fence never
settles, so no exit is ever delivered. REQ-08's acceptance clause needs a real device, where
continuous GPS settles the fence. Status: NOT VERIFIED, cause understood, no app-side work
outstanding.

**REQ-06 significant-change is unaffected and works** — it does not depend on fence settling,
which is exactly why it fired in the same run that the geofence did not.
