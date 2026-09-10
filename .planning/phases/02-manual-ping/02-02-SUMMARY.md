---
plan: 02-02
status: complete
agent: executor/claude/claude-opus-5-1m
commits: [8674902, c221b1c]
deviations: []
human_checks: []
deferred: []
---
PingPayload (src/Core/Ping/PingPayload.swift) + 6 tests (tests/PingPayloadTests.swift).
encoded() hand-composes `{"lat":...,"lng":...,"accuracy_m":...,"label":...}` in that exact
order; label escaping goes through JSONEncoder().encode([label]) (array, defined order),
outer brackets dropped — no hand-rolled replacingOccurrences/sortedKeys/prettyPrinted (grep
gate confirmed). Non-finite lat/lng/accuracy throws PingPayloadError.nonFiniteValue.
Falsify-checked: swapping in JSONEncoder().encode(self) fails the order + byte-stability
tests exactly as the plan predicted, then reverted cleanly (smoke re-ran green after).
Smoke: 31 tests / 6 suites, exit 0, `** TEST SUCCEEDED **`. Secret-scanned staged diff, no
hits. PingPayload.encoded() is now the only place turning a fix into wire bytes — ready for
02-04's transport layer to consume.
