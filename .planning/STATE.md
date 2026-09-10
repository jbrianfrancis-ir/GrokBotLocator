<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 2 of 4 (Manual ping) | Plans: 13/13 | Verify: human_needed, 0 gaps
Last: 2026-09-10 — 13 waves executed, smoke green (84 tests/12 suites). 0 gaps, 3 backstops unverified, 6 human checks open. Fixed 1 flaky hang, 2 guard holes.
Next: run 6 human checks in VERIFICATION.md, then /flow-pr
## Gate
type: verification-human-checks
asked: On-screen acceptance needs a human. 6 checks in VERIFICATION.md: endpoint ping + 401 (REQ-02/04/SC-01), label survives force-quit (REQ-03), When-In-Use/Never (REQ-10), phase-01's 3 deferred components, REQ-12 Inspector both screens, REQ-11 401 on screen.
options: run them and record pass/fail | carry into /flow-pr | waive (not advised: phase 01 closed REQ-12 that way, then 02-01 voided it)
default: run them
note: AX5 actionLabel>screenTitle is ACCEPTED (15:30); never file it.
## Run
Iteration: 3 | Started: 2026-09-10T15:31Z | Repeats: 0
Signature: rule4:phase02:plans13/13:verifhuman_needed
## Decisions
- init: iOS 26.0; deploy.tool null — merge is terminal (D-01/04/07)
- 15:30: curves LEFT ALONE, ungated; AX5 inversion accepted, pinned by 02-01
- plan 02: wire bytes hand-composed (JSONEncoder order non-deterministic); retryable=.failed
## Blockers
- none
## Session
Stopped: 13/13 executed on flow/manual-ping, guard fix at HEAD, NOT pushed.
Resume: human checks, then /flow-pr. 3 backstops need a rule + test. ACTION: re-save
  credentials on the iPhone (ThisDeviceOnly).
