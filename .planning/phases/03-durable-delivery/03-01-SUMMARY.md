<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-01
status: complete
agent: executor/claude/sonnet
commits: [c101fcc, 9441a8f]
deviations: ["[Rule 1] PingPayloadTests.encodesExactlyTheFourKeysWithTheRightTypes asserted the old four-key Set; once Task 1's encoded() emits `at` that assertion is simply wrong, so its Set literal was widened to five keys inside Task 1's own commit (c101fcc) rather than leaving Task 1's gate red until Task 2. Task 2 then did the full rename/value-assertion work per plan.", "[Commit hygiene] Task 2's `git add` (9441a8f) landed in a shared-checkout window where another agent's staged-but-uncommitted tests/PingSenderTests.swift (03-04, plan-04) was also in the index; my commit briefly included it. I reverted that content in a follow-up commit (25e5e08) before discovering 03-04's own SUMMARY had already investigated the identical sweep, judged the code correct, and deliberately left it in 9441a8f rather than rewrite shared history (3 commits had already landed on top). Reverted my own correction (b27874b) to restore 03-04's content; no other file touched."]
human_checks: []
deferred: []
---
`PingPayload` gained `capturedAt: Date` (last stored property, `"at"` last in CodingKeys and the
composed wire literal); `LocationFix.payload(label:)` is the only bridge, passing its own
`timestamp`. All eight literal `PingPayload(...)` call sites repaired in the same commit as the
type change (c101fcc). Task 2 (9441a8f) renamed the four-key test to
`encodesExactlyTheFiveKeysWithTheRightTypes` with the pinned `"2023-11-14T22:13:20Z"` literal,
extended key-order and added `atCarriesTheFixTimeNotTheEncodeTime` (fails if `encoded()` ever
reaches for `Date()`), and pinned `LocationFix`'s bridge with a named
`capturedAt == timestamp` assertion. Both tasks' falsify mutations reproduced the predicted
failure against file-scoped `grep`/the named test, then reverted — confirmed clean via
`git diff -- <task files>` before each commit.
Final `SMOKE_DERIVED_DATA=build/dd-03-01 ./scripts/smoke.sh`: exit 0, TEST SUCCEEDED, 123
tests/14 suites (post-revert of the commit-hygiene fix; reflects all sibling plans' code present
at that point, not just 03-01's).
