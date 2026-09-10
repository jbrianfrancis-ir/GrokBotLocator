---
plan: 02-01
status: complete
agent: executor/claude/claude-opus-5
commits: [e2e5393, 237f205]
deviations: []
human_checks: []
deferred: []
---
Added the relative-order tripwire to tests/DynamicTypeScalingTests.swift: tokenOrderAtDefaultSize
(strict ascending at .large: secondary<body<actionLabel<screenTitle) and tokenOrderAtAX5IsPinned
(measured order at .accessibility5: secondary<body<screenTitle<actionLabel — the accepted
actionLabel>screenTitle inversion, per 2026-09-10 15:30 decision). tokenHeightsAtBothSizes prints
all eight heights (`token heights — ...`) into the smoke log. Measured via the harness, not
assumed: large 21/24/34/41, AX5 59/67/79/70 (secondary/body/actionLabel/screenTitle). Suite doc
comment extended with the 15:30 context so the AX5 order doesn't read as a bug. DSTypography.swift
untouched — all eight baseline grep counts confirmed 1 before and after. ./scripts/smoke.sh green
both times (25 tests, 5 suites).
