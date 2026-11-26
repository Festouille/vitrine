#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
DEVICE=${1:?usage: test.sh DEVICE_UDID [SCREENSHOT_DIRECTORY]}
OUT=${2:-"$HERE/build"}
ID=com.vitrine.hidepodcastsharness
mkdir -p "$OUT"
"$HERE/build.sh"
xcrun simctl status_bar "$DEVICE" override --time 9:41 --dataNetwork wifi --wifiMode active \
    --wifiBars 3 --cellularMode active --cellularBars 4 --batteryState discharging --batteryLevel 100
xcrun simctl install "$DEVICE" "$HERE/build/HidePodcastsHarness.app"
RESULT="$(xcrun simctl get_app_container "$DEVICE" "$ID" data)/Documents/result.txt"
for look in Native Redesigned; do
    redesigned=NO
    [ "$look" != Redesigned ] || redesigned=YES
    for mode in OFF ON; do
        hide=NO
        [ "$mode" != ON ] || hide=YES
        xcrun simctl terminate "$DEVICE" "$ID" 2>/dev/null || true
        rm -f "$RESULT"
        xcrun simctl launch "$DEVICE" "$ID" -spotifyglass.redesign "$redesigned" -spotifyglass.hidePodcasts "$hide"
        count=0
        until [ -f "$RESULT" ] || [ "$count" -ge 60 ]; do
            count=$((count + 1))
            sleep 0.5
        done
        grep -Fx "$look · $mode: filter and reuse checks passed" "$RESULT"
        xcrun simctl io "$DEVICE" screenshot "$OUT/$look-$mode.png"
    done
done
