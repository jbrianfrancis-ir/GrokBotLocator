<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 13 | Status: ready
Last: 2026-09-11 — planned: 13 plans, 6 waves. 14 blocking issues closed; D-15 added MapKit, 3 plans revised, re-check PASS.
Next: /flow-execute 4
## Gate
none — D-15 (add MapKit; narrow to one file) answered 2026-09-11.
## Run
Iteration: 1 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule6:phase04:plans13/13:verifnone
## Decisions
- D-12: queue is the one sanctioned coordinate store; payload gains `at`
- D-13/D-14: type scale −1 step; 429+408 retryable; 7-day give-up; keep-until-shown
- D-15: MapKit authorized for reverse geocoding, confined to one file
## Blockers
- none
## Session
Stopped: phase 04 planned on flow/automatic-triggers. Nothing executed.
Resume: 3 rulings still open (D-15 answered only the geocoder) — ARCHITECTURE silent on
  UIBackgroundModes:location; and
  PR #4's two, held as backstop truths on 04-05 (hydrate() vs D-12) and 04-10 (UnqueuedPingSink
  calls a 429 permanent). ROADMAP says rule both here. Phase 02's 11 checks still open.
