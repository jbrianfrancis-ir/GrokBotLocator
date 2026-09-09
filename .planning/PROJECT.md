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
| D-06 | Webhook URL, sender key, and header name are all user-entered at runtime | The key must never enter the repo; `Authorization: Bearer` is the confirmed default, editable so a panel change needs no rebuild | 2026-09-09 |
| D-07 | iOS 26.0 minimum deployment target | The only target device runs iOS 26; unlocks `CLMonitor` and Liquid Glass, and removes all back-deployment branching | 2026-09-09 |
| D-08 | Accessibility-first design system in `DESIGN.md`, self-authored | The app must be readable without reading glasses in bright sun; a linked Claude Design system was not needed for two screens | 2026-09-09 |
| D-09 | The on-disk queue file is the durability mechanism; `URLSessionConfiguration.background` is not the primary send path | Research confirmed user force-quit cancels background transfers and the system will not relaunch a force-quit app, so background URLSession cannot satisfy REQ-05 on its own | 2026-09-09 |
| D-10 | The saved sender key is never re-rendered; settings shows a "key saved" indicator instead | Avoids putting a live credential on screen where it can be shoulder-surfed or screenshotted; url and header still repopulate | 2026-09-09 |
| D-11 | Sign with the Informative Research team (signing only); app identity stays personal | A paid team gives year-long provisioning profiles; a free personal team expires in 7 days and would strand the app mid-trip | 2026-09-09 |
