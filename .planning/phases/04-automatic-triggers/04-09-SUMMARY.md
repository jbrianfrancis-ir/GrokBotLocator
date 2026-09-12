<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-09
status: complete
agent: executor/claude/sonnet
commits: [679d7d6, bee9f32, 1e42e49, a5509d0]
deviations: ["[undeclared files] PingHomeView.swift's preview and tests/SmokeTests.swift + tests/QueueDrainCoordinatorTests.swift each construct a PingModel; dropping rateLimiter/now's defaults (Task 2) broke all three. Fixed with minimal call-site args (a real PingRateLimiter in the preview, tiny always-allowing fakes in the tests), folded into Task 2's commit as a direct consequence of that task."]
human_checks: []
deferred: []
---
PingTrigger (manual/significantChange/arrival/geofenceExit, word+symbolName) added to
PingHistoryEntry/PingDeliveryUpdate (nil-default; queue file and wire format untouched).
PingHistoryLog.apply keeps a row's existing trigger when an update carries none (REQ-07 survives
a delayed drain). PingModel.ping() claims from the injected PingRateLimiting before sending — same
shape as the no-fix branch — and tags manual pings .manual; rateLimiter/now are required init
params, no defaults (LEARNINGS). GrokBotLocatorApp builds the one PingRateLimiter 04-10's
AutomaticPinger must share. PingOutcomeRow draws+speaks the trigger via DS tokens only.
Final smoke: 233 tests / 26 suites passed (baseline 226/26 + 7 new). One PingRateLimiting instance
now gates both PingModel.ping() (manual) and where 04-10 will claim (automatic).
