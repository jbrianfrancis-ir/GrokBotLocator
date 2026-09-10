# Roadmap

| NN | Phase | Goal (one line) | Requirements | Status |
|----|-------|-----------------|--------------|--------|
| 01 | Foundation & design system | XcodeGen project, signing config, `DESIGN.md` tokens and components, Keychain-backed settings screen, smoke script | REQ-01, REQ-12, SC-05, SC-06 | verified |
| 02 | Manual ping | Authorization flow, one-shot fix, payload encoder, POST, history list, test-connection — the "I'm here" button works end to end | REQ-02, REQ-03, REQ-04, REQ-10, REQ-11, SC-01, REQ-12 | planned |

### Carried into phase 02 from phase 01
Three phase-01 acceptance checks were deferred, not waived. Phase 02 wires all three into real
screens; verify them **there**, on-screen, and close them in phase 02's VERIFICATION.

*Rationale corrected 2026-09-10 (pre-PR review):* this section previously said all three components
"never got a call site". That holds for PingOutcomeRow and DSChrome (both confirmed zero call sites)
but **not** for PingButton, which `SettingsView.swift:54` calls in production. Only its in-flight
state is unreachable.
- **PingButton** — in flight a spinner sits beside a changed word; VoiceOver reads label + in-flight state. **Only the in-flight half is deferred**: nothing outside the component's own `#Preview` sets `isInFlight`. The pressed state was already reachable at `SettingsView.swift:54` in phase 01. (Phase 02 gives it the "I'm here" button.)
- **PingOutcomeRow** — at AX5, light and dark, symbol + word + colour all present, reflowing with no clipping. (Phase 02 gives it the history list.)
- **DSChrome** — with Reduce Transparency on, or contrast increased, it resolves to a fully opaque fill instead of `.thinMaterial`. Phase 01 left `.dsChrome()` with **zero call sites**, so its production path has never run; the first screen to adopt it must re-verify for real, not by preview.
| 03 | Durable delivery | Offline queue, backoff retry, connectivity observation, failure classification — no ping is lost on Italian roaming | REQ-05, SC-02 | pending |
| 04 | Automatic triggers | Significant-change, visits, `CLMonitor` geofences, per-trigger toggles, rate limit, reverse-geocoded labels | REQ-06, REQ-07, REQ-08, REQ-09, SC-03, SC-04 | pending |
