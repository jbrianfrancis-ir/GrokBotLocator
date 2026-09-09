<!-- .planning/phases/NN-slug/NN-MM-SUMMARY.md — cap 1.5KB. Frontmatter first: others read only frontmatter. -->
---
plan: 01-11
status: complete
agent: executor/claude/sonnet
commits: [d5997ef, a78ec21]
deviations: []
human_checks: []
deferred: []
---
SettingsModel (`@Observable @MainActor`): urlText, senderKey, headerName (seeded
defaultHeaderName), hasStoredKey, status (idle/saved/error(String)); depends on
CredentialStore protocol only. load() fills url/headerName, never senderKey (D-10) --
hasStoredKey is the only trace. save() validates https url, non-empty key (or re-reads
the stored key via store.load() when untouched and hasStoredKey), non-empty header;
each failure is a field-specific .error, nothing written. clear() empties store, fields,
and hasStoredKey. Tests: FakeCredentialStore (in-memory, records last save) covers all
validation paths, load's D-10 behaviour, untouched-key re-read/preserve, clear, and the
default header. Verified: `./scripts/smoke.sh` -> TEST SUCCEEDED, 21 tests/5 suites,
"Suite SettingsModelTests passed" in log; `grep -rnE 'print\(|NSLog|os_log' src/Settings/`
exits 1 (no hits); secret scan on both staged diffs clean; all fixtures are `.invalid`
placeholders.
