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

## 2026-09-10 14:12 · checkpoint-human-action
- **asked**: Phase 01's last two acceptance checks, both on the settings screen. (1) VoiceOver phrasing: does the screen announce all 7 elements as specified — heading trait on the title, "Webhook URL" spoken once (no double-speak from the `accessibilityHidden` visible label), the sender key row reading "Sender key, Key saved, button" and **never** speaking the stored key or the SF Symbol name, and "Clear settings" against the visible "Clear"? (2) Accessibility Inspector audit at AX5 (`content_size accessibility-extra-extra-extra-large`) in light and dark: zero contrast and zero hit-target findings (REQ-12).
- **answered**: BOTH PASS. On (1), verbatim: "all rows pass, no double-speak, key never spoken" — D-10 therefore holds in the accessibility layer, not just on screen. On (2), verbatim: "pass", given after the orchestrator drove the simulator to AX5 light, then flipped to dark on request, and the human ran the audit in both. Interpreted by the orchestrator as zero contrast findings, zero hit-target findings in both appearances, and the Webhook URL single-line truncation at AX5 ruled NOT a REQ-12 clipping failure — the one judgment call flagged before the run. REQ-12 closed; phase 01 verified.
- **note**: the audit ran against a build the orchestrator rebuilt from HEAD and reinstalled, because the prior simulator install and the last source edit shared a timestamp minute and the nav-title fix (463ef71) could not be proven present. A stale second install under the placeholder bundle id `com.example.GrokBotLocator` was removed from the same simulator; the real install and its data were untouched.
- **still open, not part of this gate**: D-03 (free personal team, profile expires 2026-09-16 — verification-adequate, not ship-adequate) and the `http://`-rejection field error, which is trace-verified and unit-tested but has never been typed into the UI by a human.
- **by**: owner
- **at**: 8ce2e53 · phase 01

## 2026-09-10 14:26 · review-refute
- **asked**: The design review lens tagged an AX5 type-hierarchy finding `blocking`, on the stated grounds that DSTypography's four tokens ride four different Dynamic Type curves and the screen title therefore renders SMALLER than body text at AX5 (claimed 53pt vs 62pt), making REQ-12 closed on evidence that cannot see it. Orchestrator measured it with the phase's own ImageRenderer harness: secondary 59, body 67, screenTitle 70, actionLabel 79. The specific claim is false — the title is larger than body — but the title/body gap collapses from 1.71x at default to 1.04x, and actionLabel genuinely overtakes screenTitle, so "Save settings" renders larger than the "Settings" heading. Accept the downgrade from blocking to should-fix?
- **answered**: DOWNGRADE ACCEPTED. Recorded as a refuted blocking finding in PR #1's body under "Deviations and open items", flagged as needing the reviewer's agreement, with the underlying defect listed under "Thin spots". Not fixed in this PR; belongs to phase 02 with a proper relative-order test.
- **by**: owner
- **at**: 25e72f6 · phase 01 · PR #1

## 2026-09-10 14:26 · checkpoint-decision
- **asked**: (1) The project declares no version field anywhere — no MARKETING_VERSION/CURRENT_PROJECT_VERSION, no manifest, no tags — and the built Info.plist carries neither CFBundleShortVersionString nor CFBundleVersion (verified against the binary, not inferred). App Store Connect and TestFlight reject uploads missing them. Establish a version now or not? (2) How much of the 6-lens review to fix before opening the PR?
- **answered**: (1) NO VERSION CHANGE. Recorded in the PR body as "version: no scheme declared; no bump applicable", with the missing Info.plist keys carried as an open item for a later phase. (2) FIX THE CONFIRMED FOUR — Clear button hit region (the confirmed blocking finding), Keychain ThisDeviceOnly on both add and update branches, smoke.sh's dead exit-code guard, and the two false records in VERIFICATION.md. Explicitly declined the wider "confirmed four + test hardening" option, so the contrast-accessor fix and the DSTextStyle 17pt floor assertion were carried as documented open items rather than applied.
- **note**: ~15 should-fix findings across six lenses were carried into the PR body unfixed, each named. The audit-trail gap (36 of 68 commits not machine-auditable) was recorded rather than remedied — the fix would force-push over 67 published commits and invalidate SHAs cited throughout .planning/; both the conventions lens and the orchestrator judged that the worse trade.
- **by**: owner
- **at**: 25e72f6 · phase 01 · PR #1
