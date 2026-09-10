<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-03
status: complete
agent: executor/claude/sonnet
commits: [614154b, fc4ddf1]
deviations: []
human_checks: []
deferred: []
---
`ConnectivityEdge` (src/Queue/Connectivity.swift): pure value type, `lastSatisfied: Bool?`
starting `nil`, `observe(satisfied:)` fires only `false -> true`; `nil -> *` and any other
transition return false. `ConnectivityObserving` yields `AsyncStream<Void>` rising edges.
`NWPathMonitorConnectivity` is the sole `import Network` site (grep-confirmed); its mutable
edge state lives in a private `LockedEdge` (`NSLock`-guarded `@unchecked Sendable` box) rather
than a captured `var` — Swift 6 strict concurrency refuses a `var` mutated from
`pathUpdateHandler` (same shape as the LEARNINGS.md nonisolated-fake hang); fixed by boxing,
not by dropping the lock.
`ConnectivityTests.swift`: all four transitions + cold-start pinned with no network; a
compile-and-construct-only protocol check for the wrapper, no awaited stream. Falsified both
tasks (rogue `import Network`; `observe` returning true whenever satisfied) — both reproduced
the documented failure, both reverted, confirmed byte-identical.
`smoke.sh` (SMOKE_DERIVED_DATA=build/dd-03-03) went green at commit time (retried after
sibling 03-01's in-flight PingPayload edit in this shared checkout settled).
