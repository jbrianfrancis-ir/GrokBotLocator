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

## 2026-09-09 21:55 · checkpoint-decision
- **asked**: Deploying to a physical iPhone needs a provisioning profile, but DEVELOPMENT_TEAM is the work team and only an Apple *Distribution* cert exists for it (no Development cert); the sole Apple Development cert on the Mac belongs to a personal team. Sign local device builds with the personal team, the work team, or don't deploy? [Team IDs redacted per the 2026-09-09 19:45 entry — ARCHITECTURE.md forbids them in tracked files.]
- **answered**: Personal team, for local device builds only. Applied as xcodebuild command-line overrides (CODE_SIGN_STYLE/CODE_SIGN_IDENTITY/DEVELOPMENT_TEAM) — Signing.xcconfig and project.yml were NOT modified, so the work team remains the committed configuration for distribution.
- **UNRESOLVED CONFLICT**: the 2026-09-09 19:30 entry chose the work team precisely because a *free* personal team's profiles expire after 7 days, stranding the app mid-trip (D-03). If this personal team is free, that risk returns for any real trip use. Adequate for closing the two device-only verification checks; NOT settled for shipping. Needs a human call before the app is relied on.
- **blocked-on**: Xcode has no Apple ID signed in ("No Accounts: Add a new account in Accounts settings"), so no profile could be created. Nothing was registered in any developer account; the build failed closed.
- **by**: Brian Francis <127874124+jbrianfrancis-ir@users.noreply.github.com>
- **at**: 3a4f353 · phase 01
