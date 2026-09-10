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
- `URLRequest.timeoutInterval` is an IDLE timeout, not a total one: a drip-feeding endpoint held
  a request 64.1s against a 10s setting (measured). The API that bounds total elapsed time is
  `timeoutIntervalForResource`, and it CANNOT be set on `URLSession.shared` — a shared session's
  configuration is a read-only copy, which is the structural reason the defect exists. Fix at the
  composition root with a constructed session, bound ABOVE SC-01's 10s (or legitimate slow
  roaming sends start failing), and drop `= .shared` as `init`'s default so a later call site
  cannot reacquire the defect by omission. It surfaces as `URLError.timedOut`, which the
  classifier already turns into a retryable sentence, so "no ping silently dropped" still holds.
- An unbounded response body is a SEPARATE defect from the timeout with the same symptom: a fast
  100MB response satisfies any duration bound and still OOM-kills the app. Needs a byte budget
  (`expectedContentLength` or `session.bytes(for:)`) plus truncation before `String(decoding:)`
  and before rendering — and REQ-11 renders the body verbatim, so the view is in scope too.
- A guard written as a grep needs its own negative test. Four holes shipped in this repo's guards
  despite the rules being right: a line-level filter could be escaped on that line, `@AppStorage`
  never says "UserDefaults", `CLBackgroundActivitySession` never says "CLLocationManager", and an
  anchored `.font(` pattern misses `.system(size:)` on the next line. A guard with no probe only
  proves nobody has yet written the string it happens to match.
- Parallel executors sharing one checkout must stage by explicit path. `git add -A`/`-a` takes
  whatever a sibling left staged: in phase 03 wave 2 it happened three times — 03-01's commit
  swept 03-04's staged tests, 03-01 then nearly destroyed them "fixing" it (reverted in time),
  and 03-01's own SUMMARY landed under a 03-04 commit. Code stayed correct; attribution did not.
  Never rewrite shared history to repair this — document it and move on.
- Per-plan `SMOKE_DERIVED_DATA` isolates the build LOG, not the SOURCES. Every plan's gate is a
  whole-project build, so within a wave it compiles every sibling's in-flight edits and a plan
  cannot observe its own gate green until the whole wave lands. The wave gate belongs to the
  orchestrator at fan-in. Phase 02 never hit this: 13 plans, 13 waves.
- Waiting for a file to stop changing is not a completion signal — the same trap hosts.md records
  for phase directories. An executor watched a sibling's mtime for "stable" and would have waited
  forever; the sibling was mid-edit.
- Swift 6 strict concurrency rejects an escaping closure mutating a captured local `var`
  ("Mutation of captured var ... in concurrently-executing code") even when a lock serializes it.
  Prefer `Synchronization.Mutex<T>`, which is genuinely `Sendable` and lets the compiler prove
  `withLock` safe, over an `NSLock` + `@unchecked Sendable` box, which only asserts it.
