---
plan: 03-12
status: complete
agent: executor/claude/sonnet
commits: [08d0cc4, a218ad0]
deviations: []
human_checks: ["REQ-05/SC-02 on-device steps (Task 3): airplane-mode queue+resume, force-quit relaunch delivery with correct `at`, forced permanent rejection, REQ-04 two-outcome check — batched for a human, not attempted here"]
deferred: []
---
GrokBotLocatorApp now builds `FilePingQueueStore.applicationSupport()` once, sharing it between
`DurablePingSink` and `PingQueueDrain`, and shares one bounded `URLSessionPingTransport` between
the sender and the drain. `QueueDrainCoordinator` drains at launch, foreground return, and a
connectivity edge; `.backgroundTask(.appRefresh(QueueDrainTask.identifier))` drains without
surfacing. `QueueDrainTask.request(identifier:from:)` returns nil for an empty identifier
(tested). Application Support unavailable falls back to `UnqueuedPingSink`, no false "Queued".
Three smoke guards added (queue-store confinement, queue-protection presence, built-plist
background identifier) — all three live-probed to fail on a real mutation, then reverted.
Smoke green at 164 tests / 19 suites; tree clean, only declared files staged/committed.
