#!/bin/sh
set -e
cd "$(dirname "$0")"
SRC=${SRC:-$(cd ../../tweak/Sources && pwd)}
THEOS=${THEOS:-$HOME/theos}
APP="$PWD/build/ArtworkAccentHarness.app"
mkdir -p build/gen "$APP"

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
compile() {
    xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
        -isysroot "$SDK" -Wno-deprecated-declarations -I"$SRC" "$@"
}
for source in Shared/Player/PlayerState Shared/LocalFiles/LocalFileInfo Native/Appearance/Accent Native/Appearance/Repaint \
    Native/Home/HomeGradient Redesigned/Kit/SGRAccent Redesigned/Home/HomeHeader Redesigned/Player/PlayerCoverAccent; do
    name=${source##*/}
    "$THEOS/bin/logos.pl" -c generator=internal "$SRC/$source.x" > "build/gen/$name.m"
    compile -I"$SRC/${source%/*}" -c "build/gen/$name.m" -o "build/gen/$name.o"
done

compile main.m stubs.m ../scene.m build/gen/*.o \
    "$SRC"/Core/SGLog.m "$SRC"/Core/SGPrefs.m "$SRC"/Core/SGUIMode.m "$SRC"/Core/SGViewTree.m \
    "$SRC"/Native/Home/HomeGradientChoices.m "$SRC"/Redesigned/Kit/SGRTokens.m "$SRC"/Redesigned/Kit/SGRActionRow.m \
    "$SRC"/Shared/Player/SGArtworkAccent.m "$SRC"/Shared/Player/SGLastTrack.m \
    "$SRC"/Shared/LocalFiles/LocalCover.m "$SRC"/Shared/LocalFiles/LocalFiles.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation -framework CoreText -framework MediaPlayer -framework Symbols \
    -o "$APP/ArtworkAccentHarness"
cp Info.plist "$APP/Info.plist"
codesign -f -s - "$APP"
echo "built $APP"
