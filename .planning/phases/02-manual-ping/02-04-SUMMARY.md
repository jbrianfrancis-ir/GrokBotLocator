---
plan: 02-04
status: complete
agent: executor/claude/claude-opus-5-1m
commits: [28ae23d, 4a22b52]
deviations: []
human_checks: []
deferred: []
---
Added src/Core/Transport/URLSessionPingTransport.swift: `struct URLSessionPingTransport:
PingTransport` with an injected `URLSession` (default `.shared`). `send` builds one POST to
`credentials.url`, 10s timeout, `Content-Type: application/json`, the sender key sent
verbatim in the credential's header name (no app-added "Bearer "), body = `payload.encoded()`.
A non-HTTP response throws `PingTransportError.notAnHTTPResponse` rather than force-unwrapping.
No retry/backoff/queue/logging — that's phase 03. tests/PingTransportTests.swift adds
`StubURLProtocol` (static state behind an `NSLock`, body read from `httpBodyStream` since
`URLProtocol` strips `httpBody`) on an ephemeral session; `@Suite(.serialized)` since all 5
tests share that static state. Covers: 200 returns status+body; POST shape/headers/body
(parsed-field equality primary, byte-equality against a second `encoded()` call secondary per
02-02's byte-stability); 204 empty body -> `""`; stubbed `URLError` throws something other
than `PingTransportError`; no `Authorization` header leaks in when the credential's header
name is `X-Test-Key`. Falsify-checked live: prefixing the header with "Bearer " fails the
header assertions as predicted; reverted. smoke.sh green at 4a22b52, 43 tests/8 suites.
