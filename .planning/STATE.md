<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 2 of 4 (Manual ping) | Plans: 13/13 | PR #2 OPEN, CLEAN | Verify: human_needed
Last: 2026-09-10 — PR #2 opened. 7-lens review: 1 security blocking (redirect leaked key+coords) + 8 defects fixed, each falsified. Gate 84->107 tests.
Next: run the human checks in VERIFICATION.md; human review+merge of PR #2
## Gate
type: verification-human-checks
asked: On-screen acceptance needs a human — 6 checks in VERIFICATION.md (endpoint ping + 401, label survives force-quit, When-In-Use/Never, phase-01's 3 deferred components, REQ-12 Inspector both screens, REQ-11 401). Plus: 2 ARCHITECTURE contradictions to settle before phase 03.
options: run them and record pass/fail | merge and carry them | waive (not advised)
default: run them
note: AX5 actionLabel>screenTitle is ACCEPTED (15:30); never file it.
## Run
Iteration: 3 | Started: 2026-09-10T15:31Z | Repeats: 0
Signature: rule4:phase02:plans13/13:verifhuman_needed
## Decisions
- init: iOS 26.0; deploy.tool null — merge is terminal (D-01/04/07)
- 15:30: curves LEFT ALONE; AX5 inversion accepted, pinned by 02-01
## Blockers
- none
## Session
Stopped: PR #2 open (https://github.com/jbrianfrancis-ir/GrokBotLocator/pull/2), CLEAN, 0 checks (no CI).
Resume: human checks, then merge. GATE for human: 2 ARCHITECTURE contradictions block
  phase 03 (queue vs raw-coordinates ban; no timestamp in pinned payload). ACTION: re-save
  credentials on the iPhone (ThisDeviceOnly).
