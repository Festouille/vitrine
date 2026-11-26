#!/bin/sh
# Builds the CarPlay Simulator harness: compiles the real CarPlay.x (via logos.pl),
# SGCarPlayModel.m, and KaraokeLines/Timing/Romanise against the iOS Simulator CarPlay SDK,
# signed with the com.apple.developer.carplay-audio entitlement so it launches inside the
# Xcode CarPlay Simulator (I/O -> External Displays -> CarPlay).
set -e
THEOS="${THEOS:-$HOME/theos}"
DIR=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$DIR/../../tweak/Sources" && pwd)
OUT="$DIR/build"
rm -rf "$OUT"
mkdir -p "$OUT/gen" "$OUT/CarPlayHarness.app"

"$THEOS/bin/logos.pl" -c generator=internal "$SRC/Shared/CarPlay/CarPlay.x" > "$OUT/gen/CarPlay.m"

cat > "$OUT/entitlements.plist" <<'ENT'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>application-identifier</key><string>VITRINE000.com.vitrine.carplayharness</string>
  <key>com.apple.developer.carplay-audio</key><true/>
</dict>
</plist>
ENT

SDK=$(xcrun --sdk iphonesimulator --show-sdk-path)
xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O1 \
    -Wall -Werror -Wno-deprecated-declarations -Wno-unused-function \
    -I"$SRC" -I"$SRC/Shared/CarPlay" -isysroot "$SDK" \
    -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker "$OUT/entitlements.plist" \
    "$DIR/main.m" \
    "$OUT/gen/CarPlay.m" \
    "$SRC/Shared/CarPlay/SGCarPlayModel.m" \
    "$SRC/Shared/Lyrics/KaraokeLines.m" \
    "$SRC/Shared/Lyrics/KaraokeTiming.m" \
    "$SRC/Shared/Lyrics/Romanise.m" \
    "$SRC/Core/SGLog.m" \
    "$SRC/Core/SGPrefs.m" \
    "$SRC/Core/SGUIMode.m" \
    "$SRC/Core/SGFlagForce.m" \
    "$SRC/Settings/SGLocalize.m" \
    "$SRC/Settings/SGStrings_fr.m" \
    "$SRC/Settings/SGStrings_es.m" \
    "$SRC/Settings/SGStrings_tr.m" \
    -framework UIKit -framework CarPlay -framework MediaPlayer -framework AVFoundation \
    -framework CoreGraphics -framework QuartzCore -framework Foundation -framework NaturalLanguage \
    -o "$OUT/CarPlayHarness.app/CarPlayHarness"

cat > "$OUT/CarPlayHarness.app/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>CarPlayHarness</string>
  <key>CFBundleIdentifier</key><string>com.vitrine.carplayharness</string>
  <key>CFBundleName</key><string>Vitrine CarPlay</string>
  <key>CFBundleDisplayName</key><string>Vitrine CarPlay</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>UIBackgroundModes</key>
  <array>
    <string>audio</string>
  </array>
  <key>UILaunchScreen</key><dict/>
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><true/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneConfigurationName</key><string>PhoneScene</string>
          <key>UISceneDelegateClassName</key><string>SGPhoneSceneDelegate</string>
        </dict>
      </array>
      <key>CPTemplateApplicationSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneClassName</key><string>CPTemplateApplicationScene</string>
          <key>UISceneConfigurationName</key><string>CarPlayScene</string>
          <key>UISceneDelegateClassName</key><string>SGCarPlaySceneDelegate</string>
        </dict>
      </array>
    </dict>
  </dict>
</dict>
</plist>
PLIST

echo "built $OUT/CarPlayHarness.app"
