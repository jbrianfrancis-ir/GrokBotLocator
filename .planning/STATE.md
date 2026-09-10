<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State

## Position
Phase: 1 of 4 (Foundation & design system) | Plans: 12/12 | Status: PR #1 open, MERGEABLE/CLEAN
Last: 2026-09-10 — PR #1 open. 6-lens review: 1 blocking fixed (Clear button hit region), 1 refuted by human (AX5 hierarchy). 4 fixes: Clear button, Keychain ThisDeviceOnly (+regression test), smoke.sh dead exit guard, 2 false VERIFICATION records. Smoke 22 green.
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
- gate: sign with the signing team, personal app identity (D-11)
- plan: on-disk queue is the durability mechanism, not background URLSession (D-09)
- verify: 3 phase-01 checks deferred to phase 02, not waived (PingButton, PingOutcomeRow, DSChrome)

## Blockers
- none

## Session
Stopped: PR #1 MERGEABLE/CLEAN, 0 reviews/threads. Repo has NO .github/workflows — zero CI
  checks, so "clean" = unverified-by-CI. smoke.sh is the only gate, local only.
Resume: review+merge are human; after merge /flow-next (deploy.tool null — no UAT/release).
  ACTION: re-save credentials once on the iPhone to migrate Keychain items to ThisDeviceOnly.
  ~15 should-fix findings in the PR body, unfixed. D-03 OPEN (free team, expires 2026-09-16).
