---
plan: 01-07
status: complete
agent: executor/claude/sonnet
commits: [2449d6b, 922f93a]
deviations: []
human_checks: ["Press and hold PingButton in the preview: the fill visibly changes (foreground/background swap). Toggle isInFlight: the label word changes beside the spinner. VoiceOver reads label and in-flight state.", "At AX5 in both appearances CredentialField's label, field, and saved-indicator reflow without clipping; VoiceOver reads the label and the saved-indicator's value. No control anywhere reveals a secure value."]
deferred: []
---
PingButton.swift: full-width primary action, minHeight DSMetrics.primaryActionHeight,
radius DSMetrics.primaryActionRadius, `.dsFont(.actionLabel)`, opaque DSPalette.primaryAction
fill. Custom `PingButtonStyle` swaps the pair's foreground/background on press (real colour
change, not opacity — stays contrast-safe since the pair is symmetric). In-flight shows a
ProgressView beside a changed word ("Pinging…") and disables the button. accessibilityLabel
+ accessibilityValue speak in-flight state. CredentialField.swift: visible `.dsFont(.body)`
label above the field, never placeholder-only; secure variant has no reveal control (D-10) —
while `savedIndicator` is set and untouched (secure, empty, unedited) it shows that text in
place of a value with the binding still empty, tapping it starts a fresh edit. minHeight
DSMetrics.minTapTarget, opaque fill, DSMetrics.cornerRadius, autocorrect/autocapitalization
off, never prints/logs/defaults the bound value. Both files read every size/colour from
DSMetrics/DSPalette/DSTypography, no literals. 8 total `#Preview`s (4 per file: light/dark
x default/AX5), each showing every state. Verified: both grep guards exit 1 (no glass/
Material/print/NSLog matches), `./scripts/smoke.sh` → type-scale guard passed, xcodebuild
BUILD SUCCEEDED with both new files compiled into the app target, `** TEST SUCCEEDED **`,
4 tests/2 suites (unchanged from 01-06 — this plan added no new test target files).
