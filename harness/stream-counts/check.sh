#!/bin/sh
set -eu
cd "$(dirname "$0")"
DEVICE="${1:?Pass the UDID of a booted iOS 26 or later simulator}"
EVIDENCE="${2:?Pass an existing screenshot directory}"
test -d "$EVIDENCE"
BUNDLE=org.vitrine.stream-counts
xcrun simctl install "$DEVICE" build/StreamCounts.app
DATA=$(xcrun simctl get_app_container "$DEVICE" "$BUNDLE" data)
for look in Native Redesigned; do
    for setting in off on; do
        rm -f "$DATA/Documents/result.txt"
        redesign=NO
        enabled=NO
        if [ "$look" = Redesigned ]; then redesign=YES; fi
        if [ "$setting" = on ]; then enabled=YES; fi
        xcrun simctl launch --terminate-running-process "$DEVICE" "$BUNDLE" \
            -spotifyglass.redesign "$redesign" -spotifyglass.streamCounts "$enabled"
        for attempt in 1 2 3 4 5 6 7 8 9 10; do
            if [ -f "$DATA/Documents/result.txt" ]; then break; fi
            sleep 1
        done
        if ! rg -F "$look $setting: row counts, missing counts and request deduplication held" "$DATA/Documents/result.txt"; then
            echo "Failed: $look $setting" >&2
            exit 1
        fi
        xcrun simctl io "$DEVICE" screenshot "$EVIDENCE/$look-$setting.png"
    done
done
