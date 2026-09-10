<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-06
status: complete
agent: executor/claude/sonnet
commits: [11b0907, c51e55f, d9a4688]
deviations: []
human_checks: []
deferred: []
---
`src/Queue/PingQueueStore.swift`: `QueuedPing`, `PingQueueError {unreadable, full}`,
`PingQueueStoring` (load/append/replace), `FilePingQueueStore` -- the D-12 queue file, an actor
over `PingQueue.json` in Application Support. Every write reasserts
`.completeFileProtectionUnlessOpen` AND `isExcludedFromBackup` (atomic replace doesn't inherit
prior resource values). `append` refuses at capacity 200, never evicts; an undecodable file
moves to `PingQueue-unreadable.json` (replacing any prior, never deleted), reports once via
`.unreadable`. No print/log/`.encoded()` in the file (grep-confirmed).
`tests/PingQueueStoreTests.swift`: 6 tests on real files under a throwaway temp dir --
cross-instance durability, backup exclusion, `replace` dropping a delivered id, full-queue
refusal (oldest survives), unreadable set-aside + clean restart, `permanentFailure` round-trip.
Backstop truth (open by design): a ping that fails permanently WHILE QUEUED stays on disk with
its reason until shown, then removed. REQUIREMENTS.md doesn't settle whether this must survive
an app-not-running failure; this store assumes it must.
Smoke green at all 3 commits: 123→123→129 tests, 14→14→15 suites; log confirms
"Suite PingQueueStoreTests passed".
