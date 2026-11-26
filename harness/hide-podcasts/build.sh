#!/bin/sh
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
OUT="$HERE/build"
APP="$OUT/HidePodcastsHarness.app"
mkdir -p "$APP"
for look in Native Redesigned; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal \
        "$SRC/$look/HidePodcasts/HidePodcasts.x" > "$OUT/$look.m"
done
xcrun -sdk iphonesimulator clang -target arm64-apple-ios26.0-simulator -fobjc-arc -I"$SRC" \
    "$HERE/main.m" "$OUT/Native.m" "$OUT/Redesigned.m" \
    "$SRC/Shared/HidePodcasts/HidePodcasts.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGPrefs.m" \
    "$SRC/Core/SGUIMode.m" "$SRC/Core/SGViewTree.m" \
    -framework UIKit -framework Foundation -framework QuartzCore -framework CoreGraphics \
    -o "$APP/HidePodcastsHarness"
cp "$HERE/Info.plist" "$APP/Info.plist"
echo "built $APP"
