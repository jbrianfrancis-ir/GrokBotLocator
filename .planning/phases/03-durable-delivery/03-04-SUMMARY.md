<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-04
status: complete
agent: executor/claude/sonnet
commits: [9e656ce, 9441a8f]
deviations: ["[Commit hygiene] Task 2's diff (4 @Test funcs, tests/PingSenderTests.swift:361-429) was staged+scanned, then swept into sibling commit 9441a8f (test(03-01), DevFlow-Plan: 03-01) by a shared-checkout race -- another agent committed between my `add` and `commit`, which then reported nothing staged. Code is correct and tested, just carries 03-01's trailer not 03-04's. Reported to team lead; no history rewrite since 3 commits landed on top of 9441a8f."]
human_checks: []
deferred: []
---
`PingEnqueueOutcome.queued` gained `id: UUID`, minted by the sink; `PingAttempt` gained a
trailing `queuedID: UUID?` via an explicit initialiser defaulted `nil`, so all ~40 call sites
(every preview included) compile untouched. `send(label:)`'s retryable arm copies the sink's id
onto the attempt; every other path (`.sent`, any `.permanentFailure`) carries `queuedID: nil`.
Task 1 also repaired `FakeSink`'s broken `.queued` default, same commit (9e656ce).
Task 2's four tests (pinning all dispositions for whether they carry an id) landed in 9441a8f --
see deviations.
Full-tree smoke re-run after all four sibling plans landed, at HEAD 9fec0d7: green, "123 tests
in 14 suites passed"; log confirms all four new tests by name.
