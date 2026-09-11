<!-- .planning/phases/04-automatic-triggers/04-08-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-08
status: complete
agent: executor/claude/sonnet
commits: [968967a, a42550c]
deviations:
  - "[Task 3] No separate commit: doc-comment-only, no falsify, already landed in Task 1's file (968967a)."
human_checks:
  - "Device/sim, Always granted, trigger on: after one manual ping, move >150m -> exactly ONE geofence-exit ping; move >150m again -> a SECOND ping (proves re-registration)."
deferred: []
---
GeofenceMonitor.swift: GeofenceMonitoring protocol + actor CLMonitorGeofence (CLMonitor confined
here per smoke's guard). register(at:) always reuses one `conditionIdentifier` -- replaces, never
accumulates, so re-registration cannot leak (tests: registeringTwiceLeavesExactlyOneRegion, 20
concurrent registrations via a genuinely-suspending fake). Exit-only: `.satisfied` fires nothing.
`currentCentre()` reads back via `CLMonitor.record(for:)`, CONFIRMED live against Apple's DocC
JSON 2026-09-11 (`func record(for:) -> CLMonitor.Record?`, `.condition: any CLCondition` cast to
`CircularGeographicCondition`) -- not stubbed to memory-only. No disk write, no UserDefaults key
(queue file stays the one sanctioned coordinate store). InMemoryGeofence (internal) is 04-11's
reusable fake. Radius 150m pinned as backstop. Final smoke: 226 tests / 26 suites, exit 0 (+7/+1
over the 219/25 baseline).
