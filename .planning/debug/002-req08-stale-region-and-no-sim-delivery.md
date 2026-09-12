<!-- .planning/debug/NNN-slug.md — persistent debug state; resumable across sessions. -->
---
status: open                # open | resolved
symptom: REQ-08 still does not fire after debug/001 — a stale region is never corrected, and CLMonitor delivers no events on the simulator at all
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

## Resolution
**H2 is fixed and that fix stands on its own evidence** - probe output plus a red-before/
green-after unit test - independent of anything the simulator does or does not deliver.

**The delivery question is NOT resolved and is no longer attributed to `CLMonitor`.** The control
run (significant-change, PASSED yesterday, silent today) says the simulator stopped delivering
wake-based location events generally. An earlier version of this file called H4 "confirmed
(blocking)" and said events are not delivered on the simulator "for this app"; that
over-attributed a general silence to one API and is retracted - see H4/H6.

**Next cheapest step:** `xcrun simctl erase` a fresh iOS 26 device, install once, grant once, run
ONE significant-change route. If that fires, simulator state was the problem and the geofence run
should be repeated clean. If it does not, the simulator is not a usable oracle for REQ-06/07/08
and all three need real hardware.

**For a personal-use install the real device IS the test.** Nothing here blocks shipping: both
fixed defects make automatic triggers strictly more likely to arm, and neither can make anything
worse than the shipped behaviour.
