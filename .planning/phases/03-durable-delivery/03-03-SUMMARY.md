<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-03
status: complete
agent: executor/claude/sonnet
commits: [614154b, fc4ddf1, 9fec0d7]
deviations: ["[Review] Team lead flagged the first fix (NSLock + private @unchecked Sendable box) as silencing the captured-var diagnostic, not answering it. Replaced with Mutex<ConnectivityEdge> (genuinely Sendable) in 9fec0d7. Verified only by isolated `swiftc -typecheck -strict-concurrency=complete` on this file (clean) -- no whole-project rerun, per instruction not to build the whole tree mid-wave; lead reruns the wave gate at fan-in."]
human_checks: []
deferred: []
---
`ConnectivityEdge` (src/Queue/Connectivity.swift): pure value type, `lastSatisfied: Bool?`
starting `nil`; `observe(satisfied:)` fires only `false -> true`, every other transition
returns false. `ConnectivityObserving` yields `AsyncStream<Void>` rising edges.
`NWPathMonitorConnectivity` is the sole `import Network` site (grep-confirmed); edge state is
guarded by `Synchronization.Mutex<ConnectivityEdge>`, not a captured `var` -- Swift 6 strict
concurrency refuses that mutation from `pathUpdateHandler` (see deviations).
`ConnectivityTests.swift`: all four transitions + cold-start, no network; compile-only check
for the wrapper. Falsified both tasks -- reproduced, reverted, confirmed byte-identical.
`smoke.sh` went fully green once at 614154b/fc4ddf1; the Mutex fix (9fec0d7) is typecheck-only.
