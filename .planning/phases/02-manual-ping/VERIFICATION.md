<!-- .planning/phases/02-manual-ping/VERIFICATION.md — 5.1KB against the template's 2KB cap,
     deliberately. The overshoot is the 11 unrun on-screen checks and their exact steps; cutting
     to 2KB would mean handing a human checks they cannot follow. Nothing reads this file for
     warm-start (STATE.md carries that), and phase 01's VERIFICATION.md is 20KB, so this is the
     tightest verification record in the project. Orchestrator's call, 2026-09-10. -->
---
phase: 02-manual-ping
status: human_needed
smoke: pass
gaps: []
unverified:
  - "02-03 non-401/403 4xx permanent, never retried"
  - "02-04 sender key verbatim, no app-added Bearer"
  - "02-05 negative horizontalAccuracy refused, not clamped"
---

## Smoke
`./scripts/smoke.sh` → exit 0, `** TEST SUCCEEDED **`, "84 tests in 12 suites passed" — 4 runs at 1d12324, tree clean after each; the once-flaky in-flight test never hung. Encoder condition met.

## Truths
| plan truths | result | evidence |
|---|---|---|
| 02-01 ×5 order tripwire, curves untouched | VERIFIED | 3 tests; log `AX5: 59/67/79/70` — actionLabel>screenTitle pinned, ACCEPTED per 15:30; 8 greps = 1 |
| 02-02 ×6 four keys, types, order, byte-stable, escaping, non-finite | VERIFIED | PingPayloadTests 6/6; byte-stable over 50 in-process calls, cross-process by construction (no dict container) |
| 02-03 ×4, 02-04 ×5 status/body kept, classification, sentence reasons, one POST, header, 204→"", non-HTTP throws | VERIFIED | PingClassifierTests 12 runs; PingTransportTests 5, URLProtocol stub |
| 02-05 ×6, 02-06 ×8 bridge, notices, purpose string, point-of-use, no Always/bg-GPS, CL confined, bounded wait | VERIFIED | LocationAuthorizationTests 14 runs; PlistBuddy on built Info.plist; all 3 smoke guards fired on live probes (file:line, exit 1) |
| 02-07 ×5, 02-08 ×6, 02-09 ×7 label persists, cap-50, whole ping in one call, fail-fast, only `.retryable` enqueued, one tap one POST, rows/guidance/notice/announcement | VERIFIED (coincidental-reliance) | PingHistoryTests 7, PingSenderTests 8, PingModelTests 11; no print/os_log in `src/`. Reliance: at 1d12324 smoke's UserDefaults guard skipped lines naming `UserDefaultsPingLabelStore` — probed a real second caller, smoke stayed exit 0. Patched in the working tree since (uncommitted); re-probed → exit 1, clean tree still 84/12 |
| 02-10 ×6, 02-11 ×3 shared sender, verbatim status/body, 401 headline, `status` untouched, control ≥60pt + disabled, no `lineLimit`, verbatim-key footnote | VERIFIED | SettingsModelTests (5000-char intact, ""→"", nil→nil); SettingsView.swift:84-93,124-150 |
| 02-12 ×6, 02-13 ×3 reason under badge + spoken, home layout, only production `.dsChrome()`, title in content, 5 concretes ×1, one shared sender, route wired | VERIFIED | PingOutcomeRow.swift:33,62; PingHomeView.swift:39-164; dsChrome greps = 2 (1 production, 1 preview); ctor greps = 1 in GrokBotLocatorApp.swift:22-30; RootView.swift:25-31 |
| 02-11/12/13 on-screen halves — 401 visible, AX5 reflow, in-flight, real-endpoint REQ-02/03/04/10 + SC-01, REQ-12 audit | HUMAN | 02-13 `status: partial`; tasks 2-4 never run |
| 3 backstops — 4xx policy, verbatim key, negative accuracy | HUMAN (non-inferable) | spec settles none; tests pin the code's choice, not a rule |

