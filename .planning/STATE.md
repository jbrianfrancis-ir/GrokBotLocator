<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 15/15 | Status: verifying — gaps: [], human checks open
Last: 2026-09-11 — 04-15 closed the REQ-08 arming gap. Smoke GREEN 267 tests/29 suites.
Next: 5 device checks + rule the 3 backstops, then /flow-pr
## Gate
type: human-action
asked: No gaps left, smoke green. 5 checks need a device; 3 backstops need a stated RULE —
  an abstention is lifted by a human, never a green test. REQ-12/AX5, REQ-10, REQ-06 PASSED.
  Full list in VERIFICATION.md.
options:
  1. Run the 5 device checks + rule the 3 backstops, then /flow-verify 4 → /flow-pr.
  2. Rule the 3 backstops now, defer device checks to UAT — phase stays unverified.
  3. Open the PR now, treat the checks as PR evidence — merges REQ-07/08 unproven on device.
default: none
## Run
Iteration: 6 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule2:phase04:plans15/15:verifhuman
## Decisions
- D-15: MapKit for reverse geocoding, one file
- D-16: 2nd coordinate store — the single last-ping position, overwritten never appended
## Blockers
- none (REQ-09 enforcement closed by 04-14; REQ-08 arming closed by 04-15)
## Session
Stopped: 71 commits on flow/automatic-triggers, pushed. No PR opened.
Resume: CLMonitor persistence + event delivery MEASURED (RESEARCH Q2 addendum) — the earlier
  REQ-08 non-reproduction was the arming bug, not the simulator. Sim testing needs
  `simctl location start` with lat,lon pairs — not a teleport, not a .gpx path.
