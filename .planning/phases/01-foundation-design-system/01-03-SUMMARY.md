---
plan: 01-03
status: complete
agent: executor/claude/sonnet
commits: [bfb4251, 7433c30]
deviations: []
human_checks: []
deferred: []
---
DSTypography.swift: `DSTextStyle` (body 20/secondary 17/actionLabel 28 semibold/screenTitle
34 bold, each with a `relativeTo` text style) plus a private `DSFontModifier` whose
`@ScaledMetric` resolves inside the View body -- the only form that scales. `.dsFont(_:)`
is the sole way tokens reach a view; no `Font` is ever `static`. RootView's placeholder
Text now calls `.dsFont(.body)`. DynamicTypeScalingTests (`@MainActor @Suite`) measures
each token's rendered height via `ImageRenderer` at `.large` vs `.accessibility5`,
asserting AX5 >= 1.5x default; a `Font.custom(fixedSize:)` negative control asserts ~1.0x
in the same suite. Verified the harness can fail: swapped the modifier to a plain
`.system(size:)` literal, reran -- all 4 cases failed naming the expectation -- then
reverted and reran clean. `xcodebuild test`: "Suite DynamicTypeScalingTests passed",
"Test run with 3 tests in 1 suite passed" (Swift Testing count; XCTest's line stays 0).
