<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 13 | Status: ready
Last: 2026-09-11 — planned: 13 plans, 6 waves, checker PASS after 1 round closed 14 blocking issues.
Next: rule the gate, then /flow-execute 4
## Gate
type: decision
asked: Reverse-geocoded labels, a stated phase-04 deliverable, cannot be built as specified.
  `CLGeocoder` is soft-deprecated at iOS 26.0 ("Use MapKit"); its replacement
  `MKReverseGeocodingRequest` is in MapKit, NOT on ARCHITECTURE's closed Frameworks list.
  As planned, phase 04 ships EMPTY labels.
options:
  1. Add MapKit to ARCHITECTURE Frameworks — 04-04 gains 1 file; labels ship as REQ-06/07/08 specify.
  2. Ship empty labels — plans run unchanged; label half defers; marker stays open.
  3. Use CLGeocoder anyway — no ARCHITECTURE edit, builds on an API Apple says to stop using.
default: none
plan: 04-04
## Run
Iteration: 2 | Started: 2026-09-11T15:03Z | Repeats: 0
Signature: rule6:phase04:plans13/13:verifnone
## Decisions
- D-12: queue is the one sanctioned coordinate store; payload gains `at`
- D-13/D-14: type scale −1 step; 429+408 retryable; 7-day give-up; keep-until-shown
## Blockers
- none
## Session
Stopped: phase 04 planned on flow/automatic-triggers. Nothing executed.
Resume: 3 rulings open besides the gate — ARCHITECTURE silent on UIBackgroundModes:location; and
  PR #4's two, held as backstop truths on 04-05 (hydrate() vs D-12) and 04-10 (UnqueuedPingSink
  calls a 429 permanent). ROADMAP says rule both here. Phase 02's 11 checks still open.
