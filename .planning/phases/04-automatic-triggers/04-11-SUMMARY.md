<!-- .planning/phases/04-automatic-triggers/04-11-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-11
status: complete
agent: executor/claude/sonnet
commits: [0399e61, 8b71de5, 9267e3a, 3fc108f]
deviations: ["[smoke-green per commit] Task 1 stubbed the 3 handlers (no-op bodies) so start() compiled before Task 2's real logic; Task 2 replaced the stubs, no plan behaviour change."]
human_checks: ["REQ-06: 500 m GPX pings once, 300 m pings none, backgrounded", "REQ-07: backgrounded visit arrival pings once as Arrival", "REQ-05 4th drain: airplane mode, queue a ping, background, location wake, confirm silent drain", "SC-03: full day all triggers on, Battery share under 5%"]
deferred: []
---
`TriggerCoordinator` (actor) arms significant-change/visits/geofence from settings, requesting
Always only when enabled and not authorized (REQ-10). Every callback drains FIRST, unconditionally
— proven by an ordering script + test, falsified by moving `handleVisit`'s drain below its guard
(both fail). `serialized(_:)` chains each handler onto a `Task` reassigned pre-suspension, so the
reference read-modify-write never interleaves across concurrent wakes — proven with real
`Task.yield()`-suspending fakes. `settled()`/`currentReference()` give tests a completion signal
and read window. 9 new tests; smoke 251/28 suites green (was 242/27). `git status` clean.
