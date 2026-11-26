#!/bin/sh
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
UDID=${1:?Usage: sh launch-settings.sh <simulator-udid>}
OUT=${OUT:-$HERE/build}
ffmpeg -v error -y -f lavfi -i color=c=white:s=360x640:d=4 -pix_fmt yuv420p "$OUT/settings-canvas.mp4"
xcrun simctl install "$UDID" "$OUT/PlayerHarness.app"
SIMCTL_CHILD_HARNESS_CANVAS_FILE="$OUT/settings-canvas.mp4" SIMCTL_CHILD_HARNESS_SCENARIO=settings \
    xcrun simctl launch --terminate-running-process --console "$UDID" com.vojta.playerharness
