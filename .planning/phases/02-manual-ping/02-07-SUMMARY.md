<!-- .planning/phases/02-manual-ping/02-07-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 02-07
status: complete
agent: executor/claude/claude-opus-5
commits: [fa3273a, 859263a, e3d6a10]
deviations: []
human_checks: []
deferred: []
---
Added src/Ping/PingLabelStore.swift (protocol + UserDefaultsPingLabelStore, one key
"ping.label", `@unchecked Sendable` since the SDK doesn't mark UserDefaults Sendable under
strict concurrency — documented thread-safe, so the override is sound) and
src/Ping/PingHistory.swift (PingOutcome: Equatable, PingHistoryEntry, PingHistoryLog:
newest-first insert, capacity 50, in-memory only). tests/PingHistoryTests.swift: 7 cases —
REQ-03's real claim (label outlives the store via a second instance over the same defaults),
empty-defaults/empty-label round-trips, exactly-one-key-written (used persistentDomain(for:),
not dictionaryRepresentation(), which merges ~29 search-list keys and never reads as 1), log
ordering, 55-into-50 capacity drop, and reason-by-outcome. Both grep guards (UserDefaults
single-caller; no FileManager/JSONEncoder/UserDefaults in PingHistory.swift) and all three
falsify steps run live and reverted cleanly. smoke.sh green, 58 tests/10 suites, tree clean.
