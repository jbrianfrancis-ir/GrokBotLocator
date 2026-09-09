# Decisions

## 2026-09-09 19:20 · checkpoint-decision
- **asked**: Phase-1 plans had defects I proved empirically and /flow-plan's 3-round revision budget was spent. Resolve by (1) applying the fixes directly, (2) a fresh planner + checker round, (3) executing as-is, or (4) a /flow-oracle second opinion?
- **answered**: Option 1 — apply the fixes directly. Also supplied the signing Team ID source (the iOS app in SpecialProjects.StudentLoans) and resolved the open sender-key question: show a "key saved" indicator rather than exposing the credential.
- **by**: Brian Francis <127874124+jbrianfrancis-ir@users.noreply.github.com>
- **at**: 9e3c723 · phase 01

## 2026-09-09 19:20 · checkpoint-decision
- **asked**: On relaunch, should the sender key field repopulate with the stored key, or show a saved-indicator with the value withheld? Both satisfy REQ-01 and the requirements did not settle it (backstop truth on plan 01-10).
- **answered**: Show "key saved" with the value withheld. User's reasoning: avoid exposing a credential on screen.
- **by**: Brian Francis <127874124+jbrianfrancis-ir@users.noreply.github.com>
- **at**: 9e3c723 · phase 01 / plan 01-10

## 2026-09-09 19:30 · checkpoint-decision
- **asked**: Sign this personal app with the Informative Research work team, or a personal team? A free personal team's provisioning profiles expire after 7 days, which would strand the app mid-trip (D-03). [Team IDs redacted — see redaction note below.]
- **answered**: Keep the work team for signing only. The app stays personal — bundle id is com.bfrancis.grokbotlocator, not a company prefix. User was shown that this registers the App ID under the employer's developer account.
- **by**: Brian Francis <127874124+jbrianfrancis-ir@users.noreply.github.com>
- **at**: a68b10f · phase 01

## 2026-09-09 19:45 · secret-scan-clearance
- **asked**: N/A — self-reported policy violation, not a gate the human raised.
- **answered**: I wrote two literal Apple Team IDs into the entry above while quoting the question, then committed and pushed them. ARCHITECTURE.md forbids DEVELOPMENT_TEAM in any tracked file. The values are redacted here. They remain in git history at commits before 0c11338; a Team ID is a low-sensitivity public identifier (it appears in any distributed app's receipt and authenticates nothing on its own), so history was NOT rewritten — that is the user's call, and force-pushing is destructive. The live values remain only in the gitignored Signing.xcconfig.
- **by**: Brian Francis <127874124+jbrianfrancis-ir@users.noreply.github.com>
- **at**: 0c11338 · phase 01
