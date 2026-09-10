<!-- .planning/phases/02-manual-ping/02-06-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 02-06
status: complete
agent: executor/claude/claude-opus-5-1m
commits: [a98be30, a28da65, 15d9b67]
deviations: []
human_checks: []
deferred: []
---
CoreLocationFixProvider.swift (@MainActor, LocationFixProvider conformance)
is the only file touching CLLocationManager/CLLocationUpdate. Requests
When-In-Use inside currentFix() only, waits at most 60s (250ms x 240
polls) for the system prompt then throws .notAuthorized, races an 8s
CLLocationUpdate.liveUpdates(.default) stream against a timeout via
withThrowingTaskGroup (cancelled on first result either way), and returns
only via LocationFix.validated(...) — one call, zero memberwise inits.
project.yml gained INFOPLIST_KEY_NSLocationWhenInUseUsageDescription (no
Always key, no UIBackgroundModes). scripts/smoke.sh gained a location
guard, before xcodegen generate, failing on
requestAlwaysAuthorization/startUpdatingLocation/
allowsBackgroundLocationUpdates anywhere in src/, or CLLocationManager/
CLLocationUpdate outside CoreLocationFixProvider.swift. All three
falsify steps run (probe added, guard/grep fires, reverted); smoke.sh
green and tree clean after each. PlistBuddy confirmed the purpose string
is in the built Info.plist and UIBackgroundModes is absent.
