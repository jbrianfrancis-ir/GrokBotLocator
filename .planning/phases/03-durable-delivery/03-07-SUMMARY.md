<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-07
status: complete
agent: executor/claude/sonnet
commits: [4d29c77, b7ad86d, d135935]
deviations: ["[Task 1 verify] `grep -nE 'Codable|FileManager|UserDefaults' src/Ping/PingHistory.swift` (expect exit 1) was unsatisfiable at HEAD: a pre-existing header comment already read \"no `Codable` and no persistence of any kind,\" so the whole-file token grep matched comment text, not real conformance/API use -- same class of miss the plan-checker caught and fixed twice elsewhere this phase; this one got through. Reworded that clause to \"never serialized and no persistence of any kind\" -- no behaviour change, only made the guard truthful."]
human_checks: []
deferred: []
---
`PingDeliveryUpdate` + `PingHistoryLog.apply(_:)` (PingHistory.swift): corrects a known row IN
PLACE at its existing index (no reorder), or inserts newest-first via the existing capacity-50
`record`. `PingModel.ping()`'s `.retryable` arm now reads `.queued` (was phase-02's documented
no-op), entries stamped with `attempt.queuedID`. Added `apply(_ updates:announcing:)` --
`announcing` undefaulted on purpose, `true` announces only the last update at a fresh
`attemptSequence`, `false` is silent launch hydration (touches neither `lastAttempt` nor
`attemptSequence`), empty array is a no-op either way. Added `show(notice:)` as the only
external entry point to `guidance`, which stays `private(set)`. Inverted (not deleted) the one
falsified test, same commit as the arm flip. 9 new tests across PingHistoryTests/PingModelTests.
Gate: `SMOKE_DERIVED_DATA=build/dd-03-07 ./scripts/smoke.sh` exit 0, 138 tests/15 suites (was
129/15), 0 failures. `aQueuedRowFlipsToSentWhenTheDrainReportsIt`'s pass line is in
build/dd-03-07.log; `aRetryableAttemptRecordsAQueuedRowCarryingItsReason`'s console line was
clobbered by concurrent-test carriage-return redraws, confirmed passed via `xcresulttool
get test-results summary` (failedTests: 0, passedTests: 138).
