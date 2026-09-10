<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 2 of 4 (Manual ping) | Plans: 13 written, 0 executed | Status: PLANNED, checker PASS
Last: 2026-09-10 — phase 01 merged (PR #1). Phase 02 planned: 13 plans, 3 revision rounds, 24 checker issues all resolved, final PASS re-confirmed against HEAD by a second checker.
Next: /flow-execute 2
## Gate
none
## Run
Iteration: 2 | Started: 2026-09-10T15:31Z | Repeats: 0
Signature: rule4:phase02:plans0/13:verifnone
## Decisions
- init: iOS 26.0, native SwiftUI; deploy.tool null — merge is terminal, no UAT/release (D-01/04/07)
- gate: sender key never re-rendered; "key saved" indicator (D-10)
- plan: on-disk queue is the durability mechanism, not background URLSession (D-09)
- 15:30 gate: type curves LEFT ALONE, phase 02 ungated — AX5 actionLabel>screenTitle accepted, pinned by 02-01's tripwire
- plan 02: wire bytes hand-composed in ARCHITECTURE's key order (JSONEncoder order is non-deterministic, proven on-simulator); retryable failure records .failed, phase 03 swaps the queue in via PendingPingSink
## Blockers
- none
## Session
Stopped: planning closed on flow/manual-ping. 13 waves, fully serial — smoke.sh shares one
  xcodeproj and derived-data dir. Runs unattended; human checks batch at 02-11/02-13.
Resume: /flow-execute 2. ACTION (human, on-device): re-save credentials on the iPhone to migrate
  Keychain items to ThisDeviceOnly. ~15 PR #1 should-fix findings unfixed. D-03 OPEN (expires 2026-09-16).
