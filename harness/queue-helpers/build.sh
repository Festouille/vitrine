#!/bin/sh
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC="$HERE/../../tweak/Sources"
OUT="$HERE/build"
APP="$OUT/QueueHelpers.app"
mkdir -p "$OUT/gen" "$APP"
for file in Native/Player/QueueDuration Redesigned/NowPlaying/QueueDuration Shared/Player/TapToQueue; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$file.x" > "$OUT/gen/$(echo "$file" | tr / _).m"
done
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.4-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -I"$SRC/Native/Player" -I"$SRC/Redesigned/NowPlaying" -I"$SRC/Shared/Player" \
    -Wno-deprecated-declarations "$HERE/main.m" "$HERE/../scene.m" "$HERE/../tabbar/touch.m" \
    "$OUT/gen/Native_Player_QueueDuration.m" "$OUT/gen/Redesigned_NowPlaying_QueueDuration.m" \
    "$OUT/gen/Shared_Player_TapToQueue.m" "$SRC/Shared/Player/QueueHelpers.m" "$SRC/Shared/Player/QueueReshuffle.m" \
    "$SRC/Core/SGFlagForce.m" "$SRC/Core/SGPrefs.m" "$SRC/Core/SGUIMode.m" "$SRC/Core/SGLog.m" "$SRC/Core/SGViewTree.m" \
    -framework UIKit -framework IOKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$APP/QueueHelpers"
cp "$HERE/Info.plist" "$APP/Info.plist"
echo "built $APP"
