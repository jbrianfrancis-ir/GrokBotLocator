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

echo "==> type-scale guard: no sub-15pt font literal or raw system-size call outside DSTypography"
EXEMPT="src/Core/DesignSystem/DSTypography.swift"
# `.system(size:` is matched on its OWN line, not only after `.font(`: grep is line-based, so
# `Text("x").font(\n    .system(size: 20)\n)` walked straight past the anchored pattern. Same for
# `Font.system(size:)` and `UIFont.systemFont(ofSize:)`, neither of which mentions `.font(`.
GUARD_HITS=$(grep -rnE \
    -e '\.system\([[:space:]]*size:' \
    -e 'Font\.system\(' \
    -e 'UIFont\.systemFont\(' \
    -e 'ofSize:[[:space:]]*-?([0-9]|1[0-4])(\.[0-9]+)?\b' \
    -e 'size:[[:space:]]*-?([0-9]|1[0-4])(\.[0-9]+)?\b' \
    src --include='*.swift' 2>/dev/null | grep -v "^${EXEMPT}:" || true)

if [[ -n "$GUARD_HITS" ]]; then
    echo "type-scale guard failed -- font-size literal below 15pt or raw .font(.system(size:)) outside DSTypography:" >&2
    echo "$GUARD_HITS" >&2
    exit 1
fi

echo "==> location guard: continuous-GPS APIs banned outright; Always in LocationDelegateProxy only; CLLocationManager in 2 files; CLMonitor in GeofenceMonitor"
FIX_PROVIDER="src/Core/Location/CoreLocationFixProvider.swift"
ALWAYS_FILE="src/Triggers/LocationDelegateProxy.swift"
GEOFENCE_MONITOR="src/Triggers/GeofenceMonitor.swift"

# 1. The unconditional ban -- NO file exemption and, deliberately, NO comment-strip. A guard with
# no exemption at all is the one shape nothing can escape. All three are ARCHITECTURE's Forbidden
# continuous-GPS pattern; `requestAlwaysAuthorization` is no longer in this list because phase 04
# is now permitted to call it, in exactly one file (check 2 below).
# `CLBackgroundActivitySession` stays banned by an explicit ruling, not by omission: it is a
# When-In-Use convenience (RESEARCH Q3) -- it keeps a when-in-use app alive in the background and
# "is not a substitute for Always authorization and does not itself enable the terminated-app
# relaunch behavior REQ-06/07/08 depend on". What phase 04 may need is `CLServiceSession`
# (RESEARCH Q2/Q5), a DIFFERENT type with a different spelling that this pattern does not match,
# so keeping the ban costs phase 04 nothing.
FORBIDDEN_API_HITS=$(grep -rnE \
    'startUpdatingLocation|allowsBackgroundLocationUpdates|CLBackgroundActivitySession' \
    src --include='*.swift' 2>/dev/null || true)

if [[ -n "$FORBIDDEN_API_HITS" ]]; then
    echo "location guard failed -- startUpdatingLocation/allowsBackgroundLocationUpdates/CLBackgroundActivitySession are not allowed anywhere in src/ (ARCHITECTURE Forbidden continuous-GPS pattern; Always is permitted only in ${ALWAYS_FILE}, these three are permitted nowhere, and CLServiceSession -- not CLBackgroundActivitySession -- is what phase 04 may use):" >&2
    echo "$FORBIDDEN_API_HITS" >&2
    exit 1
fi

# 2. Always, in one file. Anchored on grep's own `path:lineno:` prefix -- never a filter that
# drops any line merely MENTIONING the filename -- because LEARNINGS records that exact hole: the
# old UserDefaults guard dropped whole lines containing an allowed token, so a real violation
# beside it on the same line passed clean. A `^path:` anchor keys off which FILE grep reported the
# hit from, which no line's content can forge. Deliberately no comment-strip here: a comment-only
# strip would ALSO drop a violation placed on the same line as a comment mentioning this filename
# (the probe for this exact shape proved it), which defeats the one thing this anchor exists to
# catch.
ALWAYS_HITS=$(grep -rnE 'requestAlwaysAuthorization' src --include='*.swift' 2>/dev/null \
    | grep -v "^${ALWAYS_FILE}:" || true)

if [[ -n "$ALWAYS_HITS" ]]; then
    echo "location guard failed -- requestAlwaysAuthorization must appear only in ${ALWAYS_FILE}:" >&2
    echo "$ALWAYS_HITS" >&2
    exit 1
fi

# 3. CLLocationManager/CLLocationUpdate, in two files -- CoreLocationFixProvider.swift (the
# original home) plus LocationDelegateProxy.swift (phase 04's Always caller). Same `^path:`
# anchors as check 2. Nothing else may name either.
CORELOCATION_HITS=$(grep -rnE \
    'CLLocationManager|CLLocationUpdate' \
    src --include='*.swift' 2>/dev/null \
    | grep -v "^${FIX_PROVIDER}:" \
    | grep -v "^${ALWAYS_FILE}:" || true)

