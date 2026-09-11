<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-02
status: complete
agent: executor/claude/sonnet
commits: [54be48d]
deviations: ["[Verify] Neither task's full <verify> (SMOKE_DERIVED_DATA=build/dd-03-02 ./scripts/smoke.sh) was run to green by this executor -- the whole-project build was failing on sibling plan 03-03's src/Queue/Connectivity.swift (Swift 6 concurrency capture error, mid-edit in this shared checkout) at commit time. Per-plan SMOKE_DERIVED_DATA isolates the build log only, not sources, so this plan's own gate cannot go green until every 03-0x sibling in the wave lands. Team lead is absorbing this at wave fan-in and will re-run this plan's grep/log assertions against that build."]
human_checks: []
deferred: []
---
`PingRetryPolicy` (src/Queue/PingRetryPolicy.swift): pure value type, `.standard`, with
`delay(afterAttempts:)` = `min(30 * 2^(n-1), 3600)` (30...1920 for 1-7, 3600 from 8 on),
`nextAttemptDate(afterAttempts:now:)`, `hasGivenUp(firstAttemptAt:now:)` (7-day horizon,
time-based not count-based), and `gaveUpReason` (finished sentence). No `Date()`/`URLSession`/
`FileManager`/`Task.sleep` -- confirmed by the task's own grep, independent of the build.
Falsify mutation (`let createdAt = Date()`) reproduced the grep hit, then reverted; confirmed
clean afterward.
`PingRetryPolicyTests.swift` pins all 8 delay values (1920 at attempt 7, not 1800), the cap
past attempt 8, non-positive-attempt handling, `nextAttemptDate` arithmetic, the 7-day give-up
boundary (false at +6d23:59:59, true at +7d), and the reason sentence shape -- not build-verified
here; see deviations.
Both `backstop_truths` (non-401/403 4xx permanence; 7-day give-up horizon) are stated as
BACKSTOP in the file's header comment, not resolved -- left open per instruction.
