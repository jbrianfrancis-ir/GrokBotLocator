<!-- .planning/LEARNINGS.md — cap 20 bullets; consolidate oldest when over. -->
# Learnings

- A grep guard is a net, not a proof, and every change to one needs an ESCAPE probe — a plausible
  violation added in a NEW place — not a deletion probe. Five holes have shipped here despite the
  rules being right: a whole-line filter escaped on that same line, `@AppStorage` never saying
  "UserDefaults", `CLBackgroundActivitySession` never saying `CLLocationManager`, an anchored
  `.font(` missing `.system(size:)` on the next line, and a multiline `data.write(`. Phase 04
  added the fix: exclude a permitted file by anchoring on grep's own `^path:lineno:` prefix, which
  no line's CONTENT can forge — never by filtering lines that merely mention the filename. Its 13
  probes caught the plan's own comment-strip reintroducing the same-line hole; keep both must-FAIL
  and must-PASS probes, since a guard that rejects everything also "passes" every failure probe.
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
- Parallel executors in ONE checkout cannot commit safely, and explicit-path staging does not
  save them: the git *index* is shared, so `git commit` takes a sibling's already-staged files
  no matter how careful your own `git add` was. Phase 03 wave 2 hit this 4x — 03-01 staged two
  named test files and still swept 03-04's; 03-01 then nearly destroyed that work "fixing" it
  (caught by reading 03-04's SUMMARY first); later a SUMMARY rode under the wrong plan's commit,
  twice. Code stayed correct every time; only attribution crossed. Never rewrite shared history
  to repair it — 3 commits were already on top. The real fix is one worktree per parallel plan
  (`/flow-workstream`), not commit hygiene. Until then, expect crossed trailers in any wave >1
  plan and reconcile from SUMMARY frontmatter (`plan:`), which is authoritative, not from
  commit messages, which are not.
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
- `drainBackground()` applies updates with `announcing: true`, so a background-wake outcome sets
  `lastAttempt` and can announce a result for a tap the user never made. No phase-03 truth forbids
  it — only launch hydration is required to be silent — but phase 04's location wake lands on that
  same coordinator, so decide it there rather than discovering it on a device.
- A test that pins an implemented choice is not the same as a rule. All three of phase 03's
  backstop truths HAVE tests; they stop drift, they do not settle whether the choice is right.
  An abstention is lifted by a human stating the rule, never by a green test.
- An actor serializes entry, not a call: it is reentrant at every `await`. `PingQueueDrain` had
  THREE read-modify-write holes of that shape — drain-vs-drain (delivered twice), drain-vs-enqueue
  (a ping queued mid-drain erased while its row read Queued), and a swallowed delta write
  (delivered pings never removed, re-POSTed next drain). Each was invisible to a suite where every
  test drives one caller against a fake that never suspends. A fake that returns instantly cannot
  test an actor; give it a real suspension.
- Fixing one failure can make another reachable. Splitting a read error out of a decode error
  (correct, it stopped a locked device destroying the queue) turned the drain's `try?` from a
  hypothetical into an ordinary path. Re-run the lens that owns the neighbouring code after a
  fix, not only the lens that reported it.
- A bound that depends on a vendor API honouring `cancel()` is not a bound. `MKReverseGeocodingRequest.mapItems`
  did NOT resume on `cancel()` with no service reachable: `withTaskGroup` awaits every child, so the
  abandoned fetch hung the caller forever (leaked continuation) — found by a real 18-minute hang, not by
  review, after a plan-checker had passed the construction. The shape that works is an unstructured,
  never-awaited task plus a `Mutex`-guarded one-shot continuation: bounded BY CONSTRUCTION. Copy that
  for any "race X against a timeout", never `withTaskGroup`.
- Persisting a setting, displaying it, and enforcing it are three separate wirings. Phase 04 did the
  first two for REQ-09's minimum interval and missed the third: the value was clamped, stored and drawn
  on screen while `PingRateLimiter.setMinimumInterval` had zero callers, so the gate kept its default
  for the process life. 257 tests were green over it because the requirement's literal acceptance clause
  still passed. When a value is stored in one type and enforced in another, a plan must NAME the call
  that carries it across, and the test must assert the ENFORCER's behaviour, not the stored value —
  every fake limiter in the suite returned `.allowed`, so only the real actor could have caught it.
- Serialized execution fixes the crossed-attribution defect that parallel waves cause. Phase 03 crossed
  authorship 4x in one wave because executors share a git INDEX even when `files_modified` are disjoint;
  phase 04 ran all 14 plans one at a time and every `DevFlow-Plan` trailer matches its own plan's commits,
  zero crossings. The cost is wall-clock only.
- A durable grant and the live session that makes it effective are two different lifetimes, and one
  condition cannot gate both. REQ-08 never fired because `CLServiceSession` creation lived inside
  `requestAlways()` behind `!= .authorizedAlways`: a cold relaunch of an already-granted app had
  nothing to request, so it held no session either, and Always was inert for the whole process. The
  suite could not see it — every fake source defaulted to `.authorizedWhenInUse`, so the skipped
  branch was never once executed by 267 green tests. When a default in a test fake decides which
  branch runs, the other branch is untested: give the fake a PARAMETER for the state that is normal
  in production (already authorized, already migrated, already cached) and drive both.
