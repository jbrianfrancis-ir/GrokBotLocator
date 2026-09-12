---
plan: 04-01
status: complete
agent: executor/claude/sonnet
commits: [9cbc841, 16079ea, bdb3c8f]
deviations: ["[Rule 1] Dropped the comment-strip step from the Always-confinement and MapKit checks (plan prose specified it). Probes (c) and (l) proved keeping it let a violation disguised behind a `//` comment mentioning the allowed filename pass clean -- exactly the same-line escape these path anchors exist to close. CLMonitor/UserDefaults keep comment-strip since no probe exercises that shape there and doc comments legitimately name those tokens."]
human_checks: []
deferred: []
---
project.yml: UIBackgroundModes now `[location, fetch]`; added
NSLocationAlwaysAndWhenInUseUsageDescription. smoke.sh: location guard split into an
unconditional ban (startUpdatingLocation/allowsBackgroundLocationUpdates/CLBackgroundActivitySession,
no exemption) + Always-in-LocationDelegateProxy + CLLocationManager-in-2-files +
CLMonitor-in-GeofenceMonitor (token-stripped); new MapKit guard confines import+types to
MapKitTriggerLabelProvider.swift (D-15); UserDefaults guard widened to PingLabelStore.swift +
TriggerSettingsStore.swift; new background-modes guard reads the built plist. All 13 escape
probes run on a throwaway copy outside the repo, per plan: (a)(b)(c)(e)(g)(h) location guard
failed; (d)(f) UserDefaults guard failed; (k)(l)(m) MapKit guard failed; (i)(j)(n) passed
clean. Clean-tree smoke.sh exits 0.
