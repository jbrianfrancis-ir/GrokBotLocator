# Architecture constraints

## Stack
| What | Exactly | Version |
|------|---------|---------|
| Platform | iOS (iPhone, portrait) | 26.0 min deployment target |
| Language | Swift, strict concurrency | 6.3.3 |
| Toolchain | Xcode | 26.6 (17F113) |
| UI | SwiftUI + Observation (`@Observable`), Liquid Glass on chrome | iOS 26 SDK |
| Project file | XcodeGen from `project.yml` | 2.46.0 |

## Principles
- **Zero third-party dependencies.** iOS SDK only; any SPM/CocoaPods/Carthage entry is a violation.
- **Credentials live only in the Keychain** — never in source, `project.yml`, `Info.plist`, `UserDefaults`, or a log line.
- **No ping is silently dropped.** Every send succeeds, is durably queued, or is recorded as failed with a user-visible reason.
- **Fully usable at "When In Use".** Manual pings work without `Always`; `Always` only unlocks automatic triggers.
- **`DESIGN.md` is binding.** No type below 15pt (was 17pt until D-13), no tap target under 60pt, no state conveyed by colour alone, Dynamic Type to AX5 — the app must be usable without reading glasses.
- **Transport and storage are protocol-backed and injected** — delivery is testable without a device or live webhook.

## Smoke
- **Command**: `./scripts/smoke.sh` — `xcodegen generate`, build for an iOS 26 simulator, run the test bundle.
- **Pass looks like**: exit 0; `** TEST SUCCEEDED **`; encoder test asserts `{"lat":<num>,"lng":<num>,"accuracy_m":<num>,"label":<string>,"at":<string>}` in that order.

## Frameworks & libraries (all iOS 26 SDK, no third-party)
- CoreLocation — fixes, significant-change, visits, `CLMonitor` regions
- Security (Keychain) — webhook URL / key / header storage
- Foundation `URLSession` — webhook POST
- Network `NWPathMonitor` — gating retries while the process is alive (cannot wake a suspended app)
- BackgroundTasks `BGAppRefreshTask` — supplementary opportunistic queue drain
- MapKit `MKReverseGeocodingRequest` — reverse geocoding for automatic-ping labels (D-15,
  2026-09-11). `CLGeocoder`/`CLPlacemark` are soft-deprecated at iOS 26.0 ("Use MapKit"), so
  this list does not pin the app to a deprecated API. First-party Apple SDK: "Zero third-party
  dependencies" is untouched. Confined to one file — see Forbidden.
- Swift Testing (bundled with Xcode 26.6) — unit tests

