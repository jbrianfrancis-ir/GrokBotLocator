<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 15/15 | Status: verifying — gaps: [], human checks open
Last: 2026-09-12 — D-21 closed in code: merged (PR #6, c18070f), smoke green 275/29,
  signed build launched on the phone. Field check still owed.
Next: webhook in Settings, tap "I'm here", walk 500 m. Then D-21 proper — trigger
  OFFLINE and locked, restore network, confirm the ping drains.
## Gate
type: human-action
asked: Device checks left: D-21 locked pocket, REQ-07 visits, REQ-05's 4th drain,
  SC-03 battery, D-16 class. All need real-world use.
options:
  1. Configure the webhook and use it on the trip; treat the trip as UAT.
  2. Also set up TestFlight first, so fixes can ship without the Mac.
default: none
## Run
Iteration: 6 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule2:phase04:plans15/15:verifhuman
## Decisions
- D-15: MapKit reverse geocoding, one file
- D-16: 2nd coordinate store — last-ping position, overwritten never appended
- D-21: queue shares D-16's class, pocket-writable — shipped, unproven on hardware
## Blockers
- none blocking. On device as com.bfrancis.grokbotlocator.trip, profile to 2027-09-12.
- Sim surfaces no NSFileProtectionKey (probed: control and protected both nil), so
  D-21's test pins only the seam. Hardware is the only proof.
- REQ-08 dead on sim, understood, no app work left (debug/002): fence arms and computes
  (Inside)=>(Outside), sCount stays 0, never delivers.
- D-17/D-19 want pinning tests (D-18 done). 3 latent findings in TODOS.md.
## Session
Stopped: main c18070f, green, synced; branches cleaned to main alone; nothing in flight.
Resume: app work DONE for REQ-06. Sim needs `simctl location start` with lat,lon pairs,
  not a teleport; read locationd via `simctl spawn <udid> log show` first.
