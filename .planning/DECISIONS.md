# Decisions

## 2026-09-09 19:20 · checkpoint-decision
- **asked**: Phase-1 plans had defects I proved empirically and /flow-plan's 3-round revision budget was spent. Resolve by (1) applying the fixes directly, (2) a fresh planner + checker round, (3) executing as-is, or (4) a /flow-oracle second opinion?
- **answered**: Option 1 — apply the fixes directly. Also supplied the signing Team ID source (the iOS app in SpecialProjects.StudentLoans) and resolved the open sender-key question: show a "key saved" indicator rather than exposing the credential.
- **by**: owner
- **at**: 9e3c723 · phase 01

## 2026-09-09 19:20 · checkpoint-decision
- **asked**: On relaunch, should the sender key field repopulate with the stored key, or show a saved-indicator with the value withheld? Both satisfy REQ-01 and the requirements did not settle it (backstop truth on plan 01-10).
- **answered**: Show "key saved" with the value withheld. User's reasoning: avoid exposing a credential on screen.
- **by**: owner
- **at**: 9e3c723 · phase 01 / plan 01-10

## 2026-09-09 19:30 · checkpoint-decision
- **asked**: Sign this personal app with the paid Apple Developer signing team, or a personal team? A free personal team's provisioning profiles expire after 7 days, which would strand the app mid-trip (D-03). [Team IDs redacted — see redaction note below.]
- **answered**: Keep the signing team for signing only. The app stays personal — bundle id is com.bfrancis.grokbotlocator, not a company prefix. User was shown that this registers the App ID under the signing team's developer account.
- **by**: owner
- **at**: a68b10f · phase 01

## 2026-09-09 19:45 · secret-scan-clearance
- **asked**: N/A — self-reported policy violation, not a gate the human raised.
- **answered**: I wrote two literal Apple Team IDs into the entry above while quoting the question, then committed and pushed them. ARCHITECTURE.md forbids DEVELOPMENT_TEAM in any tracked file. The values are redacted here. They remain in git history at commits before 0c11338; a Team ID is a low-sensitivity public identifier (it appears in any distributed app's receipt and authenticates nothing on its own), so history was NOT rewritten — that is the user's call, and force-pushing is destructive. The live values remain only in the gitignored Signing.xcconfig.
- **by**: owner
- **at**: 0c11338 · phase 01

## 2026-09-09 21:55 · checkpoint-decision
- **asked**: Deploying to a physical iPhone needs a provisioning profile, but DEVELOPMENT_TEAM is the signing team and only an Apple *Distribution* cert exists for it (no Development cert); the sole Apple Development cert on the Mac belongs to a personal team. Sign local device builds with the personal team, the signing team, or don't deploy? [Team IDs redacted per the 2026-09-09 19:45 entry — ARCHITECTURE.md forbids them in tracked files.]
- **answered**: Personal team, for local device builds only. Applied as xcodebuild command-line overrides (CODE_SIGN_STYLE/CODE_SIGN_IDENTITY/DEVELOPMENT_TEAM) — Signing.xcconfig and project.yml were NOT modified, so the signing team remains the committed configuration for distribution.
- **UNRESOLVED CONFLICT**: the 2026-09-09 19:30 entry chose the signing team precisely because a *free* personal team's profiles expire after 7 days, stranding the app mid-trip (D-03). If this personal team is free, that risk returns for any real trip use. Adequate for closing the two device-only verification checks; NOT settled for shipping. Needs a human call before the app is relied on.
- **blocked-on**: Xcode has no Apple ID signed in ("No Accounts: Add a new account in Accounts settings"), so no profile could be created. Nothing was registered in any developer account; the build failed closed.
- **by**: owner
- **at**: 3a4f353 · phase 01

## 2026-09-10 · evidence — the personal-team conflict is now measured, not hypothetical
- **asked**: N/A — resolves the UNRESOLVED CONFLICT logged 2026-09-09 21:55 (is the personal team free or paid?).
- **answered**: FREE. The provisioning profile Xcode issued for com.bfrancis.grokbotlocator spans exactly 7 days (created 2026-09-09, expires 2026-09-16). So D-03's "stranded mid-trip" risk is real for any personal-team build: the app stops launching a week after each install. Adequate for the phase-1 device verification it was created for — both device-only checks are now closed — and NOT adequate for carrying the app on a trip. Shipping still needs either the signing team (D-11 as originally decided) or a paid personal membership. Human call, not taken here.
- **note**: the device build was signed by a personal team whose id differs from the one inferred from the local Development certificate's CN; the cert CN suffix is a certificate identifier, not a Team ID. [Team IDs redacted per the 2026-09-09 19:45 entry.]
- **by**: owner
- **at**: 3a4f353 · phase 01

## 2026-09-10 · checkpoint-decision
- **asked**: Three phase-01 acceptance checks (PingButton press/in-flight, PingOutcomeRow at AX5, DSChrome opaque fallback) cover components phase 01 built but never gave a call site, so they can only be judged in Xcode previews. Force them now, or carry them to phase 02 where real screens adopt them?
- **answered**: Carry all three forward to phase 02. Recorded in ROADMAP.md under "Carried into phase 02 from phase 01" and marked [→] DEFERRED in phase 01's VERIFICATION. Deferred, NOT waived — phase 02 must close them on-screen. Note DSChrome's production path has never executed (zero call sites), so a preview could not have closed it honestly anyway.
- **by**: owner
- **at**: 3a4f353 · phase 01
