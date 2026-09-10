<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-10
status: complete
agent: executor/claude/sonnet
commits: [9c87127]
deviations: ["[Task 2] launchHydratesTheHistoryFromTheQueueFile split into two tests -- see below"]
human_checks: []
deferred: []
---
`src/App/QueueDrainCoordinator.swift`: `@MainActor final class`, four triggers behind one
`hasHydrated` flag + one `connectivityTask`. `hydrate()` maps `QueuedPing` -> `PingDeliveryUpdate`
(`.failed`+its reason, or `.queued`+standing sentence), takes the trailing `PingHistoryLog.capacity`
slice (oldest-first, so `record`'s insert-at-front lands newest-first), `apply(announcing: false)`.
`drainForeground`/`drainBackground` differ only in `surfacingFailures` and budget (25s/20s);
both apply `announcing: true` and route a notice through `show(notice:)`. Connectivity edges
call `drainForeground()` via one `[weak self]` Task. Grep guard clean (verified + hand-falsified:
a `Date()` swap trips it, reverted).

`tests/QueueDrainCoordinatorTests.swift`: 7 tests. Found and worked around a real interaction:
`PingQueueDrain.drain` reports a `permanentFailure` entry on EVERY call regardless of due date
(pinned 03-09 behavior), so a drain immediately following hydration in the same `start()` call
DOES re-surface and announce an already-marked failure -- correct (first real disclosure), but
incompatible with one combined test asserting both "3 rows" and "`lastAttempt` nil". Split into
`launchHydratesTheHistoryFromTheQueueFile` (2 pending only, asserts `lastAttempt` nil, as
directed) and `launchHydratesAPermanentFailureSilentlyBeforeItIsSurfaced` (asserts it IS
announced, once, by the drain that follows). Also hand-verified: `hasHydrated` guard removed ->
`hydrationRunsOnlyOnce` fails, `Suite QueueDrainCoordinatorTests failed`; reverted.

Smoke green: 155->162 tests, 17->18 suites; log confirms "Suite QueueDrainCoordinatorTests passed".
Wires nothing into the app yet -- a later plan in this phase constructs this at the composition
root and adds `BGAppRefreshTask` registration.
