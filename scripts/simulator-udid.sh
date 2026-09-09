#!/usr/bin/env bash
# Prints the UDID of one available iOS 26 iPhone simulator on stdout.
# Honours $SIMULATOR_NAME (an exact device name) when set; otherwise picks
# the first available iPhone whose runtime is iOS 26.x. Never hardcodes a
# device name — installed iPhone models vary by machine and Xcode version.
set -euo pipefail

if [[ -n "${SIMULATOR_NAME:-}" ]]; then
    udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
name = sys.argv[1]
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    if 'iOS-26' not in runtime:
        continue
    for device in devices:
        if device.get('isAvailable') and device.get('name') == name:
            print(device['udid'])
            sys.exit(0)
" "$SIMULATOR_NAME")
else
    udid=$(xcrun simctl list devices available -j | python3 -c "
import json, sys
data = json.load(sys.stdin)
for runtime, devices in data['devices'].items():
    if 'iOS-26' not in runtime:
        continue
    for device in devices:
        if device.get('isAvailable') and device.get('name', '').startswith('iPhone'):
            print(device['udid'])
            sys.exit(0)
")
fi

if [[ -z "$udid" ]]; then
    echo "simulator-udid.sh: no available iOS 26 iPhone simulator found" >&2
    exit 1
fi

echo "$udid"
