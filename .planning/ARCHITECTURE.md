# Architecture constraints

## Stack
| What | Exactly | Version |
|------|---------|---------|
| Platform | iOS (iPhone, portrait) | 18.0 min deployment target |
| Language | Swift, strict concurrency | 6.3.3 |
| Toolchain | Xcode | 26.6 (17F113) |
| UI | SwiftUI + Observation (`@Observable`) | iOS 18 SDK |
| Project file | XcodeGen from `project.yml` | 2.46.0 |

## Principles
- **Zero third-party dependencies.** iOS SDK only; any SPM/CocoaPods/Carthage entry is a violation.
- **Credentials live only in the Keychain** — never in source, `project.yml`, `Info.plist`, `UserDefaults`, or a log line.
- **No ping is silently dropped.** Every send succeeds, is durably queued, or is recorded as failed with a user-visible reason.
- **Fully usable at "When In Use".** Manual pings work without `Always`; `Always` only unlocks automatic triggers.
- **Transport and storage are protocol-backed and injected** — delivery is testable without a device or live webhook.

## Smoke
- **Command**: `./scripts/smoke.sh` — `xcodegen generate`, build for an iOS 18 simulator, run the test bundle.
- **Pass looks like**: exit 0; `** TEST SUCCEEDED **`; encoder test asserts `{"lat":<num>,"lng":<num>,"accuracy_m":<num>,"label":<string>}`.

## Frameworks & libraries (all iOS 18 SDK, no third-party)
- CoreLocation — fixes, significant-change, visits, `CLMonitor` regions
- Security (Keychain) — webhook URL / key / header storage
- Foundation `URLSession` — webhook POST
- Network `NWPathMonitor` — connectivity observation for retry
- Swift Testing (bundled with Xcode 26.6) — unit tests

## Architecture & patterns
- App code under `src/`, tests under `tests/`; `project.yml` and `scripts/` at the root.
- Feature folders under `src/` (`Settings/`, `Ping/`, `Triggers/`, `Queue/`) plus `Core/` for Keychain/payload/transport.
- Offline queue is a `Codable` array in Application Support via `FileManager` — no SwiftData, no Core Data.
- All location work sits in one actor-isolated coordinator; views never touch `CLLocationManager`.

## Infrastructure (Azure / Aspire resources)
- **None.** No server, no deployable surface. The webhook receiver is Grok-hosted; the app ships via Xcode/TestFlight.

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
- Storing or logging the sender key, the webhook URL, or raw coordinates.
- Committing `DEVELOPMENT_TEAM`, a bundle id, or a provisioning profile.
- Force-unwrapping a `CLLocation` or a network response.
