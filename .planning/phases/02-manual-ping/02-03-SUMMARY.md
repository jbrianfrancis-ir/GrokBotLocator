---
plan: 02-03
status: complete
agent: executor/claude/claude-opus-5-1m
commits: [bfbbe36, 2324d9d]
deviations: []
human_checks: []
deferred: []
---
Added src/Core/Transport/PingTransport.swift: PingResponse (statusCode, body), PingDisposition
(sent/permanentFailure/retryable), the PingTransport protocol, and PingClassifier — a pure
function over a status code. 2xx -> sent; 401/403 -> permanentFailure naming Settings;
remaining 4xx -> permanentFailure naming the URL (REQUIREMENTS.md backstop); 5xx ->
retryable; outside 200...599 -> permanentFailure naming the code; thrown transport error ->
retryable, never interpolated. tests/PingClassifierTests.swift pins every branch including
the 4xx backstop and the reason-string shape (ends in ".", >=20 chars). Credential-leak grep
scoped to PingTransport.swift per the plan (folder-wide would break on 02-04's legitimate
setValue(credentials.senderKey, ...) call). Falsify-checked live: flipping 500...599 to
.permanentFailure fails serverErrorsAreRetryable as predicted; reverted before final commit.
smoke.sh green at 2324d9d.
