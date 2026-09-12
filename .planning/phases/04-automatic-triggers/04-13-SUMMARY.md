<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-13
status: complete            # complete | partial | blocked
agent: executor/claude/sonnet    # role/provider/model that executed this plan — matches the commit trailers
commits: [b51c0fa, 7cf3d87, 1a67696]                 # short SHAs, one per task
deviations: []              # "[Rule N] description" per entry
human_checks: ["REQ-05 fourth-drain end-to-end on a device: airplane mode on, tap I'm here, background, airplane mode off, drive a location wake — confirm no announcement while backgrounded and history row reads Sent on reopen"]
deferred: []                # out-of-scope issues found, not fixed
---
Composition root now wires phase 04 end to end: one `PingRateLimiter` shared by `PingModel`
and `AutomaticPinger`; `LocationDelegateProxy`, `CLMonitorGeofence`, `UserDefaultsTriggerSettingsStore`,
the shipping `MapKitTriggerLabelProvider` (D-15) and one `TriggerCoordinator`, handed to
`SettingsModel` as its `TriggerControlling`. `TriggerCoordinator.start()` runs from the root
view's `.task`, after the queue drain; scene phase sets presence (`.active` true, `.background`/
`.inactive` false) so a location wake drains silently. No `import MapKit` in this file. Smoke:
257 tests, 28 suites, green after every task.
