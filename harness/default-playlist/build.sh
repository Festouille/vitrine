#!/bin/bash
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
SRC=$(cd "$HERE/../../tweak/Sources" && pwd)
APP="$HERE/build/DefaultPlaylistHarness.app"
mkdir -p "$APP"

xcrun -sdk iphonesimulator clang -target arm64-apple-ios17.0-simulator -fobjc-arc -g -O0 \
    -I"$SRC" -Wall -Werror -Wno-deprecated-declarations \
    "$HERE/main.m" "$HERE/../scene.m" "$SRC/Shared/DefaultPlaylist/DefaultPlaylist.m" \
    "$SRC"/Settings/{SGPage,SGPageStyle,SGModPage,SGGlowSwitch}.m \
    "$SRC"/Settings/{SGLocalize,SGStrings_fr,SGStrings_es,SGStrings_tr}.m \
    "$SRC"/Core/{SGLog,SGPrefs,SGViewTree,SGGlass,SGLegacyGlass,SGGlassTouch,SGFlagForce,SGUIMode}.m \
    -framework UIKit -framework QuartzCore -framework CoreGraphics -framework Foundation \
    -o "$APP/DefaultPlaylistHarness"

cat > "$APP/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>DefaultPlaylistHarness</string>
<key>CFBundleIdentifier</key><string>com.vitrine.defaultplaylistharness</string>
<key>CFBundleVersion</key><string>1</string>
<key>UIUserInterfaceStyle</key><string>Dark</string>
<key>UILaunchScreen</key><dict/>
<key>UIApplicationSceneManifest</key><dict>
  <key>UISceneConfigurations</key><dict>
    <key>UIWindowSceneSessionRoleApplication</key><array><dict>
      <key>UISceneConfigurationName</key><string>Default</string>
      <key>UISceneDelegateClassName</key><string>SGRHarnessScene</string>
    </dict></array>
  </dict>
</dict>
</dict></plist>
PLIST
echo "built $APP"
