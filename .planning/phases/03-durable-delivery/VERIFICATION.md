---
phase: 03-durable-delivery
status: pass
smoke: pass
gaps: []
unverified: []
settled_by_D14:
  - "4xx: 408/429 retryable, rest permanent — was an abstention, now stated in REQUIREMENTS.md"
  - "give-up horizon: 7 days from first attempt — confirmed and stated"
  - "retention of a permanently-failed queued ping until shown — confirmed and stated"
---

## Smoke
`SMOKE_DERIVED_DATA=build/dd-verify-03 ./scripts/smoke.sh` → exit 0, `** TEST SUCCEEDED **`,
`Test run with 164 tests in 19 suites passed`, all six guards printed, `==> smoke passed`.
Wire-format condition met: `encodesExactlyTheFiveKeysWithTheRightTypes()` +
`keysAppearInTheOrderArchitectureNames()` passed in this run (lat,lng,accuracy_m,label,at).

## Truths
| must_have truth | result | evidence |
|---|---|---|
| 03-01 five keys in order; `at` is the FIX time; no default `capturedAt`; byte-stable | VERIFIED | `atCarriesTheFixTimeNotTheEncodeTime()`, `encodesExactlyTheFiveKeysWithTheRightTypes()`, `keysAppearInTheOrderArchitectureNames()`, `encodingIsByteStableAcrossCalls()` all passed; `PingPayload.capturedAt` has no default (PingPayload.swift), `LocationFix.payload(label:)` is the only bridge |
| 03-02 strictly growing capped backoff; pure function; give-up carries a finished sentence | VERIFIED | `delayGrowsStrictlyUntilItCaps()`, `givesUpOnlyAfterSevenDaysFromTheFirstAttempt()`, `theGiveUpReasonIsAFinishedSentence()`; `PingRetryPolicy` takes `now:` as a parameter, imports only Foundation |
| 03-03 rising edge only; first observation silent; pure value type | VERIFIED | `theFirstObservationNeverFiresAnEdge()`, `onlyTheRisingEdgeFires()`, `aStableConnectionNeverRefires()`, `goingOfflineFiresNothing()`; smoke's `import Network` guard confines Network to Connectivity.swift (probed live, below) |
| 03-04 queued ping returns an identity that travels to the caller; refusal downgrades to permanent; existing call sites untouched | VERIFIED | `aQueuedPingCarriesTheSinksIdBackToTheCaller()`, `aRefusedEnqueueBecomesAPermanentFailureThatSaysSo()`, `aRefusedEnqueueLeavesNoQueuedID()`, `aDeliveredPingHasNoQueuedID()`; `PingAttempt.queuedID` is `UUID? = nil` in the init |
| 03-05 total-elapsed bound; truncation marked; no session default; timeout is retryable | VERIFIED | `theBoundedSessionCarriesATotalElapsedBound()` (`timeoutIntervalForResource == 30`), `aLargeResponseBodyIsTruncatedAtTheBudgetAndSaysSo()`; `init(session:)` has no default (URLSessionPingTransport.swift:30); `disposition(forTransportError:)` returns `.retryable` for every thrown error → `aTransportErrorIsRetryableAndReachesTheSink()` |
| 03-06 survives the process; backup-excluded provably at runtime; delivered entry removed; capacity refusal; unreadable file set aside | VERIFIED | `aQueuedPingSurvivesAFreshStoreOverTheSameDirectory()`, `theQueueFileIsExcludedFromBackup()` (reads `.isExcludedFromBackupKey` off the real file), `replaceRemovesADeliveredEntry()`, `appendRefusesWhenTheQueueIsFull()`, `anUnreadableFileIsSetAsideAndReported()` |
| 03-07 Queued row with reason; in-place flip; unknown id inserts; capacity/order held; `show(notice:)`; silent apply; empty list announces nothing | VERIFIED | `aRetryableAttemptRecordsAQueuedRowCarryingItsReason()`, `aQueuedRowFlipsToSentWhenTheDrainReportsIt()`, `applyingAnUpdateForAKnownIdReplacesTheRowInPlace()` (asserts id order unchanged), `applyingAnUpdateForAnUnknownIdInsertsANewestFirstRow()`, `applyingUpdatesNeverExceedsCapacity()`, `applyingSilentlyLeavesLastAttemptUntouched()`, `anEmptyUpdateListAnnouncesNothing()`, `showNoticePutsASentenceOnScreen…()` |
| 03-08 disk before the promise; starts at one attempt; refusal is a safe sentence | VERIFIED | `aQueuedPingIsOnDiskBeforeTheIdIsReturned()`, `theEntryStartsAtOneAttemptWithABackoffAlreadyApplied()`, `aStoreRefusalBecomesANotQueuedSentence(_:)`, `nothingIsQueuedWhenTheAppendThrows()`; no error/URL/key interpolated (DurablePingSink.swift:36-51) |
| 03-09 delivered→removed+Sent; not-due untouched; retryable backs off silently; permanent kept until surfaced; no credentials drains/deletes nothing; deadline preserves the rest; rewritten per entry | VERIFIED | `aDeliveredPingIsRemovedFromTheFileAndReportedSent()`, `aPingNotYetDueIsLeftCompletelyAlone()`, `aRetryableFailureBacksOffWithoutReportingOrRemoving()`, `aPermanentRejectionIsMarkedButKeptWhenNotSurfacing()` (both halves), `missingCredentialsDrainNothingAndDeleteNothing()`, `theDeadlineStopsTheWalkAndLeavesTheRestQueued()`, `theFileIsRewrittenAfterEachEntryNotOnlyAtTheEnd()` |
| 03-10 launch hydration before any send, once, silent, capped-newest; edge drain flips to Sent unattended; notice reaches the screen; background keeps failures on file | VERIFIED | `launchHydratesTheHistoryFromTheQueueFile()` (`lastAttempt == nil`), `hydrationRunsOnlyOnce()`, `hydrationIsCappedAtTheLogsCapacityAndKeepsTheNewest()` (all entries still on file), `aConnectivityEdgeDrainsTheQueue()`, `aNoticeFromTheDrainBecomesOnScreenGuidance()`, `aBackgroundDrainKeepsAPermanentlyFailedEntryOnFile()`; `start()` calls `hydrate()` before `drainForeground()` (QueueDrainCoordinator.swift:59-65) |
| 03-11 built plist permits the identifier + declares fetch; identifier is a build-setting reference; purpose string, portrait, launch-screen survive | VERIFIED | Read off the BUILT `GrokBotLocator.app/Info.plist`: `BGTaskSchedulerPermittedIdentifiers[0] = com.bfrancis.grokbotlocator.queue-drain`, `UIBackgroundModes = [fetch]`, `NSLocationWhenInUseUsageDescription` present, `UISupportedInterfaceOrientations = [Portrait]`, `UILaunchScreen` present. `project.yml:36` holds `"$(PRODUCT_BUNDLE_IDENTIFIER).queue-drain"`; no bundle id in `project.yml` or `src/`. See advisory below on tracked planning prose. |
| 03-12 DurablePingSink shipped; one store/one transport/one session; four drain triggers; identifier read from the plist; empty identifier submits nothing; no Application Support degrades to phase 02 | VERIFIED (trace) | GrokBotLocatorApp.swift:47-77 — one `WebhookSession.make()` transport into both `PingSender` and `PingQueueDrain`, one `FilePingQueueStore` into both `DurablePingSink` and the drain, `queue == nil` → `UnqueuedPingSink` and no coordinator; body:83-93 wires `.task start()`, `scenePhase .active` → `drainForeground()`, `.backgroundTask(.appRefresh)` → `drainBackground()`; `QueueDrainTask.identifier` reads the plist key only; `anEmptyIdentifierProducesNoRefreshRequest()` + `aRealIdentifierProducesARequestFifteenMinutesOut()` passed |
| 03-12 the smoke gate fails on each of its four new guards, seen live | VERIFIED | Probed by mutation on this branch, tree restored after each: FileManager in DurablePingSink → `queue-store guard failed`; `import Network` in PingQueueDrain → `import Network must appear only in …Connectivity.swift`; dropping `.completeFileProtectionUnlessOpen` → `queue-protection guard failed`; dropping `isExcludedFromBackup` → `queue-protection guard failed`; built plist with the key deleted → the guard's empty-identifier branch fires |
| 03-02 non-401/403 4xx: 408/429 retryable, rest permanent | VERIFIED (rule stated by D-14) | Was HUMAN (non-inferable) until D-14 settled it and REQUIREMENTS.md stated it. `a4xxThatCannotSucceedLaterIsPermanent(400,404,409,410,422,499)` and `theTwoTemporary4xxCodesAreRetryable(408,429)` now pin a stated rule, not the code's own choice. 408/429 changed behaviour here. |
| 03-02 give-up 7 days after the first attempt | VERIFIED (rule stated by D-14) | Was HUMAN (non-inferable). D-14 confirmed 7 days from first attempt, measured in elapsed time, and REQUIREMENTS.md states it, so `givesUpOnlyAfterSevenDaysFromTheFirstAttempt()` pins a rule rather than a constant. No behaviour change. |
| 03-06 a permanently-failed queued ping is retained until shown | VERIFIED (rule stated by D-14) | Was HUMAN (non-inferable). D-14 confirmed keep-until-shown-then-delete and REQUIREMENTS.md states it. No behaviour change. The BACKGROUND path that produces the retained state is still unexercised on a device — a gap in evidence, not in the spec. |

