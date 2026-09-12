# Roadmap

| NN | Phase | Goal (one line) | Requirements | Status |
|----|-------|-----------------|--------------|--------|
| 01 | Foundation & design system | XcodeGen project, signing config, `DESIGN.md` tokens and components, Keychain-backed settings screen, smoke script | REQ-01, REQ-12, SC-05, SC-06 | verified |
| 02 | Manual ping | Authorization flow, one-shot fix, payload encoder, POST, history list, test-connection — the "I'm here" button works end to end | REQ-02, REQ-03, REQ-04, REQ-10, REQ-11, SC-01, REQ-12 | merged, acceptance open |

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
### Carried out of phase 02 — merged before its acceptance ran
PR #2 merged 2026-09-10 with **eleven on-screen checks never run**. They are the acceptance
evidence for REQ-02, REQ-03, REQ-04, REQ-10, REQ-11, SC-01 and REQ-12, listed runnable in
`phases/02-manual-ping/VERIFICATION.md`. Phase 02 is integrated, NOT verified — close them on a
device and record the result there, not here.
- **REQ-02 / REQ-04 / SC-01** — real endpoint: the four-key body in ARCHITECTURE's key order,
  "Sent" under 10s, then a forced 401 giving two rows with distinct outcomes and a reason.
- **REQ-03** — type "Gallipoli", send, force-quit, relaunch: the field still reads it.
- **REQ-10** — at When In Use the button works and the screen names what Always adds; Never gives
  a guidance sentence and NO history row.
- **REQ-11** — a wrong key shows a visible `HTTP 401` with its body, no alert, key never redisplayed.
- **REQ-12** — Accessibility Inspector at AX5, light AND dark, on PingHomeView **and** SettingsView.
  The AX5 `actionLabel` > `screenTitle` inversion is ACCEPTED (15:30 decision) — never file it.
- **Phase-01's three deferred components**, still open a second phase later: PingButton in flight,
  PingOutcomeRow at AX5, `.dsChrome()`'s Reduce-Transparency fallback.

Three backstop truths also remain unverified by design — the non-401/403 4xx retry policy, whether
the app prepends `Bearer `, and what a negative `horizontalAccuracy` means. Each needs a rule
stated in REQUIREMENTS.md, then a test.

| 03 | Durable delivery | Offline queue, backoff retry, connectivity observation, failure classification — no ping is lost on Italian roaming | REQ-05, SC-02 | verified, merged (PR #4) |

### Carried out of phase 03 — REQ-05's fourth drain opportunity
REQ-05 names four opportunities the queue may drain on: connectivity returning while the app is
alive, a **location-triggered wake**, a manual launch, and a `BGAppRefreshTask`. Phase 03 owns
three. The location-triggered wake cannot be built there — nothing wakes the app on location until
phase 04 registers significant-change, visit and geofence monitoring — so it is **deferred, not
waived**, and REQ-05 is listed against phase 04 below so it cannot be marked done without it.
- **Entry point already built**: `QueueDrainCoordinator.drainForeground()` (phase 03, plan 03-10).
  Phase 04 calls it from each location callback; it needs no new drain machinery, only the call.
- Phase 03 verifies green without it by design. REQ-05's `accept:` clause does not exercise a
  location wake, which is exactly why this section exists — the clause cannot be the tracker.

| 04 | Automatic triggers | Significant-change, visits, `CLMonitor` geofences, per-trigger toggles, rate limit, reverse-geocoded labels | REQ-05 (location-wake drain, carried), REQ-06, REQ-07, REQ-08, REQ-09, REQ-10 (Always half), SC-03, SC-04 | planned |

### Carried into phase 04 from PR #4 — two decisions merged unresolved
PR #4 merged 2026-09-11 (`c83a2c8`) with two defects its own body marked **"needs a decision"**. The
merge authorized integration; it did not answer either question, and both are live on `main` now.
Rule on them in phase 04 — they touch the code phase 04 extends. Full record: `DECISIONS.md`
2026-09-11 15:00 · pr-upstream.
- **`hydrate()` vs `ARCHITECTURE.md:72` — a law-vs-code contradiction, not a bug.**
  `QueueDrainCoordinator.hydrate()` copies queue entries into `PingHistoryLog`. D-12 sanctioned the
  queue file as the ONE coordinate store on the express condition that entries are "never copied
  anywhere else". The shipped code violates binding law today. The ruling is *which side moves* —
  narrow the clause, or drop the copy — and either way a Forbidden clause gets edited, so it is a
  human's call. Phase 04 queues a position on every automatic trigger, which makes this hotter, not
  cooler: more writes reach `hydrate()` the moment triggers land.
- **`UnqueuedPingSink` relabels a retryable disposition permanent.** With the queue unavailable, a
  429 renders as *"Failed: it is waiting and will be sent again."* — a sentence that contradicts
  itself, and nothing is waiting. Directly undercuts D-14, which had just made 429/408 retryable.
  User-facing and cheap; needs a decision only on what it should say instead.

Also still open and NOT closed by this merge: phase 02's eleven on-screen acceptance checks, the
three phase-01 components deferred twice, nothing yet seen at AX5 (including D-13's new type scale
and two bottom-bar changes), SC-06 unmeasured after that cut, REQ-05's connectivity-edge and
background drain paths never exercised, and `.completeFileProtectionUnlessOpen` proven by grep
rather than at runtime on a device.
