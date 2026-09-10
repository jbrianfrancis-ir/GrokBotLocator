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
# `.system(size:` is matched on its OWN line, not only after `.font(`: grep is line-based, so
# `Text("x").font(\n    .system(size: 20)\n)` walked straight past the anchored pattern. Same for
# `Font.system(size:)` and `UIFont.systemFont(ofSize:)`, neither of which mentions `.font(`.
GUARD_HITS=$(grep -rnE \
    -e '\.system\([[:space:]]*size:' \
    -e 'Font\.system\(' \
    -e 'UIFont\.systemFont\(' \
    -e 'ofSize:[[:space:]]*-?([0-9]|1[0-6])(\.[0-9]+)?\b' \
    -e 'size:[[:space:]]*-?([0-9]|1[0-6])(\.[0-9]+)?\b' \
    src --include='*.swift' 2>/dev/null | grep -v "^${EXEMPT}:" || true)

if [[ -n "$GUARD_HITS" ]]; then
    echo "type-scale guard failed -- font-size literal below 17pt or raw .font(.system(size:)) outside DSTypography:" >&2
    echo "$GUARD_HITS" >&2
    exit 1
fi

echo "==> location guard: no requestAlwaysAuthorization/startUpdatingLocation/allowsBackgroundLocationUpdates, and CLLocationManager/CLLocationUpdate confined to CoreLocationFixProvider.swift"
LOCATION_PROVIDER="src/Core/Location/CoreLocationFixProvider.swift"

