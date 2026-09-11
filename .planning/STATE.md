<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 14/14 + 04-15 planning | Status: verifying
Last: 2026-09-11 — REQ-06 PASSES both halves (machine-driven sim, ping at 500.8 m). New gap found.
Next: check + execute 04-15; 7 human checks still open
## Gate
type: human-action
asked: 7 of 10 checks still need a human. REQ-12/AX5, REQ-10, REQ-06 PASSED. The rest need a
  device; 3 backstops need a stated RULE. List in VERIFICATION.md.
options:
  1. Run the 7 remaining checks + rule the 3 backstops, then /flow-verify 4 → /flow-pr.
  2. Rule the 3 backstops now, defer device checks to UAT — phase stays unverified.
  3. Open the PR first, treat the checks as PR evidence — merges REQ-07/08 unproven.
default: none
## Run
Iteration: 5 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule2:phase04:plans14/14:verifgaps
## Decisions
- D-13/D-14: type −1 step; 429+408 retryable; 7-day give-up; keep-until-shown
- D-15: MapKit for reverse geocoding, one file
- D-16: 2nd coordinate store — the single last-ping position, overwritten never appended
## Blockers
- GAP REQ-08 circular arming: cold relaunch with ONLY geofence on can never arm the region.
  D-16 unblocked the fix; plan 04-15 is being written.
## Session
Stopped: 66 commits on flow/automatic-triggers, pushed. No PR opened.
Resume: 3 backstops need a rule — hydrate() vs D-12, UnqueuedPingSink's 429, MapKit throttling.
  Sim testing needs `simctl location start`, NOT a teleport. GPX in scripts/gpx/.
