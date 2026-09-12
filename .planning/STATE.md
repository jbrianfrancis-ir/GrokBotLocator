<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 15/15 | Status: verifying — gaps: [], human checks open
Last: 2026-09-12 — debug/001 RESOLVED: an already-Always cold relaunch held no
  CLServiceSession, so Always was inert. Smoke GREEN 269/29.
Next: re-run REQ-08's device repro (GeofenceMonitor.swift); rule D-17/18/19 → /flow-verify 4
## Gate
type: human-action
asked: No gaps left, smoke green. 5 checks need a device; 3 backstops need a stated RULE —
  an abstention is lifted by a human, never a green test. Full list in VERIFICATION.md
options:
  1. Run the 5 device checks + rule the 3 backstops, then /flow-verify 4 → /flow-pr.
  2. Rule the 3 backstops, defer device checks to UAT — phase stays unverified.
  3. Open the PR now — merges REQ-07/08 unproven on device.
default: none
## Run
Iteration: 6 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule2:phase04:plans15/15:verifhuman
## Decisions
- D-15: MapKit for reverse geocoding, one file
- D-16: 2nd coordinate store — the last-ping position, overwritten never appended
## Blockers
- none blocking. REQ-08's cause FIXED (75d36a2), UNPROVEN on device — D-17/18/19.
- 2 latent findings filed not fixed — see debug/001's Resolution (zero coverage on
  CLMonitorGeofence's real body; a permanently-killable observation task).
## Session
Stopped: 74 commits on flow/automatic-triggers, 3 unpushed. No PR opened.
Resume: REQ-08 had TWO causes, both closed — 04-15's arming gap, debug/001's missing session.
  Sim needs `simctl location start` with lat,lon pairs, not a teleport or .gpx; the repro's
  step 0 (other triggers off, force-quit) is load-bearing.
