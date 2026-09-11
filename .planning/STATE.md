<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 13/13 executed | Status: verifying
Last: 2026-09-11 — all 13 plans executed, smoke GREEN 257 tests/28 suites. VERIFICATION: 1 gap.
Next: /flow-plan 4 --gaps (REQ-09 enforcement seam), then re-verify
## Gate
none — D-15 answered 2026-09-11. 8 human checks + 3 backstops await a device/human at re-verify.
## Run
Iteration: 3 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule5:phase04:plans13/13:verifgaps
## Decisions
- D-12: queue is the one sanctioned coordinate store; payload gains `at`
- D-13/D-14: type scale −1 step; 429+408 retryable; 7-day give-up; keep-until-shown
- D-15: MapKit authorized for reverse geocoding, confined to one file
## Blockers
- GAP REQ-09: a minimum interval set in Settings is persisted and DISPLAYED but never reaches
  the gate. `PingRateLimiter.setMinimumInterval` has zero callers in src/; TriggerCoordinator
  holds no limiter reference. The limiter keeps 60s for the process life while the screen says
  otherwise ("This gap covers the I'm here button too"). Floor and default are unaffected.
## Session
Stopped: phase 04 executed + verified; 1 gap to close. 58 commits on flow/automatic-triggers.
Resume: /flow-plan 4 --gaps. Then the human checks: REQ-06/07/08 on device, REQ-05's fourth drain
  end-to-end, REQ-10's live prompt, AX5 audit, SC-03 battery — plus 3 backstops needing a stated
  rule (hydrate() vs D-12, UnqueuedPingSink's 429 vs D-14, MapKit throttling).
