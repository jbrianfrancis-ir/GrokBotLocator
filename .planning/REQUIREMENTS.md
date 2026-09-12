# Requirements

## Must have (v1)
- REQ-01: Settings stores webhook URL, sender key, header name in the Keychain — accept: all three survive relaunch; url and header repopulate on screen while the key shows a "key saved" indicator and is never re-rendered (D-10); absent from a `UserDefaults` dump and from `strings` on the binary.
- REQ-02: "I'm here" button captures one fix and POSTs `{"lat","lng","accuracy_m","label","at"}` to the configured URL with the configured header — accept: stub server receives that exact JSON in that key order, `lat`/`lng` numeric, `at` the ISO-8601 time of the FIX not the POST; status shown to user. (`at` added 2026-09-10, D-12 — REQ-05 may deliver a ping a wake later, and the receiver has to be able to tell.)
- REQ-03: Optional label, remembered between pings, editable before sending — accept: type "Gallipoli", send, relaunch, field still reads "Gallipoli".
- REQ-04: Ping history list: timestamp, coordinates, label, outcome (sent / queued / failed + reason) — accept: one success and one forced failure give two rows with distinct outcomes.
- REQ-05: Failed or offline pings queue durably to disk and drain at the next opportunity the OS gives the app — connectivity returning while it is alive, a location-triggered wake, a manual launch, or a `BGAppRefreshTask` — accept: airplane mode → tap → "queued"; with the app open, airplane off → flips to "sent" unattended; force-quit then relaunch → the queued ping is still there and sends.
- REQ-06: Significant-change monitoring auto-pings after the device moves at least 500 m (fixed, not configurable) — accept: simulated route crossing 500 m, app backgrounded, delivers a ping; a 300 m move delivers none.
- REQ-07: Visit monitoring auto-pings on arrival somewhere the user lingers — accept: simulated visit event, app backgrounded, produces exactly one ping marked as an arrival.
- REQ-08: Geofence registers a region at the last ping, pings on exit, re-registers at the new location — accept: simulated exit fires one ping and registers a new region.
- REQ-09: Per-trigger on/off switches plus a minimum-interval rate limit with a hard 15 s floor enforcing SC-04 — accept: at the 60 s default, two trigger events 20 s apart produce one ping; the interval cannot be set below 15 s.
- REQ-10: Authorization requested at point of use with a purpose string; manual pings work at "When In Use", "Always" requested only when a trigger is enabled — accept: denying "Always" leaves the button working and explains what is unavailable.
- REQ-11: "Test connection" in settings sends a ping and surfaces the exact HTTP status and body — accept: a wrong key shows a visible 401/403, never a silent failure.
- REQ-12: Every screen meets `DESIGN.md` — Dynamic Type to AX5 without truncation, body text ≥ 17pt (was ≥ 20pt until D-13), tap targets ≥ 60pt, outcome shown as symbol + word + colour, light and dark both contrast-verified — accept: at AX5 in both appearances no text clips or overlaps, and the Accessibility Inspector audit reports no contrast or hit-target failures.

## Success criteria
- SC-01: A manual ping goes tap → confirmed delivery in under 10 s on a normal mobile connection.
- SC-02: Over a 7-day trip every ping is accounted for — delivered, or shown permanently failed with a reason. Zero silently dropped. Delivery may lag connectivity by one wake; loss is what this forbids, not latency.
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
- **HTTP 408 and 429 retry** (D-14): they mean "not now", not "not ever", and succeed on a later attempt. Every other 4xx (400, 404, 409, 410, 422, 499 …) is permanent — a wrong URL or a malformed body is not fixed by retrying. No `Retry-After` handling: 408/429 ride the app's own backoff.
- **A queued ping gives up 7 days after its FIRST attempt** (D-14), measured in elapsed time, not attempt count. This covers SC-02's 7-day trip with slack.
- **A ping that fails permanently while the app is not running is kept on disk with its reason until it has been shown, then deleted** (D-14). A background drain marks it; the next foreground drain reports and removes it. This is what makes SC-02's "shown permanently failed with a reason" true for a failure discovered while nobody was looking.
- Manual pings use the typed label; automatic pings reverse-geocode the locality, falling back to an empty label. **The geocoder is MapKit's `MKReverseGeocodingRequest`** (D-15, 2026-09-11): `CLGeocoder` is soft-deprecated at iOS 26.0 ("Use MapKit"), so the app does not build on it. The label is best-effort — an empty label is a normal outcome, never a reason to drop or delay a ping, and reverse geocoding is off the critical path for delivery.
- **Any reverse-geocoding failure yields an empty label** (D-19): a nil failable init, a thrown error, an empty result, a missing locality, a whitespace-only name, or the 3 s budget expiring. The app assumes NOTHING about `MKReverseGeocodingRequest`'s throttling or offline behaviour — the bound is held by construction, never by the API behaving. An empty label is a normal outcome and never delays or drops a ping.
- Reverse geocoding sends a coordinate to Apple's geocoding service. This is inherent to the feature, is not "storing or logging" under ARCHITECTURE's Forbidden entry, and is unrelated to the D-12 queue-file exception — but it is a real egress of location data and is recorded here so it is a known property, not a discovery.
- iOS gives no "wake when connectivity returns" primitive. A terminated app's queue drains on the next wake, not the instant signal comes back — this is an OS limit, not a design choice.
- The durability mechanism is the on-disk queue file, NOT a background `URLSession`: user force-quit cancels background transfers and the system will not relaunch a force-quit app.
- REQ-09's default minimum interval is 60 s. SC-04 sets the hard floor (15 s); 60 s is a chosen default, adjustable in settings.
- Portrait iPhone, English only — no iPad, landscape, or localization work.

## Out of scope
See `PROJECT.md` → Out of scope. Nothing here builds a server, renders Grok's reply, or ships maps or trip content.
