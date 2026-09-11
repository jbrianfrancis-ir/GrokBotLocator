<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-09
status: complete
agent: executor/claude/sonnet
commits: [9f4b559, 5fa4ba7]
deviations: []
human_checks: []
deferred: []
---
`src/Queue/PingQueueDrain.swift`: `PingDrainReport` + `actor PingQueueDrain`.
`drain(before:surfacingFailures:)` walks oldest first: 2xx deletes and reports `.sent` (D-12);
retryable backs off with no report; permanent/give-up marks `permanentFailure`, reports
`.failed`, drops only when `surfacingFailures` (background-wake-then-foreground path).
Missing/unreadable credentials and an unreadable queue both drain and delete nothing.
`store.replace` after every entry, not once at the end. Deadline stop leaves the rest
untouched. Grep guard clean.
`tests/PingQueueDrainTests.swift`: 9 tests, lock-guarded fakes, no network/disk. Covers every
disposition, non-surfacing-then-surfacing (same store, transport not re-invoked second time),
7-day give-up, both drain-nothing conditions, deadline mid-queue (`Mutex`-boxed stepping
clock, not a captured `var`, per LEARNINGS.md), per-entry rewrite (2,1,0).
Smoke green: 146→155 tests, 16→17 suites; log confirms "Suite PingQueueDrainTests passed".
Hand-falsified both task guards (Date() swap; single end-of-loop replace) -- both caught,
reverted clean.
Wires nothing into the app -- 03-10 connects `QueueDrainCoordinator` to `PingModel`.