## Human checks
- [ ] **Real endpoint, When In Use** (02-13 T3): I'm here → receiver gets `{"lat","lng","accuracy_m","label"}` in that order, lat/lng numeric, "Sent" <10 s (REQ-02, SC-01). Force a 401 → two rows, distinct outcomes, failed one carries its reason (REQ-04). "Gallipoli" → force-quit → relaunch → still there (REQ-03). When In Use: button works, screen names what Always adds; Never → guidance sentence, NO row (REQ-10).
- [ ] **Phase-01's three deferred components** (02-13 T2): PingButton in-flight — spinner beside "Pinging…", 2nd tap ignored, VoiceOver reads it; PingOutcomeRow at AX5 light+dark — symbol+word+colour, reflows, no clipping; `.dsChrome()` on the ping bar — blurred with Reduce Transparency OFF, flat opaque with it (or Increase Contrast) ON.
- [ ] **REQ-12 audit** (02-13 T4): Accessibility Inspector at `content_size accessibility-extra-extra-extra-large`, light AND dark, on PingHomeView **and again on SettingsView** (02-11 added a control and a report there) → zero contrast, zero hit-target findings; "Send a ping" wraps; gear ≥60pt, not over scrolling content; "I'm here" full-width in the bottom third. The AX5 actionLabel>screenTitle inversion is ACCEPTED (15:30) — never file it.
- [ ] **REQ-11 on screen** (02-11): wrong key vs an endpoint that 401s → "Testing…", disabled; red triangle + sentence, `HTTP 401` line, body below; no alert/toast; stored key nowhere. Repeat at AX5 light and dark: both wrap, nothing clips.
- [ ] **Backstops** — decide each rule, then write a test that fixes it (or state it in REQUIREMENTS): non-401/403 4xx retry policy; whether the app prepends `Bearer `; negative `horizontalAccuracy`.

### Found by eye during phase 03 acceptance (2026-09-10) — two defects, both fixed
Neither was caught by a test, because both are layout properties no test asserts. Both were
found by looking at the running app while setting up phase 03's checks, which is the argument
for running the on-screen checks above rather than carrying them another phase.
- **SettingsView: the feedback displaced the action.** `statusView` sat in the same scrolling
  stack as "Save settings", positioned by `Spacer` + `minHeight`. Saving INSERTED the "Saved"
  badge into the flow, grew content past the screen, and pushed the button below the fold at
  the one moment the user was looking for it. Fixed by pinning the save group in a
  `safeAreaInset(edge: .bottom)` — the shape `PingHomeView` already used. `connectionReportView`
  stays in the scroll deliberately: it renders a whole 401 body, and a wrapped sentence in the
  bar eats the budget the 88pt action floor needs at AX5.
- **PingHomeView: the outcome rendered twice.** With one history row, the row and the pinned
  `lastAttemptBadge` showed the same symbol + word a few hundred points apart. Now gated on
  `PingModel.showsLastAttemptBadge`, which hides the badge only when the newest row already
  carries that outcome and reason. It still shows when the tap recorded NO row (refused fix,
  denied authorization — 02-12's original reason for it), and when a silent drain has moved the
  row past the standing feedback. Three tests, falsified by forcing the badge always-on.

**Neither fix has been seen at AX5**, and the pinned bar is precisely where large type bites.
The REQ-12 audit above is still open and now has to cover both screens' new bottom-bar shape.

## Learnings
- A guard that filters whole lines is escapable on that line: smoke.sh dropped any line naming `UserDefaultsPingLabelStore`, so a real `UserDefaults` call beside it passed clean. Strip the allowed token, then match — fixed in the working tree, not yet committed.
- Retryable sends are `.failed` with a reason, never `.queued`: `PendingPingSink` is a wired, tested no-op. Phase 03 swaps the sink AND flips that arm in `PingModel.ping()`.
- `PingSending.send` is nonisolated `async`, so a fake runs OFF a `@MainActor` suite: lock-guard counters and latch the continuation release, or the suite hangs (865a8ba, 2-in-5).
