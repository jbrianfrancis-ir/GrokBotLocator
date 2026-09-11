---
plan: 04-03
status: complete
agent: executor/claude/sonnet
commits: [9d9b106, 0f5cacd]
deviations: ["[Task 2] The plan's metres/111_320-degrees latitude approximation is off by ~1.2 m at 500 m (measured), enough to fail the exact-500 m case against the >= threshold. Replaced it with a 60-iteration bisection on DisplacementGate.distanceMetres itself, converging to sub-micrometre error, still deterministic and clock-free."]
human_checks: []
deferred: []
---
`DisplacementGate` (src/Triggers/DisplacementGate.swift) is a pure, static type enforcing
REQ-06's fixed 500 m threshold in app code, independent of the OS significant-change callback.
`TriggerCoordinate` bridges `LocationFix` into a `Sendable, Equatable` pair `CLLocationCoordinate2D`
doesn't offer. No reference coordinate -> `shouldPing` true (backstop). `DisplacementGateTests`
(tests/DisplacementGateTests.swift) proves 300 m silent, 500 m exact pings, 1000 m pings,
stationary silent, no-reference pings, threshold == 500, and distance symmetry -- no sleeps, no
clock reads, no device. `04-11`'s TriggerCoordinator is the intended caller.
