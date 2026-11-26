#!/bin/sh
set -eu
cd "$(dirname "$0")"
SRC=../../tweak/Sources
APP=build/StreamCounts.app
mkdir -p build "$APP"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
TARGET=arm64-apple-ios17.0-simulator
for look in Native Redesigned; do
    "${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/$look/StreamCounts/StreamCounts.x" > "build/$look.m"
done
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/StreamCounts/StreamCountDataLoader.x" > build/DataLoader.m
xcrun --sdk iphonesimulator swiftc -target "$TARGET" -sdk "$SDK" -parse-as-library -whole-module-optimization \
    -emit-object IdentityFixture.swift "$SRC/Shared/StreamCounts/StreamCountIdentity.swift" -o build/Identity.o
SWIFT=$(dirname "$(xcrun --find swiftc)")/../lib/swift/iphonesimulator
xcrun --sdk iphonesimulator clang -target "$TARGET" -isysroot "$SDK" -fobjc-arc -I"$SRC" \
    main.m ../scene.m build/Native.m build/Redesigned.m build/DataLoader.m build/Identity.o \
    "$SRC"/Core/{SGPrefs,SGUIMode,SGViewTree,SGLog}.m \
    "$SRC/Shared/StreamCounts/StreamCounts.m" "$SRC/Redesigned/Kit/SGRTokens.m" \
    -L"$SWIFT" -lswiftCore -Wl,-rpath,/usr/lib/swift -framework UIKit -framework CoreText -framework Foundation \
    -o "$APP/StreamCounts"
cp Info.plist "$APP/Info.plist"
echo "built $APP"
