<!-- .planning/phases/04-automatic-triggers/04-04-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 04-04
status: complete
agent: executor/claude/sonnet
commits: [d91cb86, a5e543a, 35dba3b, aa039c5, f18c909]
deviations: ["[found by hang, not review] label(for:) originally raced fetch/timeout as two withTaskGroup children per plan text, relying on request.cancel() to unblock the loser before the group's implicit await-all-children returned. No geocoding service reachable in sim -> cancel() did not resume the leaked mapItems continuation -> function hung, violating the 3s bound. Fixed (aa039c5): fetch runs as an unstructured, never-awaited Task; a Mutex-guarded one-shot flag lets whichever of {fetch, timeout} wins resume a checked continuation exactly once. cancel() kept as hygiene only."]
human_checks: []
deferred: []
---
TriggerLabelProviding + EmptyTriggerLabelProvider (TriggerLabel.swift) and
MapKitTriggerLabelProvider (D-15) landed with tests. MapKit import/types confined to exactly one
file (grep-verified). Every failure path lands on "". Final smoke: 205 tests / 23 suites, exit 0.

Backstop evidence for next reader: `MKReverseGeocodingRequest.mapItems` does NOT reliably resume
on `cancel()` with no service reachable (leaked continuation) -- stronger than RESEARCH's
"unverified". Future code on this request must bound itself by construction, not by cancel().
