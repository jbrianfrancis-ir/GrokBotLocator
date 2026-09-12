<!-- .planning/STATE.md — cap 1.5KB. Rewrite sections in place; never append. -->
# State
## Position
Phase: 4 of 4 (Automatic triggers) | Plans: 15/15 | Status: verifying — gaps: [], human checks open
Last: 2026-09-12 — 3 defects fixed (debug/001 session, debug/002 stale region, D-18 copy).
  REQ-06 re-confirmed; REQ-08 blocked by sim fence settling. Smoke GREEN 272/29.
Next: mint an Apple Development cert for the PAID team (expired 2025-12-16) — see
  DECISIONS 2026-09-12; PR #5 is open
## Gate
type: human-action
asked: No gaps left, smoke green. 5 checks need a device; 3 backstops need a stated RULE —
  an abstention is lifted by a human, never a green test. Full list in VERIFICATION.md
options:
  1. Run the 5 device checks + rule the 3 backstops, then /flow-verify 4 → /flow-pr.
  2. Rule the 3 backstops, defer device checks to UAT — phase stays unverified.
  3. Open the PR now — merges REQ-07/08 unproven on device.
default: none
## Run
Iteration: 6 | Started: 2026-09-11T16:05Z | Repeats: 0
Signature: rule2:phase04:plans15/15:verifhuman
## Decisions
- D-15: MapKit for reverse geocoding, one file
- D-16: 2nd coordinate store — the last-ping position, overwritten never appended
## Blockers
- CANNOT install a 2-week-durable device build: the paid team's Apple Development cert EXPIRED
  2025-12-16, its valid cert is Distribution-only, the only valid Dev certs are FREE personal
  teams (7-day profiles, D-03's stranded-mid-trip risk), and no Apple ID is signed into Xcode.
  Human action required; no code change can fix it. Evidence: DECISIONS 2026-09-12.
- REQ-08 unverifiable on the simulator, CAUSE UNDERSTOOD, no app work outstanding (debug/002
  resolved): locationd shows the fence armed at radius 150 and computing (Inside)=>(Outside),
  but sCount never leaves 0 so it never settles and never delivers. Needs a real device.
- D-17/18/19 were RULED 2026-09-11; D-18's code change is now done. D-17/D-19 want tests.
- 2 latent findings filed not fixed — see TODOS.md.
## Session
Stopped: 74 commits on flow/automatic-triggers, 3 unpushed. No PR opened.
Resume: REQ-08 had TWO causes, both closed — 04-15's arming gap, debug/001's missing session.
  Sim needs `simctl location start` with lat,lon pairs, not a teleport or .gpx; the repro's
  step 0 (other triggers off, force-quit) is load-bearing.