# `CLBackgroundActivitySession` is the modern way to keep location alive in the background -- it
# is the ARCHITECTURE-Forbidden behaviour under a name none of the other patterns mention.
FORBIDDEN_API_HITS=$(grep -rnE \
    'requestAlwaysAuthorization|startUpdatingLocation|allowsBackgroundLocationUpdates|CLBackgroundActivitySession' \
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
# `@AppStorage` and `@SceneStorage` write to UserDefaults without containing the string, so the
# credential this guard exists to keep OUT of UserDefaults could be declared in one line and the
# guard would report nothing. ARCHITECTURE: credentials live only in the Keychain.
USERDEFAULTS_HITS=$(grep -rnE 'UserDefaults|@AppStorage|@SceneStorage' src --include='*.swift' 2>/dev/null \
    | grep -v "^${LABEL_STORE}:" \
    | grep -vE '^[^:]*:[0-9]+: *(///|//|\*)' \
    | sed 's/UserDefaultsPingLabelStore//g' \
    | grep -E 'UserDefaults|@AppStorage|@SceneStorage' || true)

if [[ -n "$USERDEFAULTS_HITS" ]]; then
    echo "UserDefaults guard failed -- the UserDefaults API must appear only in ${LABEL_STORE} (a second caller is a decision, not a detail):" >&2
    echo "$USERDEFAULTS_HITS" >&2
    exit 1
fi

echo "==> queue-store guard: FileManager/file-writing APIs confined to PingQueueStore.swift, import Network confined to Connectivity.swift"
QUEUE_STORE="src/Queue/PingQueueStore.swift"
CONNECTIVITY="src/Queue/Connectivity.swift"

# D-12 sanctioned PingQueueStore.swift as the ONE coordinate store, on exactly four conditions
# (protected, backup-excluded, deleted on delivery, never copied elsewhere). A second writer
# using these APIs is a decision, not a detail -- same shape as the UserDefaults guard above,
# including dropping comment-only lines first (a whole-file presence grep counts doc-comment
# text, .planning/LEARNINGS.md) rather than a whole-line `grep -v`, which a real call could hide
# beside on the same line.
QUEUE_STORE_HITS=$(grep -rnE \
    'FileManager|\.write\(to:|URLResourceValues|isExcludedFromBackup|completeFileProtectionUnlessOpen' \
    src --include='*.swift' 2>/dev/null \
    | grep -v "^${QUEUE_STORE}:" \
    | grep -vE '^[^:]*:[0-9]+: *(///|//|\*)' || true)

if [[ -n "$QUEUE_STORE_HITS" ]]; then
    echo "queue-store guard failed -- the queue file is the ONE sanctioned coordinate store (D-12); a second writer is a decision, not a detail:" >&2
    echo "$QUEUE_STORE_HITS" >&2
    exit 1
fi

NETWORK_IMPORT_HITS=$(grep -rnE '^import Network$' src --include='*.swift' 2>/dev/null \
    | grep -v "^${CONNECTIVITY}:" || true)

if [[ -n "$NETWORK_IMPORT_HITS" ]]; then
    echo "queue-store guard failed -- import Network must appear only in ${CONNECTIVITY}:" >&2
    echo "$NETWORK_IMPORT_HITS" >&2
    exit 1
fi

echo "==> queue-protection guard: ${QUEUE_STORE} applies both completeFileProtectionUnlessOpen and isExcludedFromBackup on non-comment lines"

# A whole-file presence grep counts comment text (.planning/LEARNINGS.md: a phase-01 guard read
# 5 where the answer was 1). Strip comment lines from THIS file's own hits before checking
# either protection is actually applied in code, not just described in the header doc comment.
QUEUE_STORE_NONCOMMENT_HITS=$(grep -nE 'completeFileProtectionUnlessOpen|isExcludedFromBackup' "$QUEUE_STORE" 2>/dev/null \
    | grep -vE '^[0-9]+: *(///|//|\*)' || true)

if ! echo "$QUEUE_STORE_NONCOMMENT_HITS" | grep -q 'completeFileProtectionUnlessOpen'; then
    echo "queue-protection guard failed -- ${QUEUE_STORE} does not apply .completeFileProtectionUnlessOpen on a non-comment line (D-12 sanctioned the file only as protected; losing this voids the exception):" >&2
    exit 1
fi

if ! echo "$QUEUE_STORE_NONCOMMENT_HITS" | grep -q 'isExcludedFromBackup'; then
    echo "queue-protection guard failed -- ${QUEUE_STORE} does not apply isExcludedFromBackup on a non-comment line (D-12 sanctioned the file only as backup-excluded; losing this voids the exception):" >&2
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

echo "==> background-identifier guard: the BUILT Info.plist carries a resolved, non-placeholder BGTaskSchedulerPermittedIdentifiers[0] ending in .queue-drain"
# Derived from $DERIVED_DATA, never a literal: DERIVED_DATA above is
# ${SMOKE_DERIVED_DATA:-build/dd-smoke}, and every plan in this phase overrides
# SMOKE_DERIVED_DATA with its own path, so a hard-coded build/dd-smoke/... would point at a
# directory this run never created. SceneBuilder has no conditional form, so scene registration
# for this identifier is unconditional (see QueueDrainTask's doc comment) -- this guard, reading
# the BUILT product, is what actually keeps an empty identifier out of a shipped build.
APP_PLIST="$DERIVED_DATA/Build/Products/Debug-iphonesimulator/GrokBotLocator.app/Info.plist"

if [[ ! -f "$APP_PLIST" ]]; then
    echo "background-identifier guard failed -- could not check: built Info.plist not found at ${APP_PLIST}" >&2
    exit 1
fi

BG_IDENTIFIER=$(/usr/libexec/PlistBuddy -c "Print :BGTaskSchedulerPermittedIdentifiers:0" "$APP_PLIST" 2>/dev/null || true)

if [[ -z "$BG_IDENTIFIER" ]]; then
    echo "background-identifier guard failed -- ${APP_PLIST} has no BGTaskSchedulerPermittedIdentifiers[0] (an empty identifier must never reach a shipped build):" >&2
    exit 1
fi

if [[ "$BG_IDENTIFIER" == *'$('* ]]; then
    echo "background-identifier guard failed -- ${APP_PLIST}'s BGTaskSchedulerPermittedIdentifiers[0] is an unresolved build-setting reference, not a resolved identifier: ${BG_IDENTIFIER}" >&2
    exit 1
fi

if [[ "$BG_IDENTIFIER" != *.queue-drain ]]; then
    echo "background-identifier guard failed -- ${APP_PLIST}'s BGTaskSchedulerPermittedIdentifiers[0] does not end in .queue-drain: ${BG_IDENTIFIER}" >&2
    exit 1
fi

echo "==> smoke passed"
