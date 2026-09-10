---
plan: 01-04
status: complete
agent: executor/claude/sonnet
commits: [ef79943, cb78bc7]
deviations: []
human_checks: []
deferred: []
---
scripts/smoke.sh: checks Signing.xcconfig exists (else names it, exit 1), runs the repo-wide
type-scale guard, `xcodegen generate`, resolves UDID via simulator-udid.sh (propagating its
failure/message, never falling back), `xcodebuild test` tee'd to `${SMOKE_DERIVED_DATA:-build/dd-smoke}.log`,
passes only on `** TEST SUCCEEDED **` AND `Test run with [1-9]... test` (Swift Testing count,
not XCTest's always-0 line). Never passes CODE_SIGNING_ALLOWED=NO. Guard greps src/ (excluding
DSTypography.swift) for `size:` literals under 17 or any raw `.font(.system(size:` call,
regardless of `let`/`var`/no declaration at all -- the pattern doesn't key on the keyword, so
it already covers the `static var` gap noted for this plan. Verified live: clean pass (exit 0,
3 tests); Signing.xcconfig renamed away -> exit 1 naming it, restored; SIMULATOR_NAME=NoSuchDevice
-> exit 1; temp file with `static let f = Font.system(size: 12)` -> exit 1 naming file:line,
and again with `static var` -> same; same literal appended inside DSTypography.swift -> exit 0
(exempt), reverted; raw `.font(.system(size: 20))` (>=17) on a Text -> exit 1. One transient
"Simulator device failed to launch ... Busy" flake from back-to-back launches, unrelated to
smoke.sh logic -- immediate rerun passed clean.
