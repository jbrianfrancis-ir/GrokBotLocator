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
`(sender:labelStore:fixes:)` per 02-13's call site. Label seeded from the store, written back on
change (REQ-03). `ping()` ignores a second
call while one is in flight. `.sent` records a `.sent` row; `.permanentFailure` and `.retryable`
both record `.failed` with their reason (phase 03 swaps `.retryable` to `.queued`). A fix-less
attempt records nothing and sets `guidance`. Every outcome sets `lastAnnouncement` (DESIGN.md);
`refreshAuthorizationNotice()` copies the provider's sentence after each ping (REQ-10).

tests/PingModelTests.swift: 11 cases, 3 fakes. The `Fakes` helper needed explicit `@MainActor` —
a nested type does not inherit the `@Suite`'s isolation.

Measured: grep guard exits 1; smoke.sh exits 0, `** TEST SUCCEEDED **`, "Test run with 77 tests
in 12 suites passed" (baseline 66/11), "Suite PingModelTests passed".

Falsifies run and reverted. Task 1: a `KeychainCredentialStore` reference made the grep exit 0 as
predicted. Task 2: removing `guard !isInFlight` did NOT fail cleanly — it HUNG. The second
`ping()` overwrote the fake's single continuation, leaking the first ("SWIFT TASK CONTINUATION
MISUSE"); the suite never completed. Same conclusion (the guard is required) by a different
mechanism than predicted — know this before rewriting that test.
