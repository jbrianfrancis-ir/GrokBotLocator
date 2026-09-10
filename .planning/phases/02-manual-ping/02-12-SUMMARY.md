---
plan: 02-12
status: complete
agent: executor/claude/claude-opus-5[1m]
commits: [31ce3ba, fda5537]
deviations: []
human_checks:
  - "Ping screen at AX5, light and dark: title wraps, notice/guidance/reason wrap, gear >= 60pt and not over the scrolling content, \"I'm here\" full-width in the bottom third. REQ-12's audit is 02-13's."
  - "Chrome bar: history blurred under it with Reduce Transparency off, flat opaque with it (or Increase Contrast) on."
  - "A real ping shows a spinner beside \"Pinging…\", ignores a 2nd tap, is read by VoiceOver."
deferred: []
---
`PingOutcomeRow` gained `var reason: String? = nil`, rendered between badge and label,
`.dsFont(.body)` — `.secondary` would put a failure reason on the 17pt floor. No line cap in the
file; its a11y label speaks outcome, label, coordinates, reason.

`PingHomeView`: ScrollView/VStack — wrapping title, `CredentialField` for the label, notice and
guidance as symbol + sentence + colour on opaque fills, then `PingOutcomeRow` over
`model.log.entries`. Chrome bar = gear only, no text; it uses `minWidth`/`minHeight`, since at AX5
an SF Symbol outgrows a fixed 60pt box and SwiftUI would draw it over the content. The chrome
modifier is applied once in the file; the bottom bar takes an opaque `DSPalette.body` fill.
`SettingsRoute` is here for 02-13. Previews drive two `ping()` calls (log is `private(set)`) for a
sent and a failed row.

Gate: smoke exit 0, "Test run with 84 tests in 12 suites". Both negative controls tripped their
greps, then were reverted.
