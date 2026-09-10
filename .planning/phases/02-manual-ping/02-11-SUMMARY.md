---
plan: 02-11
status: complete
agent: executor/claude/claude-opus-5[1m]
commits: [dbea707, 5cb29e2]
deviations: []
human_checks:
  - "iOS 26 sim, wrong sender key vs a real endpoint that 401s: button reads \"Testing…\" while running; red triangle + sentence, an `HTTP 401` line, body below; no alert/toast; stored key nowhere."
  - "Repeat at `content_size accessibility-extra-extra-extra-large` in `appearance light` and `dark`: sentence and body wrap, nothing clips."
deferred: []
---
Test connection sits below Save/Clear, built like Clear (60pt frame + `.contentShape` INSIDE
the label), label "Testing…" and disabled while `isTesting`. `connectionReportView` renders
`connectionReport` inline: headline through the existing `statusBadge`, then `HTTP <code>` and
the body verbatim at `.dsFont(.secondary)`, `.textSelection`, NO `lineLimit`, combined into one
accessibility element. Empty body renders "(empty response body)" as a note, not a value.
Sender key footnote says the value is sent exactly as typed ("for example Bearer abc123") — the
app never prepends "Bearer". Nothing re-renders the stored key (D-10).
Previews: `connectionReport` is `private(set)`, so a private `StubPingSending` + a wrapper
calling `testConnection()` in `.task` gives `previewModel(hasStoredKey:sender:)` a real 401;
three previews added (default, AX5, dark AX5) with a multi-line body.
Gate: smoke.sh exit 0, "Test run with 84 tests in 12 suites", TEST SUCCEEDED, no warnings.
Falsify: `.lineLimit(1)` made the grep exit 0; reverted.
