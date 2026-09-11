<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 14/14 | Status: verifying — human checks pending
Last: 2026-09-11 — 14 plans executed, gap closed, smoke GREEN 259 tests/28 suites, gaps: [].
Next: run the 10 human checks in phases/04-automatic-triggers/VERIFICATION.md, then /flow-pr
## Gate
type: human-action
asked: Phase 04 is code-complete and green, but 10 checks need a real device and 3 backstop
  truths need a stated RULE. Full list in VERIFICATION.md.
options:
  1. Run the 10 device checks + rule the 3 backstops, then /flow-verify 4 → /flow-pr.
  2. Rule the 3 backstops now, defer device checks to UAT — phase stays unverified.
  3. Open the PR first and treat the checks as PR evidence — merges REQ-06/07/08 unproven.
default: none
## Run
Iteration: 4 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule5:phase04:plans14/14:verifhuman
## Decisions
- D-12/D-13/D-14: queue is the one coordinate store; type −1 step; 429+408 retryable
- D-15: MapKit authorized for reverse geocoding, confined to one file
## Blockers
- none (the REQ-09 enforcement gap was closed by 04-14)
## Session
Stopped: phase 04 code-complete, 63 commits on flow/automatic-triggers, NOT pushed to a PR.
Resume: 3 backstops need a rule — hydrate() vs D-12, UnqueuedPingSink's 429 vs D-14, MapKit
  throttling. 2 qualified passes: 04-11's reference-advance rests on exact string equality across
  3 files (untested); 04-13's no-queue path is code-trace only.
