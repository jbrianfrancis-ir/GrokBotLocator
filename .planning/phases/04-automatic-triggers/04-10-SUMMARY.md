<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-10
status: complete
agent: executor/claude/sonnet
commits: [c95a50a, b2961a9, 30ce7f1]
deviations: ["[Rule 3] Widening PingSending with send(label:using:) broke every other conformer (Settings/PingHomeView preview stubs, SettingsModelTests/PingModelTests/QueueDrainCoordinatorTests/SmokeTests fakes) -- added a minimal send(label:using:) to each in Task 1's commit; none exercise the new method."]
human_checks: []
deferred: []
---
PingSender.send(label:) split into loadCredentials()/deliver(label:fix:credentials:); new
send(label:using:) skips fix acquisition for a caller that already has one. send(label:) keeps
HEAD's ordering (credentials before fix) and calls deliver() directly. AutomaticPinger
(@MainActor) claims from the injected PingRateLimiting (SAME instance GrokBotLocatorApp builds
for PingModel's manual path -- no default on either init, 04-13 must wire it), labels via
TriggerLabelProviding (never model.label), sends via send(label:using:), applies to PingModel
with announcing: false, and returns .rateLimited/.noCredentialsOrFix/.pinged(outcome) so 04-11
knows whether to advance its reference coordinate. UnqueuedPingSink untouched (diff-confirmed) --
the D-14 backstop conflict carries forward unresolved.
Final smoke: 242 tests / 27 suites passed (baseline 233/26 + 9 new).
