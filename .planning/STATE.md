<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 15/15 | Status: verifying — gaps: [], human checks open
Last: 2026-09-12 — D-21: queue file was sealed while locked, pocket pings dropped. Class moved
  to until-first-unlock, `.failed` no longer advances, sentence fixed. Smoke now GREEN: 275
  tests, 29 suites. D-21's own test named a member the fake lacked, so it had never compiled.
Next: set the webhook in Settings on the phone, tap "I'm here", then walk 500 m to
  confirm an automatic ping lands. D-21 + test fix still need a PR.
## Gate
type: human-action
asked: On the device with a 365-day profile. Remaining device checks are REQ-07 visits,
  REQ-05's fourth drain, SC-03 battery, D-16 protection class — all need real-world use.
options:
  1. Configure the webhook and use it on the trip; treat the trip as UAT.
  2. Also set up TestFlight first, so fixes can ship without the Mac.
default: none
## Run
Iteration: 6 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule2:phase04:plans15/15:verifhuman
## Decisions
- D-15: MapKit for reverse geocoding, one file
- D-16: 2nd coordinate store — the last-ping position, overwritten never appended
- D-21: queue file shares D-16's protection class, writable from a locked pocket
## Blockers
- none blocking. INSTALLED on device 2026-09-12 as com.bfrancis.grokbotlocator.trip (D-20
  rename cleared a personal-team App ID collision); profile expires 2027-09-12, 365 days.
- REQ-08 unverifiable on sim, cause understood, no app work left (debug/002): locationd shows
  the fence armed and computing (Inside)=>(Outside), but sCount stays 0 so it never delivers.
- D-17/D-19 want pinning tests (D-18 done). 2 latent findings in TODOS.md.
## Session
Stopped: PR #5 MERGED. D-21 + smoke fix sit on claude/ping-while-locked-fyn2q0,
  2 commits off main, no PR open. Newest unpushed.
Resume: app work is DONE for REQ-06; the only thing between here and a working 2-week
  tracker is a signing cert (Blockers). Sim needs `simctl location start` with lat,lon
  pairs, not a teleport; read locationd via `simctl spawn <udid> log show` before theorising.
