---
plan: 02-13
status: partial
agent: executor/claude/claude-opus-5[1m]
commits: [dbf260c]
deviations:
  - "[Rule 3] RootView's new signature broke tests/SmokeTests.swift — rewritten with 3 fakes."
  - "[Rule 3] .navigationBarTitleDisplayMode(.inline) moved to the pushed SettingsView; PingHomeView hides its bar."
human_checks:
  - "T2: PingButton in-flight; PingOutcomeRow AX5 light+dark; .dsChrome() Reduce-Transparency + increase_contrast."
  - "T3: REQ-02/03/04/10 + SC-01 on a real endpoint — 4-key body in key order, 401, force-quit, Never, VO."
  - "T4: Accessibility Inspector AX5 light+dark on PingHomeView AND SettingsView; verdict per screen+appearance. actionLabel>screenTitle at AX5 is ACCEPTED (15:30), never file it."
  - "Scripts: 02-13-PLAN tasks 2-4. Sim E188EA3E has dbf260c installed, AX5+light."
deferred:
  - "PingLabelStore.swift claims smoke.sh guards a 2nd UserDefaults caller; it has no such grep."
---
GrokBotLocatorApp's explicit init() builds store/fixes/sender as locals and assigns both models
via `_x = State(wrappedValue:)`, so Test connection and the ping button share one PingSender.
Each of the five constructors greps to 1 there and 0 in every other src file; the falsify
mutation named a second file, then reverted clean. RootView opens on PingHomeView with
SettingsView behind SettingsRoute, no navigationTitle. smoke.sh exit 0, 84 tests in 12 suites.
On-simulator: opens on the ping screen, gear pushes Settings, Back returns.
Tasks 2-4 are on-screen checks nobody has run — none passed.
