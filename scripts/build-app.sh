#!/bin/bash
# Builds "Data Explorer.app" into ./build with Swift Package Manager.
#
#   ./scripts/build-app.sh              # release build for this Mac
#   UNIVERSAL=1 ./scripts/build-app.sh  # Apple silicon + Intel (needs the full Xcode app)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Data Explorer"
PRODUCT="DataExplorer"
BUILD_DIR="build"
ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --product "$PRODUCT"
BIN_PATH="$(swift build -c release ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

APP="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# The icon is drawn in code, so there are no image files to keep in sync.
ICONSET="$BUILD_DIR/AppIcon.iconset"
rm -rf "$ICONSET"
swift scripts/make-icon.swift "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

# An ad-hoc signature gives the app a stable identity, which macOS needs to remember
# permissions such as Full Disk Access.
codesign --force --sign - --timestamp=none "$APP"

(cd "$BUILD_DIR" && rm -f Data-Explorer.zip && ditto -c -k --keepParent "$APP_NAME.app" Data-Explorer.zip)
echo "Built $APP"
