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

echo "==> location guard: no requestAlwaysAuthorization/startUpdatingLocation/allowsBackgroundLocationUpdates, and CLLocationManager/CLLocationUpdate confined to CoreLocationFixProvider.swift"
LOCATION_PROVIDER="src/Core/Location/CoreLocationFixProvider.swift"

FORBIDDEN_API_HITS=$(grep -rnE \
    'requestAlwaysAuthorization|startUpdatingLocation|allowsBackgroundLocationUpdates' \
    src --include='*.swift' 2>/dev/null || true)

if [[ -n "$FORBIDDEN_API_HITS" ]]; then
    echo "location guard failed -- requestAlwaysAuthorization/startUpdatingLocation/allowsBackgroundLocationUpdates is not allowed this phase (ARCHITECTURE Forbidden; Always is phase 04's to add deliberately):" >&2
    echo "$FORBIDDEN_API_HITS" >&2
    exit 1
fi

CORELOCATION_HITS=$(grep -rnE \
    'CLLocationManager|CLLocationUpdate' \
    src --include='*.swift' 2>/dev/null | grep -v "^${LOCATION_PROVIDER}:" || true)

if [[ -n "$CORELOCATION_HITS" ]]; then
    echo "location guard failed -- CLLocationManager/CLLocationUpdate must appear only in ${LOCATION_PROVIDER} (views never touch CLLocationManager):" >&2
    echo "$CORELOCATION_HITS" >&2
    exit 1
fi

echo "==> UserDefaults guard: the UserDefaults API confined to PingLabelStore.swift"
LABEL_STORE="src/Ping/PingLabelStore.swift"

# Matches the UserDefaults API, not the UserDefaultsPingLabelStore type name (legal at the
# composition root) and not doc comments. PingLabelStore.swift's own header claims this guard
# exists; before 2026-09-10 it did not, which is why the claim is now enforced rather than
# asserted. ARCHITECTURE: credentials live only in the Keychain -- a typed label is neither a
# credential nor a coordinate, so one caller is allowed and a second needs a decision.
# Strips the allowed type name from each line BEFORE looking for the API, rather than dropping
# any line that mentions it: a line-level `grep -v` let a second real caller hide beside the
# type name (`UserDefaultsPingLabelStore(); UserDefaults.standard.set(...)`), which the
# phase-02 verifier caught by probing it live.
USERDEFAULTS_HITS=$(grep -rn 'UserDefaults' src --include='*.swift' 2>/dev/null \
    | grep -v "^${LABEL_STORE}:" \
    | grep -vE '^[^:]*:[0-9]+: *(///|//|\*)' \
    | sed 's/UserDefaultsPingLabelStore//g' \
    | grep 'UserDefaults' || true)

if [[ -n "$USERDEFAULTS_HITS" ]]; then
    echo "UserDefaults guard failed -- the UserDefaults API must appear only in ${LABEL_STORE} (a second caller is a decision, not a detail):" >&2
    echo "$USERDEFAULTS_HITS" >&2
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