if [[ -n "$CORELOCATION_HITS" ]]; then
    echo "location guard failed -- CLLocationManager/CLLocationUpdate must appear only in ${FIX_PROVIDER} or ${ALWAYS_FILE} (views never touch CLLocationManager):" >&2
    echo "$CORELOCATION_HITS" >&2
    exit 1
fi

# 4. CLMonitor, in one file. Strip the concrete type token FIRST -- the composition root writes
# `let geofence = CLMonitorGeofence()`, a CODE line that comment-stripping does not reach and that
# the bare pattern would match -- exactly the shape the UserDefaults guard already uses for
# UserDefaultsPingLabelStore. Comment-strip as well (unlike checks 2/3, no probe exercises a
# comment-disguised CLMonitor call, and `CLMonitor` -- unlike `requestAlwaysAuthorization` -- is
# a plausible thing for an explanatory doc comment to name).
CLMONITOR_HITS=$(grep -rnE 'CLMonitor' src --include='*.swift' 2>/dev/null \
    | grep -v "^${GEOFENCE_MONITOR}:" \
    | grep -vE '^[^:]*:[0-9]+: *(///|//|\*)' \
    | sed 's/CLMonitorGeofence//g' \
    | grep -E 'CLMonitor' || true)

if [[ -n "$CLMONITOR_HITS" ]]; then
    echo "location guard failed -- CLMonitor must appear only in ${GEOFENCE_MONITOR}:" >&2
    echo "$CLMONITOR_HITS" >&2
    exit 1
fi

echo "==> MapKit guard: MapKit confined to MapKitTriggerLabelProvider.swift (D-15 authorizes reverse geocoding only)"
MAPKIT_PROVIDER="src/Triggers/MapKitTriggerLabelProvider.swift"

# D-15 authorizes MapKit for reverse geocoding ONLY, confined to one file (ARCHITECTURE
# Forbidden). Same `^path:` anchor as the Always check above, and for the same reason no
# comment-strip: a comment naming this filename beside a real MapKit reference on the same line
# must still be caught, not waved through as "doc comment".
MAPKIT_IMPORT_HITS=$(grep -rnE '^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*import[[:space:]]+MapKit[[:space:]]*$' src --include='*.swift' 2>/dev/null \
    | grep -v "^${MAPKIT_PROVIDER}:" || true)

if [[ -n "$MAPKIT_IMPORT_HITS" ]]; then
    echo "MapKit guard failed -- import MapKit must appear only in ${MAPKIT_PROVIDER} (D-15 authorizes reverse geocoding only):" >&2
    echo "$MAPKIT_IMPORT_HITS" >&2
    exit 1
fi

# MapKit TYPES, not only the import line -- D-15's Forbidden entry bans map views, map tiles and
# MapKit types in the ping path, and a type can reach a file through a re-export without an
# `import MapKit` of its own.
MAPKIT_TYPE_HITS=$(grep -rnE '\bMK[A-Z][A-Za-z]*' src --include='*.swift' 2>/dev/null \
    | grep -v "^${MAPKIT_PROVIDER}:" || true)

if [[ -n "$MAPKIT_TYPE_HITS" ]]; then
    echo "MapKit guard failed -- MapKit types must appear only in ${MAPKIT_PROVIDER} (D-15 authorizes reverse geocoding only):" >&2
    echo "$MAPKIT_TYPE_HITS" >&2
    exit 1
fi

echo "==> UserDefaults guard: the UserDefaults API confined to PingLabelStore.swift and TriggerSettingsStore.swift"
LABEL_STORE="src/Ping/PingLabelStore.swift"
TRIGGER_SETTINGS_STORE="src/Settings/TriggerSettingsStore.swift"

# Matches the UserDefaults API, not the UserDefaultsPingLabelStore/UserDefaultsTriggerSettingsStore
# type names (legal at the composition root) and not doc comments. PingLabelStore.swift's own
# header claims this guard exists; before 2026-09-10 it did not, which is why the claim is now
# enforced rather than asserted. ARCHITECTURE: credentials live only in the Keychain -- a typed
# label, a per-trigger on/off switch and a minimum-interval number are neither a credential nor a
# coordinate, so two callers are allowed and a third needs a decision.
# Strips the allowed type names from each line BEFORE looking for the API, rather than dropping
# any line that mentions them: a line-level `grep -v` let a second real caller hide beside the
# type name (`UserDefaultsPingLabelStore(); UserDefaults.standard.set(...)`), which the
# phase-02 verifier caught by probing it live.
# `@AppStorage` and `@SceneStorage` write to UserDefaults without containing the string, so the
# credential this guard exists to keep OUT of UserDefaults could be declared in one line and the
# guard would report nothing. ARCHITECTURE: credentials live only in the Keychain.
USERDEFAULTS_HITS=$(grep -rnE 'UserDefaults|@AppStorage|@SceneStorage' src --include='*.swift' 2>/dev/null \
    | grep -v "^${LABEL_STORE}:" \
    | grep -v "^${TRIGGER_SETTINGS_STORE}:" \
    | grep -vE '^[^:]*:[0-9]+: *(///|//|\*)' \
    | sed -e 's/UserDefaultsPingLabelStore//g' -e 's/UserDefaultsTriggerSettingsStore//g' \
    | grep -E 'UserDefaults|@AppStorage|@SceneStorage' || true)

