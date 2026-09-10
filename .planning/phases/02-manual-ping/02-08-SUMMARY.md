---
plan: 02-08
status: complete
agent: executor/claude/claude-sonnet-5
commits: [c897a42, 45ffba0]
deviations: []
human_checks: []
deferred: []
---
PingSender (src/Ping/PingSender.swift) does the whole manual ping: load credentials, take one
fix, encode, POST, classify, return a PingAttempt (fix, disposition, statusCode, responseBody).
Init is exactly `PingSender(credentials:fixes:transport:pending:)` as pinned for 02-13.
PendingPingSink + UnqueuedPingSink ship as the no-op phase-03 seam; only `.retryable` reaches
`enqueue` — `.sent`/`.permanentFailure` (401 included) never do, per ARCHITECTURE's no-silent-drop
principle. tests/PingSenderTests.swift covers all 8 branches with 4 in-file fakes, no network/device.
Both task verify greps and both plan falsify edits (reintroducing URLSession.shared; routing
.permanentFailure to the sink) reproduced the plan's predicted failures, then reverted.
smoke.sh: exit 0, TEST SUCCEEDED, 66 tests/11 suites (up from verified baseline 58/10).
