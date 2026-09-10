<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State

## Position
Phase: 1 of 4 (Foundation & design system) | Plans: 12/12 | Status: PR #1 open, MERGEABLE/CLEAN
Last: 2026-09-10 — PR #1 opened. 6-lens review found 2 blocking (1 fixed: Clear button hit region; 1 refuted by human: AX5 hierarchy). Fixed 4: Clear button, Keychain ThisDeviceOnly (+regression test), smoke.sh dead exit-code guard, 2 false records in VERIFICATION. Smoke 22 tests green.
Next: human review + merge of PR #1

## Gate
none

## Run
Iteration: 1 | Started: 2026-09-10T14:12Z | Repeats: 0
Signature: none

## Decisions
- init: iOS 26.0 target, native SwiftUI app (D-01, D-07)
- init: no deployable surface — deploy.tool null (D-04)
- gate: sender key never re-rendered; "key saved" indicator (D-10)
- gate: sign with the work team, personal app identity (D-11)
- plan: on-disk queue is the durability mechanism, not background URLSession (D-09)
- verify: 3 phase-01 checks deferred to phase 02, not waived (PingButton, PingOutcomeRow, DSChrome)

## Blockers
- none

## Session
Stopped: PR #1 MERGEABLE/CLEAN, 0 reviews, 0 threads. NOTE: repo has NO .github/workflows —
  zero CI checks exist, so "clean" means unverified-by-CI, not verified. scripts/smoke.sh is
  the only gate and runs locally only.
Resume: review + merge are human; after merge /flow-next (deploy.tool null — no UAT/release). Carry forward: ACTION — re-save
  credentials once on the iPhone to migrate existing Keychain items to ThisDeviceOnly.
  ~15 should-fix findings documented in the PR body, not fixed. D-03 still OPEN (free personal
  team; profile expires 2026-09-16). No .planning/codebase/MAP.md (greenfield).
