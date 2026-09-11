<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-12
status: complete
agent: executor/claude/sonnet
commits: [5218fe3, b387185, e3228ac, eec71b6]
deviations: ["[Task 1] `triggers` init param given a `nil` default (plan said WITHOUT one) so the ~21 existing bare `SettingsModel(store: fake)` call sites in tests/SettingsModelTests.swift, which the plan itself required left unchanged (no helper exists to intercept them), keep compiling — mirrors `sender`'s existing optional-with-default shape."]
human_checks: ["AX5 reflow of the three toggles, the interval Stepper and the notice — no truncation/clipping/overlap, all still tappable (device/simulator + Accessibility Inspector)", "With all triggers off, no Always prompt; enabling one raises it; choosing While Using shows the sentence and the I'm here button still sends"]
deferred: []
---
Adds `TriggerControlling` + retroactive `TriggerCoordinator` conformance,
`SettingsModel.triggerSettings`/`triggerNotice`/`loadTriggers()`/`setSignificantChange(_:)`/
`setVisits(_:)`/`setGeofence(_:)`/`setMinimumInterval(_:)`, and a Settings "Automatic pings"
section (3 toggles + Stepper + notice, all DS-token, all ≥60pt, 6 `DSMetrics.minTapTarget`
uses). Floor is expressed only via `PingRateLimiter.hardFloor...300` in the Stepper's range —
no literal 15/60 introduced anywhere in this plan's files. 6 new `SettingsModelTests` (actor
`FakeTriggerControl`); no existing test changed. Smoke: 257 tests/28 suites (was 251/26 at
phase start per STATE.md, 251/28 after 04-11), exit 0, `git status` clean.
