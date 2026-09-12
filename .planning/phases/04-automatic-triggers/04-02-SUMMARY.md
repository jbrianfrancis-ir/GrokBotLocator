---
plan: 04-02
status: complete
agent: executor/claude/sonnet
commits: [afc086b, 944b8ae]
deviations: []
human_checks: []
deferred: []
---
Built `PingRateLimiter` (src/Core/Ping/PingRateLimiter.swift): actor + `PingRateLimiting`
protocol + `RateLimitDecision` enum. 15s hard floor, 60s default, `>=` boundary, clamps (never
rejects) any interval below the floor including NaN/negative. `claim(at:)` has no `await` --
verified by falsifying with `await Task.yield()` (absence-grep caught it) then reverting.
Tests (tests/PingRateLimiterTests.swift) cover floor/default/boundary/refusal-sentence/shared-
window/50-concurrent-claims, all against fixed dates, no sleeps. Falsified the `>=`→`>` boundary
mutation for real: `aClaimExactlyOneIntervalLaterIsAllowed` and
`theIntervalCannotBeSetBelowFifteenSeconds` failed as predicted, then reverted (git diff
confirmed clean before recommitting). Both backstop truths documented in the file header as
open, not derived. Smoke passed both times for real (177 then 184 tests).
