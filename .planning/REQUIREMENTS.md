# Requirements

## Must have (v1)
- REQ-01: Settings stores webhook URL, sender key, header name in the Keychain — accept: survive relaunch; absent from a `UserDefaults` dump and from `strings` on the binary.
- REQ-02: "I'm here" button captures one fix and POSTs `{"lat","lng","accuracy_m","label"}` to the configured URL with the configured header — accept: stub server receives that exact JSON, `lat`/`lng` numeric; status shown to user.
- REQ-03: Optional label, remembered between pings, editable before sending — accept: type "Gallipoli", send, relaunch, field still reads "Gallipoli".
- REQ-04: Ping history list: timestamp, coordinates, label, outcome (sent / queued / failed + reason) — accept: one success and one forced failure give two rows with distinct outcomes.
- REQ-05: Failed or offline pings queue durably and retry when connectivity returns — accept: airplane mode → tap → "queued"; airplane off → flips to "sent" unattended; queue survives force-quit.
- REQ-06: Significant-change monitoring auto-pings after the device moves at least 500 m (fixed, not configurable) — accept: simulated route crossing 500 m, app backgrounded, delivers a ping; a 300 m move delivers none.
- REQ-07: Visit monitoring auto-pings on arrival somewhere the user lingers — accept: simulated visit event, app backgrounded, produces exactly one ping marked as an arrival.
- REQ-08: Geofence registers a region at the last ping, pings on exit, re-registers at the new location — accept: simulated exit fires one ping and registers a new region.
- REQ-09: Per-trigger on/off switches plus a minimum-interval rate limit with a hard 15 s floor enforcing SC-04 — accept: at the 60 s default, two trigger events 20 s apart produce one ping; the interval cannot be set below 15 s.
- REQ-10: Authorization requested at point of use with a purpose string; manual pings work at "When In Use", "Always" requested only when a trigger is enabled — accept: denying "Always" leaves the button working and explains what is unavailable.
- REQ-11: "Test connection" in settings sends a ping and surfaces the exact HTTP status and body — accept: a wrong key shows a visible 401/403, never a silent failure.
- REQ-12: Every screen meets `DESIGN.md` — Dynamic Type to AX5 without truncation, body text ≥ 20pt, tap targets ≥ 60pt, outcome shown as symbol + word + colour, light and dark both contrast-verified — accept: at AX5 in both appearances no text clips or overlaps, and the Accessibility Inspector audit reports no contrast or hit-target failures.

## Success criteria
- SC-01: A manual ping goes tap → confirmed delivery in under 10 s on a normal mobile connection.
- SC-02: Over a 7-day trip every ping is accounted for — delivered, or shown permanently failed with a reason. Zero silently dropped.
- SC-03: A full sightseeing day with all triggers on costs under 5% of battery.
- SC-04: No more than 4 pings per minute reach the routine (≥ 15 s spacing), counting manual and automatic together.
- SC-05: Fresh install → first successful ping in under 3 minutes, with URL, key, header the only inputs.
- SC-06: A user without reading glasses completes setup and sends a ping unaided, at the system's default text size, in direct sunlight.

## Assumptions
- iOS 26.0 minimum — confirmed: the target device runs iOS 26. This unlocks `CLMonitor` and Liquid Glass and drops all back-deployment work.
- Header is `Authorization: Bearer <key>` — confirmed by the user. Still editable in settings so the routine panel can change without a rebuild.
- Plain HTTPS POST, JSON body, one auth header — no request signing, no OAuth, no `Retry-After` handling.
- The sender key is long-lived and entered once; rotation means re-entering it.
- Any 2xx is accepted; 5xx and network errors retry with backoff; 401/403 surface immediately and never retry.
- Manual pings use the typed label; automatic pings reverse-geocode the locality via `CLGeocoder`, falling back to an empty label.
- REQ-09's default minimum interval is 60 s. SC-04 sets the hard floor (15 s); 60 s is a chosen default, adjustable in settings.
- Portrait iPhone, English only — no iPad, landscape, or localization work.

## Out of scope
See `PROJECT.md` → Out of scope. Nothing here builds a server, renders Grok's reply, or ships maps or trip content.
