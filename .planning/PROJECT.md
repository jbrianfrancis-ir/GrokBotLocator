# GrokBotLocator

## What
An iPhone app that sends the phone's current location to a Grok Bot webhook routine, so Grok can answer with a "you're near X" tip against a Puglia trip guide. Grok has no iOS SDK and no location API — a webhook POST is the only channel that exists. Single user, single device: the person carrying the phone around Puglia.

## Core value
Tapping "I'm here" in Puglia reliably delivers `lat`/`lng` to the Grok routine — including on spotty roaming, where the ping is queued and sent the moment signal returns.

## Out of scope
- Any server, cloud, or Azure component — the webhook receiver is Grok's
- Rendering Grok's reply inside the app; the tip arrives in the Grok chat
- Maps, trip-guide content, or offline POI data
- Sharing location with other people; multi-user or multi-device sync
- Android, watchOS, widgets, Live Activities
- Continuous breadcrumb tracking or location-history export

## Key decisions
| ID | Decision | Why | Date |
|----|----------|-----|------|
| D-01 | Native SwiftUI app, not an iOS Shortcut | Background triggers, Keychain storage, and offline retry are all impossible in a Shortcut | 2026-09-09 |
| D-02 | All three automatic triggers (significant-change, visits, geofence exit) plus a manual button | User wants coverage without carrying the phone in hand; each trigger catches a different movement pattern | 2026-09-09 |
| D-03 | Paid Apple Developer account for signing | A free personal team's 7-day signing expiry would strand the app mid-trip with no Mac nearby | 2026-09-09 |
| D-04 | `deploy.tool: null` — no deployable surface | The app ships to the device via Xcode/TestFlight and the webhook receiver is Grok-hosted; there is nothing to provision, harden, or release to Azure | 2026-09-09 |
| D-05 | Zero third-party dependencies, iOS SDK only | Keeps the build reproducible and signing trivial; every capability needed exists in CoreLocation, Security, Foundation, and Network | 2026-09-09 |
| D-06 | Webhook URL, sender key, and header name are all user-entered at runtime | The key must never enter the repo, and the routine panel's header name is not yet confirmed — configurability removes it as a blocker | 2026-09-09 |
