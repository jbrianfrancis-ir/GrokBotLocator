<!-- .planning/LEARNINGS.md — cap 20 bullets; consolidate oldest when over. -->
# Learnings

- `JSONEncoder` does not serialize in `CodingKeys` or declaration order — key order is
  non-deterministic per process (proven over six runs on the iOS 26 simulator runtime). Any
  claim about wire key order needs bytes composed by hand; `.sortedKeys` yields
  `accuracy_m, label, lat, lng`, not ARCHITECTURE's order.
- `PingSending.send` is a nonisolated `async` requirement, so a fake runs OFF a `@MainActor`
  suite. Lock-guard its counters and latch the continuation release, or the suite hangs —
  `aSecondPingWhileOneIsInFlightIsIgnored` hung 2 runs in 5 until 865a8ba.
- A verify that greps an existing file for an absence passes at HEAD, before any code is
  written. Four of phase 02's verifies had this shape and were rewritten to assert the new
  test names or symbols in the runner log instead.
- Whole-file presence greps count comment text: doc comments naming `dsChrome` pushed a
  `grep -c` from 1 to 5, and a comment containing `CLLocationManager` failed the location
  guard outright.
- A guard that filters whole lines can be escaped on that line. smoke.sh's UserDefaults guard
  dropped any line mentioning `UserDefaultsPingLabelStore`, so a real `UserDefaults` call
  beside it passed clean (the verifier probed it). Strip the allowed token, then match.
- Retryable sends record `.failed` with a reason, never `.queued`: `PendingPingSink` is wired
  and tested but drains nothing. Phase 03 swaps the sink AND flips that arm in
  `PingModel.ping()`.
- Subagent self-reports are not evidence. Two phase-02 executors reported commit SHAs absent
  from `git log` and a SUMMARY not on disk; `git cat-file -t` and `ls` settled both. Verify
  against the repo before acting on a number.
