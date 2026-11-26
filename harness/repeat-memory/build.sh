#!/bin/bash
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
SRC="$REPO/tweak/Sources"
OUT="$HERE/build"
APP="$OUT/RepeatMemory.app"
mkdir -p "$APP"
for name in PlayerState RepeatMode; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/Player/$name.x" > "$OUT/$name.m"
done
xcrun --sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -I"$SRC" -I"$SRC/Shared/Player" \
    "$HERE/main.m" "$HERE/../scene.m" "$OUT/PlayerState.m" "$OUT/RepeatMode.m" \
    "$SRC/Core/SGPrefs.m" "$SRC/Core/SGLog.m" -framework UIKit -framework Foundation -o "$APP/RepeatMemory"
cp "$HERE/Info.plist" "$APP/Info.plist"
echo "built $APP"
