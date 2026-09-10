---
plan: 02-10
status: complete
agent: executor/claude/claude-opus-5[1m]
commits: [e56842a, 4e92cd3]
deviations: ["[Rule 1] FakeSender is an actor, not the plan's counting class: PingSending.send is async, so a non-isolated fake runs off the main actor and its counters race this @MainActor suite. waitUntilEntered() replaces polling."]
human_checks: []
deferred: ["tests/PingModelTests.swift aSecondPingWhileOneIsInFlightIsIgnored hangs intermittently (2 of 5 runs): release() can read the fake's continuation before send() assigns it, so nothing resumes and the serial run stalls. Pre-existing (02-09), out of this plan's files, not fixed."]
---

SettingsModel: `sender: PingSending? = nil` as a second init param (default keeps existing
call sites compiling), nested `ConnectionReport`, `connectionReport`, `isTesting`,
`testConnection()`. Status and body pass through verbatim -- no trim, no placeholder, empty
stays "", nil stays nil. `.sent` gives a success headline; both failure arms use the classifier's
sentence, so a 401 headline names 401. No sender gives a visible unavailable report. `status`
untouched, nothing logged, no history row. 02-11 renders it.

Measured: smoke.sh exit 0, `** TEST SUCCEEDED **`, "Test run with 84 tests in 12 suites passed"
(baseline 77/12), "Suite SettingsModelTests passed", all seven new case names passed in the log.
Falsifies run and reverted: `prefix(100)` made the grep exit 0; `status = .saved` on success
failed `testConnectionLeavesSaveStatusAlone` and its suite, both as predicted.
