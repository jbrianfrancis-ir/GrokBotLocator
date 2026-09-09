# Roadmap

| NN | Phase | Goal (one line) | Requirements | Status |
|----|-------|-----------------|--------------|--------|
| 01 | Foundation & credentials | XcodeGen project, signing config, Keychain-backed settings screen, smoke script — the app builds, installs, and holds its webhook credentials | REQ-01, SC-05 | pending |
| 02 | Manual ping | Authorization flow, one-shot fix, payload encoder, POST, history list, test-connection — the "I'm here" button works end to end | REQ-02, REQ-03, REQ-04, REQ-10, REQ-11, SC-01 | pending |
| 03 | Durable delivery | Offline queue, backoff retry, connectivity observation, failure classification — no ping is lost on Italian roaming | REQ-05, SC-02 | pending |
| 04 | Automatic triggers | Significant-change, visits, `CLMonitor` geofences, per-trigger toggles, rate limit, reverse-geocoded labels | REQ-06, REQ-07, REQ-08, REQ-09, SC-03, SC-04 | pending |
