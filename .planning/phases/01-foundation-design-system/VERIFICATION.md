---
phase: 01-foundation-design-system
status: human_needed
smoke: pass
gaps: []
unverified: []
---

## Smoke
`./scripts/smoke.sh` → exit 0, `** TEST SUCCEEDED **`, `Test run with 21 tests in 5 suites passed`. Matches the declared pass condition (the encoder assertion named in ARCHITECTURE is phase 2's, not yet in scope).

## Truths
| must_have truth | result | evidence |
|-----------------|--------|----------|
| 01-01 xcodegen produces xcodeproj w/ scheme + both targets; TestAction lists GrokBotLocatorTests | VERIFIED | smoke ran `xcodegen generate`; scheme `<Testables>` has `GrokBotLocatorTests.xctest`, `skipped="NO"`; pbxproj has both targets |
| 01-01 DSMetrics carries 8/24/16pt, 60pt target, 88pt action, 16/28pt radii | VERIFIED | `src/Core/DesignSystem/DSMetrics.swift:6-18` — 8/24/16/60/88/16/28 |
| 01-01 + 01-10 no bundle id, team id or credential value in any tracked file | VERIFIED | `git ls-files \| xargs grep -nE 'DEVELOPMENT_TEAM\|PRODUCT_BUNDLE_IDENTIFIER'` → only `$(…)` substitution in the entitlements plist + placeholders in `Signing.xcconfig.example`; `Signing.xcconfig` and `*.xcodeproj/` untracked (gitignore:12, :2); URL scan of tracked src/tests finds only `example.invalid` |
| 01-02 simulator-udid.sh prints one udid, non-zero if none | VERIFIED | ran: prints `E188EA3E-…`, exit 0; `SIMULATOR_NAME=NoSuchDevice` → "no available iOS 26 iPhone simulator found", exit 1 |
| 01-02 xcodebuild test runs the bundle against its host, non-zero count | VERIFIED | smoke log: `TEST_HOST=$(BUILT_PRODUCTS_DIR)/GrokBotLocator.app/GrokBotLocator`; `✔ Test appModuleIsLinked()`; 21 tests |
| 01-02 RootView renders a plain unstyled Text | VERIFIED (superseded in-phase) | 01-02's own plan text schedules 01-12 to "swap in SettingsView"; `RootView.swift:13` now presents `SettingsView`, which uses `.dsFont` tokens only. The intent behind the truth (no raw font at the root) holds — `grep '\.system(size:\|Font.custom' src/` outside DSTypography → none |
| 01-03 every token scales (AX5 render measurably taller), proven by a test not a literal | VERIFIED | `✔ tokenScalesFromDefaultToAX5(style:) with 4 test cases passed` — ImageRenderer height ratio ≥1.5 over all four styles |
| 01-03 a fixedSize control in the same test reads 1.00, proving the harness can fail | VERIFIED | `✔ fixedSizeControlDoesNotScale()` — `abs(ratio-1.0) < 0.05` on `Font.custom(fixedSize:)` |
| 01-03 DSTypography is the only file with a font-size literal, none under 17 | VERIFIED | `grep -rnE '\.system\(size:\|Font\.custom\|size: *[0-9]+' src` excluding DSTypography → none; DSTypography sizes are 20/17/28/34, and it declares no `static let … Font` |
| 01-04 smoke.sh exits 0 with TEST SUCCEEDED and a non-zero count | VERIFIED | see Smoke above |
| 01-04 Signing.xcconfig renamed away → non-zero, names that file | VERIFIED | ran an isolated copy of `scripts/` with no xcconfig beside it: "Signing.xcconfig is missing - copy the .example and set DEVELOPMENT_TEAM and PRODUCT_BUNDLE_IDENTIFIER", exit 1 (the real file was never moved) |
| 01-04 no available iOS 26 iPhone simulator → non-zero, saying so | VERIFIED | `SIMULATOR_NAME=NoSuchDevice ./scripts/smoke.sh` → "could not resolve an iOS 26 simulator UDID", exit 1 |
| 01-04 fails, naming file and line, on a sub-17 font literal under src/ outside DSTypography | VERIFIED | added `src/Core/DesignSystem/__GuardProbe.swift` w/ `Font.system(size: 12)` → "type-scale guard failed … `__GuardProbe.swift:2`", exit 1; same literal appended inside DSTypography → guard passes on to `xcodegen generate`. Both probes removed, tree clean |
| 01-04 never passes CODE_SIGNING_ALLOWED=NO | VERIFIED | `grep -n CODE_SIGNING_ALLOWED scripts/smoke.sh` → no match |
| 01-05 a test computes the WCAG ratio of every pair in both appearances, floors 7:1 / 4.5:1 | VERIFIED | `✔ allPairsMeetContrastFloors()`; `DesignSystemContrastTests.swift:12-40` computes luminance locally over all 6 pairs × 2 appearances |
| 01-05 altering a foreground toward its background fails the test naming the pair and ratio | VERIFIED | set light body fg to `#777777`, ran `-only-testing:…/DesignSystemContrastTests` → `✘ Expectation failed: (lightRatio → 4.478…) >= 7.0` / `↳ body (light): 4.5:1 is below the 7.0:1 floor`, `** TEST FAILED **`. Reverted; tree clean |
| 01-05 every colour resolves through DSPalette, light + dark per token | VERIFIED | `DSPalette.swift:44-68` — six `DSColorPair`s each with 4 sRGB values; every view colour goes through `.foreground(for:)`/`.background(for:)` (PingButton:56, CredentialField:44/50/53/60, PingOutcomeRow:28/32/36/52/55, SettingsView:23/62/96/99) |
| 01-06 + 01-10 round-trip, overwrite-not-duplicate, empty-load-nil, clear-then-nil | VERIFIED | 6 passing tests incl. `secondSaveOverwritesWithoutDuplicate` (asserts `itemCount == 1` per account via an independent `SecItemCopyMatching`) and `missingUrlOrSenderKeyReturnsNilOnLoad` |
| 01-06 load with nothing stored returns nil — never a default url, key, or empty stand-in | VERIFIED | `✔ loadOnFreshServiceReturnsNil`; `KeychainCredentialStore.swift:26-33` returns nil on missing url or senderKey; `WebhookCredentials` has only `defaultHeaderName` |
| 01-06 + 01-10 interpolating WebhookCredentials prints redacted placeholders | VERIFIED | `✔ descriptionAndDebugDescriptionRedactAllFields` checks both `String(describing:)` and `String(reflecting:)` |
| 01-06 + 01-10 nothing writes to UserDefaults or a log | VERIFIED | `grep -rnE 'print\(\|NSLog\|os_log\|UserDefaults' src/` → none; `✔ savingNeverTouchesUserDefaults` scans a full `dictionaryRepresentation()` dump after a real save |
| 01-06 KeychainCredentialStore is the only SecItem caller | VERIFIED | `grep -rl SecItem src/` → `KeychainCredentialStore.swift` only |
| 01-07 PingButton full-width, ≥88pt, 28pt semibold label, opaque fill | VERIFIED | `PingButton.swift:38` `maxWidth: .infinity, minHeight: DSMetrics.primaryActionHeight` (88); `.dsFont(.actionLabel)` → 28/.semibold; `PingButtonStyle:56-61` `.background(fill)` is a plain `Color` |
| 01-07 pressed state changes fill; in flight a spinner beside a changed word | VERIFIED (trace) | `PingButtonStyle:56-57` swaps fg/bg on `configuration.isPressed`; `PingButton:31-36` renders `ProgressView()` + `inFlightTitle` — appearance confirmation is a human check |
| 01-07 CredentialField: visible label above the input, secure variant has NO reveal control, saved-indicator instead of a value (D-10) | VERIFIED | `CredentialField.swift:42-47` label `Text` precedes `fieldRow`; grep for `reveal\|eye\|isSecureTextEntry\|showPassword\|toggle` → only the doc comment; `showsSavedIndicator` (36-38) renders the indicator while `text` stays empty |
| 01-07 both render without clipping/overlap at default and AX5, light and dark | HUMAN | needs visual judgement; four previews per component exist (`#Preview` light/dark × default/AX5) |
| 01-07 every control carries a VoiceOver label; neither uses a glass or material background | VERIFIED | `.accessibilityLabel` on PingButton:42 and all three CredentialField branches (81/92/101); `grep -rn 'Material\|glass' src` → `.thinMaterial` only in DSChrome, which neither component uses |
| 01-08 PingOutcomeRow shows symbol + word + colour, never colour alone | VERIFIED | `PingOutcome` (`PingOutcomeRow.swift:64-92`) exposes `symbolName`, `word`, `pair` on one enum — no way to read the colour without them; badge renders all three (46-55) |
| 01-08 the row reflows without clipping at default and AX5, both modes | HUMAN | visual; four previews exist |
| 01-08 DSChrome resolves to an opaque fill under Reduce Transparency or increased contrast | VERIFIED (trace) | `DSChrome.swift:15-32` reads `\.accessibilityReduceTransparency` + `\.colorSchemeContrast`; `needsOpaqueFallback` → `fill.background(for:)` (an opaque `Color`), else `.thinMaterial`. Logged deviation: only the previews use the writable `_`-prefixed keys (public keys are get-only in the iOS 26.5 SDK); production reads the public ones |
| 01-08 glass arrives only via system chrome; no source file calls glassEffect | VERIFIED | `grep -rn 'glassEffect\|glassBackgroundEffect' src/` → none; system chrome comes from `NavigationStack` in `RootView.swift:12` |
| 01-09 app target carries a keychain-access-groups entitlement | VERIFIED (device effect is HUMAN) | `GrokBotLocator.entitlements:5-8`; `project.yml:19` and pbxproj:361,470 set `CODE_SIGN_ENTITLEMENTS` for both configs |
| 01-09 the entitlement uses build-setting substitution, no literal ids in the repo | VERIFIED | value is `$(AppIdentifierPrefix)$(PRODUCT_BUNDLE_IDENTIFIER)` — no literal id |
| 01-09 the test bundle runs hosted by the app and inherits that entitlement | VERIFIED | `TEST_HOST`/`BUNDLE_LOADER` set (pbxproj:378-388, 451-461); the Keychain suite's real `SecItem` calls all pass under that host |
| 01-10 tests use a throwaway service string, never the app's real one | VERIFIED | `KeychainCredentialStoreTests:25-27` and `CredentialLeakTests:16-18` both build `"test." + UUID().uuidString`; `SmokeTests:9` passes a literal throwaway |
| 01-11 load() repopulates url + headerName only; key never assigned, hasStoredKey instead (D-10) | VERIFIED | `✔ loadFillsURLAndHeaderButNeverTheKey` asserts `model.senderKey.isEmpty`; `SettingsModel.swift:37-51` never touches `senderKey` |
| 01-11 save refused with a specific sentence for non-https/unparseable url, empty key, empty header | VERIFIED | `✔ httpURLIsRejected`, `✔ schemelessURLIsRejected`, `✔ emptyOrWhitespaceKeyIsRejectedOnAFreshModel`, `✔ emptyHeaderIsRejected` — each asserts `saveCallCount == 0` and a field-naming message |
| 01-11 headerName starts at Authorization, stays editable, empty refused | VERIFIED | `✔ freshModelHeaderNameDefaultsToAuthorization`; bound editable at `SettingsView.swift:43`; read-side default is the store's own layer (`✔ emptyHeaderNameFallsBackToDefault`) |
| 01-11 a valid trio writes through the CredentialStore protocol; the model never builds a Keychain store | VERIFIED | `✔ validTrioSavesAndReachesTheStore`; `SettingsModel.swift:25-32` holds only the protocol; the sole `KeychainCredentialStore()` construction is `GrokBotLocatorApp.swift:9` |
| 01-12 the app launches into a settings screen; url, key, header the only inputs | VERIFIED | `GrokBotLocatorApp:9-14` → `RootView(settingsModel:)` → `SettingsView` (`RootView.swift:13`); exactly three `CredentialField`s (SettingsView:27-46) plus save/clear |
| 01-12 a rejected save shows an on-screen body-size sentence, not a toast or status code | VERIFIED | `SettingsView:85` renders `.error(message)` through `statusBadge`, `.dsFont(.body)` (:93) inline in the VStack — no `alert`/`toast` anywhere in src |
| 01-12 outcome shows as symbol + word + colour; no glass behind text, fields or the save action | VERIFIED | `statusBadge` pairs an SF Symbol with the text on `DSPalette.success`/`.failure` (:83-99); no material in SettingsView, CredentialField or PingButton |
| 01-12 setup completable unaided at default size; at AX5 nothing clips or overlaps in either appearance | HUMAN | visual/Accessibility Inspector judgement |
| 01-12 after force-quit, relaunch repopulates url + header, key field empty w/ saved indicator, nothing reveals it | HUMAN (device) | in-process half is proven (`.task { model.load() }` at SettingsView:71 + `✔ loadFillsURLAndHeaderButNeverTheKey`); real force-quit persistence needs a device |

## Human checks
- [ ] Launch once on simulator: opens portrait, rotating does not switch to landscape.
- [ ] PingButton previews: press-and-hold visibly changes the fill; `isInFlight` shows a spinner beside a changed word; VoiceOver reads label + state.
- [ ] CredentialField and PingOutcomeRow at AX5, light and dark: label/field/saved-indicator and the badge reflow with no clipping or overlap; VoiceOver reads the label and the saved-indicator value; no control reveals a secure value.
- [ ] DSChrome's three previews: default is translucent `thinMaterial`; "Reduce Transparency on" and "Increase Contrast on" both render a fully opaque DSPalette fill.
- [ ] On a physical iPhone: install and confirm `SecItem` calls succeed under the real `keychain-access-groups` entitlement (simulator passes on test hosting alone, so smoke.sh cannot prove this).
- [ ] On device, default text size: enter url/key/header, save, force-quit, relaunch — url and header repopulate, key shows "Key saved" with no value and no reveal control (D-10); an `http://` url gives an on-screen field error (SC-05/06).
- [ ] On device: run `strings` on the built binary — neither the sender key nor the webhook host appears.
- [ ] At AX5 in light and dark, run the Accessibility Inspector audit on the settings screen: zero contrast or hit-target failures (REQ-12).

## Learnings
- smoke.sh's type-scale guard is a plain text match on `size:` followed by 0-16 across all of `src/` — it will also flag a non-font `size:` argument (a `CGSize`, an `ImageRenderer` size). DSTypography is the only exemption; a later phase needing a small non-font `size:` has to widen the regex, not add exemptions.
- `DSChrome` has zero call sites in the app — the opaque fallback is exercised only by previews, and its production path reads the get-only public environment keys while the previews drive the `_`-prefixed writable siblings. The first screen to adopt custom chrome must apply `.dsChrome()` and re-verify the fallback for real.
- Every Keychain test passes on simulator through test-host bundle identity alone; the `keychain-access-groups` entitlement is never exercised by smoke.sh. A regression in the entitlement would stay invisible until a device install.
