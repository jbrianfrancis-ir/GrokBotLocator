# State

## Position
Phase: 1 of 4 (Foundation & design system) | Plans: 12 planned, 0 executed | Status: ready
Last: 2026-09-09 — phase 1 plan-check PASSED: 29 findings resolved, zero regressions, ordering clean.
Next: /flow-execute 1

## Gate
none

## Run
Iteration: 2 | Started: 2026-09-09T18:28Z | Repeats: 0
Signature: rule4:phase01:plans0/12:verifnone

## Decisions
- init: iOS 26.0 target, native SwiftUI app (D-01, D-07)
- init: no deployable surface — deploy.tool null (D-04)
- gate: sender key never re-rendered; "key saved" indicator (D-10)
- gate: sign with the signing team, personal app identity (D-11)
- plan: on-disk queue is the durability mechanism, not background URLSession (D-09)

## Blockers
- none

## Session
Stopped: phase 1 planned and checked; ready to execute
Resume: /flow-execute 1. Toolchain facts established by probe and pinned in the plans:
  xcodegen 2.46 enumerates sources at generate time (every plan adding a file regenerates);
  a HOSTED test bundle is what makes Keychain work on simulator, not the entitlement, which
  matters on device and smoke.sh cannot prove; a Font resolved outside a View never scales,
  so type tokens reach the View through a ViewModifier.
  Non-blocking leftovers: ARCHITECTURE.md:49 "or header" wording; widen
  `grep 'static let .*Font'` to `static (let|var)`; 01-09 has one task.
