---
plan: 01-09
status: complete
agent: executor/claude/sonnet
commits: [b4aa788, 83e325a]
deviations: []
human_checks: ["On DEVICE only: install to a physical iPhone and confirm SecItem calls tagged with kSecAttrAccessGroup succeed — smoke.sh and the simulator cannot exercise the real keychain-access-groups entitlement, only hosting-without-entitlement, which is what makes SecItem work on simulator."]
deferred: []
---
GrokBotLocator.entitlements: plist with `keychain-access-groups` = exactly
`$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)`, no literal. project.yml: added
`CODE_SIGN_ENTITLEMENTS: GrokBotLocator.entitlements` to the app target; no DEVELOPMENT_TEAM,
no TEST_HOST/BUNDLE_LOADER added by hand (xcodegen emits both from the existing test-target
dependency).

Verified: both plan greps pass (`keychain-access-groups` present; literal-scan after
stripping `$(...)` substitutions finds nothing, exit 1). `xcodegen generate` exit 0;
pbxproj carries `CODE_SIGN_ENTITLEMENTS = GrokBotLocator.entitlements` in both app-target
configs and `TEST_HOST` x4 (hosted). `./scripts/smoke.sh` exit 0, `** TEST SUCCEEDED **`,
4 tests / 2 suites unchanged.

Extra check beyond the plan's ask: inspected the actual signed output. The real
`GrokBotLocator.app.xcent` that gets embedded is an empty dict — ad-hoc "Sign to Run
Locally" on simulator strips entitlements needing provisioning. Xcode also writes a
sibling `GrokBotLocator.app-Simulated.xcent` that CoreSimulator reads instead, and *that*
file shows the substitution resolved correctly: `keychain-access-groups` =
`<TEAMID>.com.bfrancis.grokbotlocator` (real value, present only in the untracked build/
directory, never in a tracked file). This is independent confirmation of the plan's
context note — simulator SecItem success comes from hosting, not this entitlement — and
of the substitution being real Xcode-resolved values, not something that could type-check
by accident. Do not read this as proof the device path works; only 01-10's on-device
human check can close that.