if [[ -n "$USERDEFAULTS_HITS" ]]; then
    echo "UserDefaults guard failed -- the UserDefaults API must appear only in ${LABEL_STORE} or ${TRIGGER_SETTINGS_STORE} (a second caller is a decision, not a detail):" >&2
    echo "$USERDEFAULTS_HITS" >&2
    exit 1
fi

echo "==> queue-store guard: FileManager/file-writing APIs confined to PingQueueStore.swift and LastPingStore.swift, import Network confined to Connectivity.swift"
QUEUE_STORE="src/Queue/PingQueueStore.swift"
LAST_PING_STORE="src/Triggers/LastPingStore.swift"
CONNECTIVITY="src/Queue/Connectivity.swift"

# D-12 sanctioned PingQueueStore.swift as the ONE coordinate store, on exactly four conditions
# (protected, backup-excluded, deleted on delivery, never copied elsewhere). D-16 (2026-09-11)
# widened that to exactly TWO sanctioned stores -- LastPingStore.swift, on its own four
# conditions -- and no further. A THIRD writer using these APIs is a decision, not a detail --
# same shape as the UserDefaults guard above, including dropping comment-only lines first (a
# whole-file presence grep counts doc-comment text, .planning/LEARNINGS.md) rather than a
# whole-line `grep -v`, which a real call could hide beside on the same line.
# Widened after PR review probed it by ESCAPE (adding a second coordinate writer) rather than by
# absence (deleting a guarded one). Four probes walked straight past the old pattern: `write(toFile:`
# (only `.write(to:` was named), `FileHandle(forWritingAtPath:)` (never named at all), a `data.write(`
# split across two lines (grep is line-based -- the SAME multiline hole this file's own comment at the
# top already documents for the type-scale guard, reintroduced in a guard written after that
# learning), and `@preconcurrency import Network` (the `^import Network$` anchors below).
# The multiline case is caught by SHAPE rather than by content -- `\.write\([[:space:]]*$` matches a
# call left open at end of line -- because grep cannot see across lines at all. A writer that splits
# its call some other way would still escape; this guard is honest about being a net, not a proof.
# Each exemption is anchored on grep's own `path:lineno:` prefix, never a filter that drops any
# line merely MENTIONING one of the two filenames -- the same reason the Always guard below uses
# `^path:` rather than a whole-line `grep -v`.
QUEUE_STORE_HITS=$(grep -rnE \
    'FileManager|\.write\(to:|\.write\(toFile:|\.write\([[:space:]]*$|FileHandle|URLResourceValues|isExcludedFromBackup|completeFileProtectionUnlessOpen|completeFileProtectionUntilFirstUserAuthentication' \
    src --include='*.swift' 2>/dev/null \
    | grep -v "^${QUEUE_STORE}:" \
    | grep -v "^${LAST_PING_STORE}:" \
    | grep -vE '^[^:]*:[0-9]+: *(///|//|\*)' || true)

if [[ -n "$QUEUE_STORE_HITS" ]]; then
    echo "queue-store guard failed -- the queue file and the last-ping file are the TWO sanctioned coordinate stores (D-12, D-16); a third writer is a decision, not a detail:" >&2
    echo "$QUEUE_STORE_HITS" >&2
    exit 1
fi

NETWORK_IMPORT_HITS=$(grep -rnE '^[[:space:]]*(@[A-Za-z]+[[:space:]]+)*import[[:space:]]+Network[[:space:]]*$' src --include='*.swift' 2>/dev/null \
    | grep -v "^${CONNECTIVITY}:" || true)

if [[ -n "$NETWORK_IMPORT_HITS" ]]; then
    echo "queue-store guard failed -- import Network must appear only in ${CONNECTIVITY}:" >&2
    echo "$NETWORK_IMPORT_HITS" >&2
    exit 1
fi

echo "==> queue-protection guard: ${QUEUE_STORE} applies both completeFileProtectionUntilFirstUserAuthentication and isExcludedFromBackup on non-comment lines, and never completeFileProtectionUnlessOpen"

