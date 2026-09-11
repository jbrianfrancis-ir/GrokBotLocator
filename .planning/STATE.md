<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 3 of 4 PR #4 OPEN — 12/12 plans, smoke 177/19, 8/8 checks closed, 0 gaps
Last: 2026-09-11 — acceptance found a DOUBLE-DELIVERY bug no test caught (actor reentrancy, 64f7b7d). D-13 shrank the type scale; D-14 settled all 3 backstops.
Next: review + merge PR #4 (human); then /flow-next. Phase 02's 11 checks still open
## Gate
none — D-13 (type scale; amends DESIGN.md + REQ-12) and D-14 (4xx policy, give-up horizon,
retention, bundle-id scope) answered 2026-09-11. All 3 backstops now stated in REQUIREMENTS.md.
## Run
Iteration: 3 | Started: 2026-09-10T19:10Z | Repeats: 0
Signature: rule8:phase03:plans12/12:verifpass
## Decisions
- init: iOS 26.0; deploy.tool null — merge terminal (D-01/04/07)
- 15:30: type curves LEFT ALONE; AX5 inversion accepted (02-01)
- D-12: queue is the one sanctioned coordinate store; payload gains `at`
## Blockers
- none
## Session
Stopped: PR #4 open — https://github.com/jbrianfrancis-ir/GrokBotLocator/pull/4. Review found 6
  blocking defects AFTER verification said pass; 3 were actor reentrancy, 1 was a locked device
  destroying the queue. All fixed, 3 rounds, final round clean. Docs only, no CI on this repo.
Resume: merge is human. 2 open decisions in the PR body: hydrate() vs ARCHITECTURE:72's "never
  copied", and UnqueuedPingSink relabelling a 429 as permanent ("Failed: it is waiting").
