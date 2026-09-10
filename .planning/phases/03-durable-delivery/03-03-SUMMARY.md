<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-03
status: complete
agent: executor/claude/sonnet
commits: [614154b, fc4ddf1, 9fec0d7]
deviations: ["[Task 1] Plan said to lock-guard ConnectivityEdge as a captured var; that does not compile under Swift 6 strict concurrency (`Mutation of captured var 'edge' in concurrently-executing code`). Boxed the var+NSLock in a private lock-boxed class captured as a `let` instead, matching the repo's existing NSLock-boxed-class pattern.", "[Task 1] Replaced that private @unchecked Sendable box with Synchronization.Mutex<ConnectivityEdge> (9fec0d7) -- genuinely Sendable. smoke.sh green, Suite ConnectivityEdgeTests passed, one `import Network` hit after."]
human_checks: []
deferred: []
---
`ConnectivityEdge` (src/Queue/Connectivity.swift): pure value type; `observe(satisfied:)`
fires only `false -> true`, every other transition returns false. `ConnectivityObserving`
yields `AsyncStream<Void>` rising edges. `NWPathMonitorConnectivity` is the sole
`import Network` site (grep-confirmed); edge state guarded by `Mutex<ConnectivityEdge>`,
not a captured `var` (see deviations).
`ConnectivityTests.swift`: all four transitions + cold-start, no network; compile-only check
for the wrapper. Falsified both tasks -- reproduced, reverted, byte-identical after.
`smoke.sh` fully green at both 614154b/fc4ddf1 and again after 9fec0d7.
