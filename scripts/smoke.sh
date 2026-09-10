#!/usr/bin/env bash
# The ARCHITECTURE-mandated smoke gate. Regenerates the Xcode project, builds for an
# available iOS 26 simulator, and runs the test bundle. Pass is exit 0 plus
# `** TEST SUCCEEDED **` and a non-zero Swift Testing count -- XCTest's own
# "Executed N tests" line is always 0 under Swift Testing and proves nothing.
set -euo pipefail

cd "$(dirname "$0")/.."

if [[ ! -f Signing.xcconfig ]]; then
    echo "Signing.xcconfig is missing - copy the .example and set DEVELOPMENT_TEAM and PRODUCT_BUNDLE_IDENTIFIER" >&2
    exit 1
fi

echo "==> type-scale guard: no sub-17pt font literal or raw system-size call outside DSTypography"
EXEMPT="src/Core/DesignSystem/DSTypography.swift"
GUARD_HITS=$(grep -rnE \
    -e '\.font\([[:space:]]*\.system\([[:space:]]*size:' \
    -e 'size:[[:space:]]*-?([0-9]|1[0-6])(\.[0-9]+)?\b' \
    src --include='*.swift' 2>/dev/null | grep -v "^${EXEMPT}:" || true)

if [[ -n "$GUARD_HITS" ]]; then
    echo "type-scale guard failed -- font-size literal below 17pt or raw .font(.system(size:)) outside DSTypography:" >&2
    echo "$GUARD_HITS" >&2
    exit 1
fi

echo "==> xcodegen generate"
xcodegen generate

echo "==> resolving simulator UDID"
if ! UDID=$(./scripts/simulator-udid.sh); then
    echo "smoke.sh: could not resolve an iOS 26 simulator UDID (see message above)" >&2
    exit 1
fi

DERIVED_DATA="${SMOKE_DERIVED_DATA:-build/dd-smoke}"
LOG_FILE="${DERIVED_DATA%/}.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "==> xcodebuild test (destination udid: $UDID)"
# `set +e` around the pipeline, NOT `|| true`: bash refreshes PIPESTATUS after every
# command, so `|| true` runs `true` and overwrites PIPESTATUS[0] with 0 -- making
# BUILD_STATUS unconditionally 0 and the exit-code check below dead code.
set +e
xcodebuild test \
    -scheme GrokBotLocator \
    -destination "platform=iOS Simulator,id=$UDID" \
    -derivedDataPath "$DERIVED_DATA" \
    2>&1 | tee "$LOG_FILE"
BUILD_STATUS=${PIPESTATUS[0]}
set -e

if [[ "$BUILD_STATUS" -ne 0 ]]; then
    echo "==> xcodebuild exited $BUILD_STATUS; tail of $LOG_FILE:" >&2
    tail -n 40 "$LOG_FILE" >&2
    exit 1
fi

if ! grep -q '\*\* TEST SUCCEEDED \*\*' "$LOG_FILE"; then
    echo "==> ** TEST SUCCEEDED ** not found in $LOG_FILE; tail:" >&2
    tail -n 40 "$LOG_FILE" >&2
    exit 1
fi

if ! grep -qE 'Test run with [1-9][0-9]* test' "$LOG_FILE"; then
    echo "==> no non-zero Swift Testing count (\"Test run with N test(s)\") found in $LOG_FILE; tail:" >&2
    tail -n 40 "$LOG_FILE" >&2
    exit 1
fi

echo "==> smoke passed"
