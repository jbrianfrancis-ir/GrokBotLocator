---
plan: 04-05
status: complete
agent: executor/claude/sonnet
commits: [f5fde41, bc2ab35]
deviations: []
human_checks: []
deferred: []
---
Added explicit `userIsPresent` (default `false`) to `QueueDrainCoordinator`, set true as the
first statement in `start()`, and a new `setUserPresent(_:)` for 04-13's scene-phase handler.
`drainForeground()` now passes `announcing: userIsPresent` instead of an unconditional `true`,
so a location wake landing while nobody is looking no longer announces. `drainBackground()`
untouched. Four new tests prove both directions and that presence is read per-drain, not
latched. `hydrate()` and `.planning/ARCHITECTURE.md` were not touched, per the plan's
do-not-touch — the hydrate()-vs-D-12 backstop truth remains open for a human ruling.
