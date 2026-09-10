<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-08
status: complete
agent: executor/claude/sonnet
commits: [59dff46, 3f89f1a]
deviations: []
human_checks: []
deferred: []
---
`src/Queue/DurablePingSink.swift`: `DurablePingSink: PendingPingSink` (`store`, `policy`,
injected `now`). `enqueue` builds a `QueuedPing` with `attemptsMade: 1` (the live attempt that
just failed counts, so the first retry is a backoff away, not immediate), awaits
`store.append`, and returns `.queued(id:)` only after that returns -- write before promise.
`.full`/`.unreadable`/any other throw each become a distinct `.notQueued` sentence; none
interpolates the caught error, URL, key, or a coordinate. Grep guard (print/NSLog/os_log/
`\(error`/credentials/senderKey/lat/lng) finds nothing.
`tests/DurablePingSinkTests.swift`: 5 tests against a lock-guarded in-memory `FakeQueueStore`
(no real disk) -- entry on "disk" before the id returns, `attemptsMade == 1` with
`nextAttemptAt` matching `PingRetryPolicy.standard`, `.full`/`.unreadable` both refuse with a
>40-char sentence ending in "." containing neither "https" nor "Error", an unexpected
`CocoaError` refuses without naming "CocoaError"/"NSError", and nothing is stored after any
refusal.
Smoke green: 141→146 tests, 15→16 suites; log confirms "Suite DurablePingSinkTests passed".
`UnqueuedPingSink` untouched, still wired -- swap happens at 03-10.
