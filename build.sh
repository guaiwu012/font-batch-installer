#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/.build"
DIST_DIR="$SCRIPT_DIR/dist"
APP_DIR="$DIST_DIR/字装一下.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
LOGIN_ITEMS_DIR="$CONTENTS_DIR/Library/LoginItems"
WATCHER_APP="$LOGIN_ITEMS_DIR/字装一下监控器.app"
WATCHER_CONTENTS="$WATCHER_APP/Contents"
WATCHER_MACOS="$WATCHER_CONTENTS/MacOS"
ICONSET_DIR="$BUILD_DIR/AppIcon.iconset"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
MODULE_CACHE="$BUILD_DIR/ModuleCache"

mkdir -p "$BUILD_DIR" "$DIST_DIR" "$MODULE_CACHE"
rm -rf "$APP_DIR" "$ICONSET_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR" "$ICONSET_DIR" "$WATCHER_MACOS"

xcrun swiftc \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macos14.0 \
    -framework SwiftUI \
    -framework AppKit \
    -framework CoreText \
    -framework ServiceManagement \
    -o "$MACOS_DIR/FontBatchInstaller" \
    "$SCRIPT_DIR/Sources/App.swift" \
    "$SCRIPT_DIR/Sources/ContentView.swift" \
    "$SCRIPT_DIR/Sources/ViewModel.swift" \
    "$SCRIPT_DIR/Sources/FontInstaller.swift" \
    "$SCRIPT_DIR/Sources/FontBatch.swift" \
    "$SCRIPT_DIR/Sources/ArchiveUtilities.swift" \
    "$SCRIPT_DIR/Sources/DownloadWatcher.swift" \
    "$SCRIPT_DIR/Sources/LoginItemController.swift"

cp "$SCRIPT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

xcrun swiftc \
    -swift-version 5 \
    -parse-as-library \
    -O \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -target arm64-apple-macos14.0 \
    -framework AppKit \
    -o "$WATCHER_MACOS/FontBatchInstallerWatcher" \
    "$SCRIPT_DIR/Watcher/WatcherMain.swift" \
    "$SCRIPT_DIR/Sources/ArchiveUtilities.swift" \
    "$SCRIPT_DIR/Sources/DownloadWatcher.swift"
cp "$SCRIPT_DIR/Watcher/Info.plist" "$WATCHER_CONTENTS/Info.plist"

xcrun swiftc -O -sdk "$SDK_PATH" -module-cache-path "$MODULE_CACHE" -framework AppKit -o "$BUILD_DIR/IconMaker" "$SCRIPT_DIR/Tools/IconMaker.swift"
for entry in "16x16:16" "16x16@2x:32" "32x32:32" "32x32@2x:64" "128x128:128" "128x128@2x:256" "256x256:256" "256x256@2x:512" "512x512:512" "512x512@2x:1024"; do
    name="${entry%%:*}"
    pixels="${entry##*:}"
    "$BUILD_DIR/IconMaker" "$pixels" "$ICONSET_DIR/icon_${name}.png"
done
xcrun swiftc -O -sdk "$SDK_PATH" -module-cache-path "$MODULE_CACHE" -o "$BUILD_DIR/IcnsPacker" "$SCRIPT_DIR/Tools/IcnsPacker.swift"
"$BUILD_DIR/IcnsPacker" "$ICONSET_DIR" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --sign - "$WATCHER_APP"
codesign --force --deep --sign - "$APP_DIR"

rm -f "$DIST_DIR/字装一下-macOS.zip" "$DIST_DIR/ZiZhuangYiXia-macOS.zip"
ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$DIST_DIR/ZiZhuangYiXia-macOS.zip"
cp "$DIST_DIR/ZiZhuangYiXia-macOS.zip" "$DIST_DIR/字装一下-macOS.zip"

echo "Built: $APP_DIR"

