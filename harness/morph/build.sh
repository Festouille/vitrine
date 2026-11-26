#!/bin/sh
set -e
SRC=$(cd "$(dirname "$0")/../../tweak/Sources" && pwd)
OUT=$(dirname "$0")/build
if [ "${MORPH_COMPACT:-0}" = 1 ]; then
    OUT=$(dirname "$0")/build/compact
fi
rm -rf "$OUT"; mkdir -p "$OUT/gen" "$OUT/MorphHarness.app"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Redesigned/Player/PlayerMorph.x" > "$OUT/gen/PlayerMorph.m"
"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Native/Player/PlayerTransition.x" > "$OUT/gen/PlayerTransition.m"
SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -DMORPH_COMPACT="${MORPH_COMPACT:-0}" \
    -I"$SRC" -I"$SRC/Redesigned/Player" -I"$SRC/Native/Player" -isysroot "$SDK" -Wno-deprecated-declarations \
    "$(dirname "$0")/main.m" "$(dirname "$0")/../scene.m" "$OUT"/gen/*.m "$SRC/Core/SGPrefs.m" \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$OUT/MorphHarness.app/MorphHarness"
cat > "$OUT/MorphHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>MorphHarness</string>
<key>CFBundleIdentifier</key><string>com.vojta.morphharness</string>
<key>CFBundleName</key><string>MorphHarness</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UIApplicationSupportsMultipleScenes</key><false/>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
codesign -f -s - "$OUT/MorphHarness.app" >/dev/null 2>&1
echo "built $OUT/MorphHarness.app"
