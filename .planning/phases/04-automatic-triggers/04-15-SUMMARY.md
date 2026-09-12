<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-15
status: complete
agent: executor/claude/sonnet
commits: [025d574, 3abd709, f4ba8ed, b353226]
deviations: ["[Task 1/4] simctl location start takes lat,lon pairs, not .gpx paths as the plan wrote; extracted fixture coordinates and passed pairs instead (same real interpolated movement). See RESEARCH.md Q2 addendum."]
human_checks: ["REQ-08 cold-relaunch: geofence ON, sig-change/visits OFF, Always granted; ping, terminate, relaunch, drive req08-hop1 then hop2 -- two rows, second proves re-registration. Also report LastPing.json's real protectionKey on device (simulator read nil even for a control file)."]
deferred: []
---
Closes REQ-08's circular-arming gap: `recoverReferenceIfNeeded()` is the one place a
reference is recovered (last-ping file, then geofence centre), called from `applySettings`
and `runSignificantChange`. `FileLastPingStore` is D-16's second sanctioned store, all four
conditions pinned by tests on the real file; smoke's queue-store guard admits exactly two
writers now, plus an ESCAPE-probed last-ping-protection guard. Task 1's throwaway probe
measured CLMonitor persistence: it survived `simctl terminate` + relaunch and delivered an
exit event. Smoke: 267 tests/29 suites (was 259/28). The three open backstops are untouched.