## Human checks
- [x] **REQ-05 queue+drain — PASS (2026-09-11, simulator, partial on the trigger).** Receiver stopped
  → tap → row read **Queued**. `PingQueue.json` held the entry with `attemptsMade: 1`,
  `nextAttemptAt - firstAttemptAt` = exactly 30.0s (03-02's `min(30·2⁰, 3600)`), and
  `xattr` showed `com.apple.metadata:com_apple_backup_excludeItem` — so the ping was genuinely on
  disk before the app said Queued (03-08's write-before-promise) and D-12's backup exclusion holds.
  Receiver restarted → row flipped to **Sent** with no taps → queue file became `[]` (D-12: entry
  deleted on delivery).
  **NOT TESTED: the connectivity-edge trigger.** The drain fired from `drainForeground()` via
  background→foreground, which is a different one of REQ-05's four opportunities. A real
  `NWPathMonitor` unsatisfied→satisfied transition still needs a device or a Wi-Fi toggle.
  Also not airplane mode: the endpoint was made unreachable by stopping the receiver, which yields
  connection-refused rather than a dead interface. Both classify retryable; they are not identical.
- [x] **REQ-05 relaunch — PASS (2026-09-11, simulator).** Receiver down → tap → Queued → process
  killed with `simctl terminate` (app binary confirmed gone) → queue file byte-identical across the
  kill → receiver restarted → relaunch → the ping delivered and the queue emptied. The payload
  arrived with wire keys `['lat','lng','accuracy_m','label','at']` in ARCHITECTURE's pinned order
  and `at` = `14:06:49Z` against an arrival of `14:07:45Z` — `at` carries the FIX time across a
  process death, 56s later (REQ-02 / D-12). An earlier attempt delivered nothing because the
  relaunch fell inside the 30s backoff window, which is the retry policy working, not a failure.
  **Found and fixed here: duplicate delivery (64f7b7d).** The first run of this check produced TWO
  POSTs for ONE queued ping, same `at`, same second. `PingQueueDrain` is an actor — reentrant
  across `await` — and both drain paths fire on launch, so the second drain loaded the same
  not-yet-replaced queue while the first was parked on the network. No test caught it because every
  test drove one drain at a time against a transport that never suspends. Re-verified after the
  fix on the same sequence: deliveries 2 → 1.
- [x] **Forced permanent rejection while queued — PASS (2026-09-11, simulator).** Ping queued
  against a dead receiver, receiver brought back answering 401, backoff waited out, drain run.
  Exactly ONE POST (401 is permanent and was never retried), the row read **Failed** with the
  verbatim `Rejected by the webhook (HTTP 401). Check the sender key and header name in Settings.`
  over label/coords/fix-time, and the queue file went to `[]`. Relaunch: "No pings yet", zero
  further POSTs — it did not survive.
  **Caveat on what this does NOT show.** A foreground drain runs `surfacingFailures: true`, so the
  failure was reported and deleted in the same pass; the "retained on disk carrying its reason
  until shown" state only exists on the BACKGROUND path (`surfacingFailures: false`), which was not
  exercised. D-14 has since settled the RULE (keep until shown, then delete), but the background
  path that produces the retained state remains unexercised on a device — a gap in evidence, not
  in the spec.
- [x] **REQ-04 unchanged — PASS (2026-09-11, simulator).** Receiver on 200 → tap → green check
  **Sent**; receiver flipped to 401 → tap → red triangle **Failed** with its reason. Two rows,
  newest first, distinct by symbol AND word AND colour (DESIGN.md: never colour alone). The wire
  confirms one POST per tap — `200` at 14:12:34Z, `401` at 14:12:51Z — so no duplicate survived
  the drain fix. Queue stayed `[]` throughout: a 401 is permanent and is never queued.
- [x] **Non-401/403 4xx policy — SETTLED (D-14).** 408 and 429 are now retryable; the rest of the 4xx range stays permanent. Behaviour CHANGED: `PingClassifier` gained a `case 408, 429` arm ahead of `400...499`, pinned by `theTwoTemporary4xxCodesAreRetryable`. Stated in REQUIREMENTS.md, so it is no longer non-inferable.
- [x] **Give-up horizon — SETTLED (D-14).** 7 days from the first attempt, measured in elapsed time not attempt count. Confirms what shipped; now a stated rule in REQUIREMENTS.md rather than a chosen default, so `givesUpOnlyAfterSevenDaysFromTheFirstAttempt` pins a rule instead of recording a choice.
- [x] **Retention until shown — SETTLED (D-14).** A background drain marks the failure and leaves it on disk; the next foreground drain reports and removes it. Confirms what shipped. This is what makes SC-02's "shown permanently failed with a reason" true for a failure found while nobody was looking. NOTE: the background path itself was still not exercised on a device — the foreground drain reports and deletes in one pass.
- [x] **Bundle id in planning prose — SETTLED (D-14).** Out of scope for ARCHITECTURE's Forbidden list, which is narrowed to source and build configuration. A bundle id is not a secret and is public in any shipped build; the rule exists to keep signing identity out of the build, and that half is unchanged and still guarded (03-11 proved `project.yml` carries no literal).

## Learnings
- The composition root (`GrokBotLocatorApp.init`) is verified only by code trace — no test constructs it, and no smoke guard asserts `DurablePingSink` is the shipped sink. A future edit swapping it back to `UnqueuedPingSink` would leave the whole suite green.
- `PingQueueDrain` writes the queue back with `try? await store.replace(...)` (PingQueueDrain.swift:146): a failing rewrite is swallowed, so the "killed mid-drain cannot re-send" guarantee holds only while writes succeed. Drain tests prove the call pattern against a fake store, not the file.
- `drainBackground()` applies updates with `announcing: true` (QueueDrainCoordinator.swift:134), so a background-wake outcome sets `lastAttempt` and can post a VoiceOver announcement for a tap the user never made. No phase-03 truth forbids it — the launch-hydration path is the one that is silent — but phase 04's wake triggers land on the same method.
