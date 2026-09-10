<!-- .planning/phases/02-manual-ping/02-05-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 02-05
status: complete
agent: executor/claude/claude-opus-5-1m
commits: [4adb01f, bc5f0fd]
deviations: []
human_checks: []
deferred: []
---
LocationFix (latitude/longitude/accuracyMetres/timestamp), LocationFixError
(5 cases, each a finished sentence), LocationFixProvider protocol, and
LocationAuthorizationNotice.notice(for:) all live in
src/Core/Location/LocationFix.swift — no CLLocationManager, pure and
device-free. LocationFix.validated(...) is the only constructor 02-06 may
use; it refuses horizontalAccuracy < 0 as .invalidAccuracy (BACKSTOP — see
plan frontmatter). LocationFix.payload(label:) bridges to PingPayload.
tests/LocationAuthorizationTests.swift pins the notice at all five
authorization statuses, the payload bridge, every error's reason sentence,
and both accuracy branches (validatedAcceptsANonNegativeAccuracy /
validatedRefusesANegativeAccuracy). Both tasks' falsify steps run and
reverted cleanly. smoke.sh green, tree clean.
