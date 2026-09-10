---
project: none (self-authored — not linked to Claude Design)
projectId: null
pulled: 2026-09-09
local: src/Core/DesignSystem/
---
# Design constraints

Driving requirement: **legible and operable without reading glasses**, one-handed, in bright Puglia sun. Every rule below is a hard constraint, not a preference. Additions are a `checkpoint:decision`.

## Tokens
- **Type scale** (all `Font.custom`-free, all Dynamic Type-scaled): body 17pt, secondary 15pt, primary-action label 24pt semibold, screen title 30pt bold. Nothing below 15pt anywhere in the app. *(D-13, 2026-09-10: shrunk one step from 20/17/28/34. The original scale pushed secondary controls and their results below the fold on Settings at the DEFAULT text size; see D-13 for the SC-06 trade.)*
- **Dynamic Type**: supported to AX5 with no truncation, clipping, or overlap. Layouts reflow vertically; no fixed-height text containers.
- **Contrast**: body and action text ≥ 7:1 against its background (WCAG AAA). Secondary text ≥ 4.5:1. Verified in both light and dark appearance.
- **Spacing**: 8pt base; 24pt between grouped controls; 16pt minimum screen margin.
- **Tap targets**: ≥ 60×60pt (above Apple's 44pt floor). The primary action is full-width and ≥ 88pt tall.
- **Radii**: 16pt on cards and buttons; 28pt on the primary action.

## Components (by group)
- Primary action: `PingButton` — full-width, bottom third of the screen for one-handed reach, 28pt semibold label, distinct pressed and in-flight states.
- Status: `PingOutcomeRow` — timestamp, coordinates, label, outcome. Outcome is **always** symbol + word + color, never color alone.
- Input: `CredentialField` — 20pt text, visible field labels (never placeholder-only), secure entry with **no reveal control**; a stored sender key is never re-displayed and shows a "key saved" indicator instead (D-10).
- Chrome: navigation and toolbars only.

## Rules
- **Liquid Glass on chrome only** — toolbars, tab bars, navigation. Never behind body text, credential fields, or the primary action. Honour Reduce Transparency and Increase Contrast by falling back to opaque fills.
- Never convey state by colour alone; pair every colour with an SF Symbol and a word.
- No text over photographic or variable backgrounds.
- Full VoiceOver labels on every control; ping outcome is announced, not just rendered.
- Light and dark appearance both required and both contrast-verified.
- Errors state what happened and what to do next, in body-size text on screen — never a transient toast, never a bare status code.