## Architecture & patterns
- App code under `src/`, tests under `tests/`; `project.yml` and `scripts/` at the root.
- Feature folders under `src/` (`Settings/`, `Ping/`, `Triggers/`, `Queue/`) plus `Core/` for Keychain/payload/transport.
- Offline queue is a `Codable` array in Application Support via `FileManager` — no SwiftData, no Core Data. The file is the durability mechanism; drain on every wake with a plain `URLSession`. `URLSessionConfiguration.background` is not the primary path.
- **The queue file is a sanctioned store for coordinates** (D-12, 2026-09-10). Narrow: written with
  `.completeFileProtectionUntilFirstUserAuthentication` (**amended by D-21, 2026-09-12** — it was
  `.completeFileProtectionUnlessOpen`, which sealed the file on every lock, so a send that failed in a
  locked pocket could not be queued and was dropped, and every background drain gave up; the queue
  now shares D-16's class and is openable from the first unlock after boot until the next restart),
  excluded from backups (`isExcludedFromBackup`), each entry deleted the moment it is delivered, and
  never copied to another DURABLE store. A queue that keeps
  delivered pings is a location history, which is not what this is for.
  **Narrowed by D-17 (2026-09-11):** reading queue entries into the in-memory, session-only history
  so a relaunch can show what is still pending is display, not storage — it creates no second
  durable copy and dies with the process. `QueueDrainCoordinator.hydrate()` is that path and is
  approved. The ban that stands is on a second durable copy; `UserDefaults`, logs and analytics
  remain off limits regardless of lifetime.
- **The last-ping coordinate is the second sanctioned store** (D-16, 2026-09-11). D-12's "never
  copied anywhere else" is widened by exactly this much and no further. REQ-08 re-registers a
  geofence at the last ping, and a cold relaunch has no other way to recover where that was —
  `CLMonitor` persistence is unverified, and without a durable record the trigger cannot arm at all
  in a geofence-only configuration. Conditions, all binding:
  - **Exactly ONE coordinate, overwritten in place, never appended.** A single overwritten point is
    not a location history; a list of them is, and that is what D-12 exists to forbid.
  - Excluded from backups (`isExcludedFromBackup`), same as the queue.
  - Protection class `.completeUntilFirstUserAuthentication`. When chosen it was **deliberately
    weaker than the queue's** then-`.completeFileProtectionUnlessOpen`; since D-21 the queue shares
    it. A geofence exit fires while the phone is locked in a pocket, which is the whole point of the
    feature; under complete protection the write would fail on exactly that wake and the region
    would never re-register. Phase 03 already shipped the inverse of this bug — a locked device
    could not open the queue and the drain reported the pings undeliverable — and D-21 closed it
    the same way. The trade is stated rather than hidden: both files survive a locked screen, so
    they are readable after first unlock following boot.
  - Deleted when every trigger is disabled — if nothing is watching, nothing needs the position.
- All location work sits in one actor-isolated coordinator; views never touch `CLLocationManager`.

## Infrastructure (Azure / Aspire resources)
- **None.** No server, no deployable surface. The webhook receiver is Grok-hosted; the app ships via Xcode/TestFlight.

## Wire format (pinned — the smoke gate asserts it byte for byte)
```
{"lat":<num>,"lng":<num>,"accuracy_m":<num>,"label":<string>,"at":<ISO-8601 string>}
```
Keys in exactly that order. `JSONEncoder` does **not** serialize in declaration order — key order is
non-deterministic per process, measured over six runs on the iOS 26 simulator — so `PingPayload`
composes these bytes itself and delegates only string escaping to Foundation.

`at` is the time of the **fix**, not the time of the POST. Added 2026-09-10 (D-12) because REQ-05
queues a ping that may be delivered a wake later: without it a ping drained on Tuesday arrives
indistinguishable from a fresh fix, and SC-02 explicitly accepts that lag, which means the receiver
has to be able to tell. A drained ping reports where the phone **was**, and when.

## Environment (names only — never values)
| Var / parameter | Source | Used by |
|-----------------|--------|---------|
| `webhook.url` | user-entered → Keychain | transport |
| `webhook.senderKey` | user-entered → Keychain | transport |
| `webhook.headerName` | user-entered → Keychain (default `Authorization`) | transport |
| `DEVELOPMENT_TEAM`, `PRODUCT_BUNDLE_IDENTIFIER` | local `Signing.xcconfig` (gitignored) | code signing |

**Fail fast — no fallback values.** Missing URL, key, or header: refuse to send and prompt for settings; never a default endpoint or empty key. A missing `Signing.xcconfig` fails the build naming the file.

## Forbidden
- Any third-party dependency manager or package.
- Continuous background GPS (`startUpdatingLocation` + `allowsBackgroundLocationUpdates`).
- Storing or logging the sender key, the webhook URL, or raw coordinates — **except** the two sanctioned stores described above: the offline queue file (D-12) and the single last-ping coordinate (D-16). Logs, analytics, `UserDefaults`, and the in-memory history remain off limits: the history list is session-only for exactly this reason.
- Committing `DEVELOPMENT_TEAM`, a bundle id, or a provisioning profile **into source or build
  configuration**. Scoped to `src/`, `project.yml`, `scripts/` and anything that ships — NOT to
  `.planning/` prose (D-14). A bundle id is not a secret and is public in any shipped build; the
  rule exists to keep signing identity out of the build, and phase 03's audit found the literal
  only in planning records, where naming it is how a decision stays auditable. The build-side
  rule is unchanged and still enforced: 03-11 proved `project.yml` carries no literal bundle id,
  and smoke's guard keeps it that way.
- Importing MapKit anywhere but `src/Triggers/MapKitTriggerLabelProvider.swift` (D-15). The
  framework is authorized for reverse geocoding only; a map view, a map tile, or MapKit types
  leaking into the ping path are outside what was allowed.
- Force-unwrapping a `CLLocation` or a network response.
- Liquid Glass behind body text, credential fields, or the primary action (chrome only — see `DESIGN.md`).
