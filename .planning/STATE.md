<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 2 of 4 (Manual ping) | Plans: 13 written, 10 executed | Status: EXECUTING
Last: 2026-09-10 — 02-10: SettingsModel.testConnection + ConnectionReport (REQ-11); smoke 84 tests/12 suites.
Next: /flow-execute 2 — resume at plan 02-11
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
Stopped: 02-10 committed (e56842a, 4e92cd3). Waves serial — smoke.sh shares one xcodeproj and
  derived-data dir; human checks batch at 02-11/02-13.
Resume: /flow-execute 2 at 02-11. FLAKY: PingModelTests in-flight case hung 2/5 runs (02-10
  deferred). ACTION (human, on-device): re-save credentials on the iPhone to migrate Keychain to
  ThisDeviceOnly. ~15 PR #1 should-fix findings unfixed. D-03 OPEN (expires 2026-09-16).
