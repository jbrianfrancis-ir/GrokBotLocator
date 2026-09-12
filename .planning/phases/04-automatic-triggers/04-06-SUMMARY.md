---
plan: 04-06
status: complete
agent: executor/claude/sonnet
commits: [5168ab3, c7e3774, 45430db]
deviations: ["[Rule 4] Task 2's falsify literal `triggers.lastLatitude` (capital L) does not trip the case-sensitive absence grep for `latitude`; re-ran with matching case (`triggers.lastlatitude`) to confirm the check has teeth (exit 0), then reverted. No code change; the real store has no such literal either way."]
human_checks: []
deferred: []
---
Added `TriggerSettings` (three switches + clamped interval, `.initial` all-off at
`PingRateLimiter.defaultInterval`) and `UserDefaultsTriggerSettingsStore` (its
`TriggerSettingsStoring` conformer, smoke.sh's second UserDefaults exemption). The floor is
enforced in exactly one place — `TriggerSettings.init`/`setMinimumInterval`, both routing through
`PingRateLimiter.hardFloor` — so `load()` clamps on read (object(forKey:) as? Double distinguishes
absent-key from a genuine 0.0) and `setMinimumInterval` clamps on write; a hand-edited store below
the floor round-trips back at the floor either way. Confirmed by falsifying the init's clamp: only
`anIntervalHandEditedBelowTheFloorIsClampedOnRead` failed. Final smoke: 212 tests in 24 suites
(205/23 baseline + 7 new tests, 1 new suite), exit 0.
