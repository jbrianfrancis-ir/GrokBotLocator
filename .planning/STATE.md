<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 4/13 | Status: executing
Last: 2026-09-11 — wave 1 done (04-01/02/03/05), fan-in smoke GREEN 195 tests/21 suites.
Next: wave 2 — 04-04, 04-06, 04-07, 04-08, 04-09 (serialized)
## Gate
none — D-15 (add MapKit; narrow to one file) answered 2026-09-11.
## Run
Iteration: 2 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule4:phase04:plans0/13:verifnone
## Decisions
- D-12: queue is the one sanctioned coordinate store; payload gains `at`
- D-13/D-14: type scale −1 step; 429+408 retryable; 7-day give-up; keep-until-shown
- D-15: MapKit authorized for reverse geocoding, confined to one file
## Blockers
- none
## Session
Stopped: mid phase-04 execution, wave 1 of 6 complete. Executors run SERIALIZED, not
  parallel — LEARNINGS: a shared git index crosses commit attribution regardless of disjoint files.
Resume: 3 rulings still open (D-15 answered only the geocoder) — ARCHITECTURE silent on
  UIBackgroundModes:location; and
  PR #4's two, held as backstop truths on 04-05 (hydrate() vs D-12) and 04-10 (UnqueuedPingSink
  calls a 429 permanent). ROADMAP says rule both here. Phase 02's 11 checks still open.
