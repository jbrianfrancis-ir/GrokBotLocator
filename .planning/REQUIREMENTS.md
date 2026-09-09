# Requirements

## Must have (v1)
- REQ-01: Settings stores webhook URL, sender key, header name in the Keychain — accept: survive relaunch; absent from a `UserDefaults` dump and from `strings` on the binary.
- REQ-02: "I'm here" button captures one fix and POSTs `{"lat","lng","accuracy_m","label"}` to the configured URL with the configured header — accept: stub server receives that exact JSON, `lat`/`lng` numeric; status shown to user.
- REQ-03: Optional label, remembered between pings, editable before sending — accept: type "Gallipoli", send, relaunch, field still reads "Gallipoli".
- REQ-04: Ping history list: timestamp, coordinates, label, outcome (sent / queued / failed + reason) — accept: one success and one forced failure give two rows with distinct outcomes.
- REQ-05: Failed or offline pings queue durably and retry when connectivity returns — accept: airplane mode → tap → "queued"; airplane off → flips to "sent" unattended; queue survives force-quit.
- REQ-06: Significant-change monitoring auto-pings after the device moves at least [NEEDS CLARIFICATION: fixed 500 m per Grok's suggestion, or user-configurable defaulting to 500 m?] — accept: simulated route crossing the threshold, app backgrounded, delivers a ping.
- REQ-07: Visit monitoring auto-pings on arrival somewhere the user lingers — accept: simulated visit event, app backgrounded, produces exactly one ping marked as an arrival.
- REQ-08: Geofence registers a region at the last ping, pings on exit, re-registers at the new location — accept: simulated exit fires one ping and registers a new region.
- REQ-09: Per-trigger on/off switches plus a minimum-interval rate limit — accept: limit 15 min, two trigger events 2 min apart produce one ping.
- REQ-10: Authorization requested at point of use with a purpose string; manual pings work at "When In Use", "Always" requested only when a trigger is enabled — accept: denying "Always" leaves the button working and explains what is unavailable.
- REQ-11: "Test connection" in settings sends a ping and surfaces the exact HTTP status and body — accept: a wrong key shows a visible 401/403, never a silent failure.

## Success criteria
- SC-01: A manual ping goes tap → confirmed delivery in under 10 s on a normal mobile connection.
- SC-02: Over a 7-day trip every ping is accounted for — delivered, or shown permanently failed with a reason. Zero silently dropped.
- SC-03: A full sightseeing day with all triggers on costs under 5% of battery.
- SC-04: Triggers deliver no more than [NEEDS CLARIFICATION: what rate does the routine tolerate before it is noise — 6/hour, 20/day, other?] pings.
- SC-05: Fresh install → first successful ping in under 3 minutes, with URL, key, header the only inputs.

## Assumptions
- iOS 18.0 minimum; the phone runs iOS 18+. Wrong here means the app will not install — confirm before phase 1 executes.
- Header defaults to `Authorization: Bearer <key>` until the routine panel says otherwise; it is editable in settings, so a wrong default is a typing correction, not rework.
- Plain HTTPS POST, JSON body, one auth header — no request signing, no OAuth, no `Retry-After` handling.
- The sender key is long-lived and entered once; rotation means re-entering it.
- Any 2xx is accepted; 5xx and network errors retry with backoff; 401/403 surface immediately and never retry.
- Manual pings use the typed label; automatic pings reverse-geocode the locality via `CLGeocoder`, falling back to an empty label.
- Portrait iPhone, English only — no iPad, landscape, or localization work.

## Out of scope
See `PROJECT.md` → Out of scope. Nothing here builds a server, renders Grok's reply, or ships maps or trip content.
