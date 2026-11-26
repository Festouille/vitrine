#!/bin/sh
set -eu
cd "$(dirname "$0")"
device=${1:-booted}
app=com.vitrine.artworkaccentharness
./build.sh
xcrun simctl install "$device" build/ArtworkAccentHarness.app
data=$(xcrun simctl get_app_container "$device" "$app" data)
result="$data/Documents/result.txt"
for look in native redesigned; do
    for state in off on; do
        set -- -spotifyglass.homeGradient YES
        if [ "$look" = redesigned ]; then
            set -- "$@" -spotifyglass.redesign YES
            key=spotifyglass.redesign.accent.artwork
        else
            key=spotifyglass.accent.artwork
        fi
        if [ "$state" = on ]; then set -- "$@" "-$key" YES; fi
        xcrun simctl terminate "$device" "$app" 2>/dev/null || true
        rm -f "$result"
        log="build/$look-$state.log"
        xcrun simctl launch --console-pty "$device" "$app" "$@" > "$log" 2>&1 &
        pid=$!
        for i in $(seq 1 60); do
            if [ -f "$result" ] || ! kill -0 "$pid" 2>/dev/null; then break; fi
            sleep 0.2
        done
        if [ ! -f "$result" ] || ! grep "^PASS $look accent $state:" "$result"; then
            xcrun simctl terminate "$device" "$app" 2>/dev/null || true
            tail -30 "$log" >&2
            exit 1
        fi
        xcrun simctl io "$device" screenshot "build/$look-$state.png"
    done
done
