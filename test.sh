#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
BUILD_DIR="$SCRIPT_DIR/.build"
SDK_PATH="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
MODULE_CACHE="$BUILD_DIR/ModuleCache"
mkdir -p "$BUILD_DIR" "$MODULE_CACHE"

xcrun swiftc \
    -swift-version 5 \
    -parse-as-library \
    -sdk "$SDK_PATH" \
    -module-cache-path "$MODULE_CACHE" \
    -framework CoreText \
    -o "$BUILD_DIR/FontInstallerTests" \
    "$SCRIPT_DIR/Sources/ArchiveUtilities.swift" \
    "$SCRIPT_DIR/Sources/FontInstaller.swift" \
    "$SCRIPT_DIR/Sources/FontBatch.swift" \
    "$SCRIPT_DIR/Tests/FontInstallerTests.swift"

"$BUILD_DIR/FontInstallerTests"

