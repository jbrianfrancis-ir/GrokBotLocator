<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 03-01
status: complete
agent: executor/claude/sonnet
commits: [c101fcc, 9441a8f]
deviations: ["[Rule 1] Old four-key Set assertion is wrong once encoded() emits `at`; widened to five keys in Task 1's own commit (c101fcc) rather than leave that gate red until Task 2.", "[Commit hygiene] 9441a8f spans two plans: explicit-path `git add tests/PingPayloadTests.swift tests/LocationAuthorizationTests.swift` (not -A/-a) still picked up 03-04's staged tests/PingSenderTests.swift, already in the shared index before my add ran. I reverted it (25e5e08), then found 03-04's SUMMARY had already judged it correct and deliberately kept it in 9441a8f (3 commits already on top); reverted my revert (b27874b) to restore it. That file is not in 03-01's files_modified."]
human_checks: []
deferred: []
---
`PingPayload` gained `capturedAt: Date` (last stored prop, `"at"` last in CodingKeys and the wire
literal); `LocationFix.payload(label:)` bridges its own `timestamp`, the only source. All 8
literal call sites repaired in the type-change commit (c101fcc). Task 2 (9441a8f) renamed to
`encodesExactlyTheFiveKeysWithTheRightTypes` with the pinned `"2023-11-14T22:13:20Z"` literal,
extended key-order, added `atCarriesTheFixTimeNotTheEncodeTime`, and pinned the
`capturedAt == timestamp` bridge by name. Both falsify mutations reproduced the predicted failure
then reverted clean (`git diff -- <task files>` checked before each commit).
Whole-project smoke observed green once at HEAD b27874b (+ an uncommitted, not-mine sibling edit
to src/Queue/Connectivity.swift in the tree): exit 0, 123 tests/14 suites,
`atCarriesTheFixTimeNotTheEncodeTime() passed` in the log. Not re-verified since — team lead owns
the wave-level gate at fan-in.
