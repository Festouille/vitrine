#!/bin/sh
# build.sh: builds check.m against this checkout's Musixmatch.m, LyricsTranslation.m, SavedTranslations.m and KaraokeTiming.m
# (and LocalFiles.m, which Musixmatch.m reads a local file's names from) as a Mac Catalyst binary and runs
# it, so no simulator is needed.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
mkdir -p "$HERE/build"
SDK=$(xcrun --sdk macosx --show-sdk-path)
compile() {
    xcrun -sdk macosx clang -target arm64-apple-ios17.0-macabi -isysroot "$SDK" -iframework "$SDK/System/iOSSupport/System/Library/Frameworks" -fobjc-arc -g -Wall -I"$SRC" "$@"
}
"${THEOS:-$HOME/theos}/bin/logos.pl" -c generator=internal "$SRC/Shared/Lyrics/KaraokeSource.x" > "$HERE/build/KaraokeSource.m"
compile -DSGMusixmatchTranslations=SGHarnessUnusedMusixmatchTranslations -c "$SRC/Shared/LyricsSources/Musixmatch.m" -o "$HERE/build/Musixmatch.o"
compile -I"$SRC/Shared/Lyrics" "$HERE/check.m" "$HERE/build/KaraokeSource.m" "$HERE/build/Musixmatch.o" \
    "$SRC/Shared/LyricsTranslation/LyricsTranslation.m" "$SRC/Shared/LyricsTranslation/SavedTranslations.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" "$SRC/Shared/Lyrics/KaraokeBody.m" "$SRC/Shared/AdBlock/Protobuf.m" "$SRC/Shared/LocalFiles/LocalFiles.m" \
    -framework UIKit -framework CoreGraphics -framework Security -framework NaturalLanguage -framework Foundation -o "$HERE/build/check"
"$HERE/build/check"