# A whole-file presence grep counts comment text (.planning/LEARNINGS.md: a phase-01 guard read
# 5 where the answer was 1). Strip comment lines from THIS file's own hits before checking
# either protection is actually applied in code, not just described in the header doc comment.
# D-21 (2026-09-12) moved the queue from completeFileProtectionUnlessOpen -- which sealed the file
# on every lock, so a pocket ping that failed offline could not be queued -- to D-16's class. The
# old class is now checked for by ABSENCE on non-comment lines: reintroducing it is the bug.
QUEUE_STORE_NONCOMMENT_HITS=$(grep -nE 'completeFileProtectionUnlessOpen|completeFileProtectionUntilFirstUserAuthentication|isExcludedFromBackup' "$QUEUE_STORE" 2>/dev/null \
    | grep -vE '^[0-9]+: *(///|//|\*)' || true)

if ! echo "$QUEUE_STORE_NONCOMMENT_HITS" | grep -q 'completeFileProtectionUntilFirstUserAuthentication'; then
    echo "queue-protection guard failed -- ${QUEUE_STORE} does not apply .completeFileProtectionUntilFirstUserAuthentication on a non-comment line (D-12 as amended by D-21 sanctioned the file only as protected; losing this voids the exception):" >&2
    exit 1
fi

if echo "$QUEUE_STORE_NONCOMMENT_HITS" | grep -q 'completeFileProtectionUnlessOpen'; then
    echo "queue-protection guard failed -- ${QUEUE_STORE} applies .completeFileProtectionUnlessOpen on a non-comment line; D-21 moved the queue off that class because it seals the file on every lock and an automatic ping from a locked pocket could not be queued:" >&2
    echo "$QUEUE_STORE_NONCOMMENT_HITS" | grep 'completeFileProtectionUnlessOpen' >&2
    exit 1
fi

if ! echo "$QUEUE_STORE_NONCOMMENT_HITS" | grep -q 'isExcludedFromBackup'; then
    echo "queue-protection guard failed -- ${QUEUE_STORE} does not apply isExcludedFromBackup on a non-comment line (D-12 sanctioned the file only as backup-excluded; losing this voids the exception):" >&2
    exit 1
fi

echo "==> last-ping-protection guard: ${LAST_PING_STORE} applies both completeFileProtectionUntilFirstUserAuthentication and isExcludedFromBackup on non-comment lines"

# Same discipline as the queue-protection guard above, and for the same reason: a whole-file
# presence grep counts comment text (.planning/LEARNINGS.md: a phase-01 guard read 5 where the
# answer was 1) -- a doc comment naming both D-16 conditions would satisfy a presence-only check
# without either ever reaching `save`. Strip comment lines from THIS file's own hits first.
LAST_PING_STORE_NONCOMMENT_HITS=$(grep -nE 'completeFileProtectionUntilFirstUserAuthentication|isExcludedFromBackup' "$LAST_PING_STORE" 2>/dev/null \
    | grep -vE '^[0-9]+: *(///|//|\*)' || true)

if ! echo "$LAST_PING_STORE_NONCOMMENT_HITS" | grep -q 'completeFileProtectionUntilFirstUserAuthentication'; then
    echo "last-ping-protection guard failed -- ${LAST_PING_STORE} does not apply .completeFileProtectionUntilFirstUserAuthentication on a non-comment line (D-16 condition 3 voided):" >&2
    exit 1
fi

if ! echo "$LAST_PING_STORE_NONCOMMENT_HITS" | grep -q 'isExcludedFromBackup'; then
    echo "last-ping-protection guard failed -- ${LAST_PING_STORE} does not apply isExcludedFromBackup on a non-comment line (D-16 condition 2 voided):" >&2
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

echo "==> background-modes guard: the BUILT Info.plist declares UIBackgroundModes location and fetch"
# Reuses $APP_PLIST from the background-identifier guard above -- derived from $DERIVED_DATA,
# never a literal. Proves Task 1's project.yml change survived into the PRODUCT, not only into
# project.yml.
BG_MODES=$(/usr/libexec/PlistBuddy -c "Print :UIBackgroundModes" "$APP_PLIST" 2>/dev/null || true)

if [[ "$BG_MODES" != *location* ]]; then
    echo "background-modes guard failed -- ${APP_PLIST}'s UIBackgroundModes is missing 'location' (significant-change/visits/CLMonitor wake needs it): ${BG_MODES}" >&2
    exit 1
fi

if [[ "$BG_MODES" != *fetch* ]]; then
    echo "background-modes guard failed -- ${APP_PLIST}'s UIBackgroundModes is missing 'fetch' (BGAppRefreshTask's queue drain needs it): ${BG_MODES}" >&2
    exit 1
fi

echo "==> smoke passed"
