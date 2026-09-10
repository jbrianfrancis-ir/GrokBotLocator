---
plan: 02-09
status: complete
agent: executor/claude/claude-sonnet-5
commits: [8431d18, 3393830]
deviations: []
human_checks: []
deferred: []
---
PingModel (src/Ping/PingModel.swift): `@Observable @MainActor final class`, init exactly
`(sender: PingSending, labelStore: PingLabelStore, fixes: LocationFixProvider)` per 02-13's
call site. Label seeded from the store and written back on every change (REQ-03); `ping()`
ignores a second call while one is in flight; `.sent` records a `.sent` row, `.permanentFailure`
and `.retryable` both record `.failed` with their reason (phase 03 swaps `.retryable` to
`.queued`); a fix-less attempt records nothing and sets `guidance` instead; every outcome sets
`lastAnnouncement` (DESIGN.md); `refreshAuthorizationNotice()` copies the provider's sentence
after every ping (REQ-10).

tests/PingModelTests.swift: 11 cases, 3 in-file fakes (a suspendable `PingSending`, an
in-memory `PingLabelStore`, a `LocationFixProvider` whose `currentFix()` must never be called).
The `Fakes` helper struct needed an explicit `@MainActor` -- a nested type does not inherit
the enclosing `@Suite`'s actor isolation, and without it `PingModel`'s MainActor-isolated
init couldn't be called from the struct's synchronous `makeModel()`.

Both task verifies measured: grep guard on PingModel.swift exits 1 (clean). Smoke:
`./scripts/smoke.sh` exits 0, `** TEST SUCCEEDED **`, "Test run with 77 tests in 12 suites
passed" (up from the 66/11 baseline), log shows "Suite PingModelTests passed".

Both falsify checks run and reverted. Task 1: adding a `KeychainCredentialStore` reference
made the grep exit 0 as predicted. Task 2: removing `guard !isInFlight` did not produce a
clean assertion failure -- it hung. The second `ping()` call overwrites the fake sender's
single stored continuation, leaking the first one; the runtime logged "SWIFT TASK CONTINUATION
MISUSE: send(label:) leaked its continuation" and the suite never completed. Confirms the
guard is required (same conclusion as the plan), by a different mechanism than the plan's
"fails on call count" prediction. Backed out via `cp` from a pre-edit backup and diffed
identical to the committed file before re-running the clean smoke pass above.
