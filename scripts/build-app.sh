#!/bin/bash
# Builds "Data Explorer.app" into ./build with Swift Package Manager.
#
#   ./scripts/build-app.sh            # universal (Apple silicon + Intel) release build
#   UNIVERSAL=0 ./scripts/build-app.sh  # just this Mac's architecture (faster)
set -euo pipefail

cd "$(dirname "$0")/.."

APP_NAME="Data Explorer"
PRODUCT="DataExplorer"
BUILD_DIR="build"
ARCH_FLAGS=()
if [ "${UNIVERSAL:-1}" = "1" ]; then
  ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c release "${ARCH_FLAGS[@]}" --product "$PRODUCT"
BIN_PATH="$(swift build -c release "${ARCH_FLAGS[@]}" --show-bin-path)"

APP="$BUILD_DIR/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_PATH/$PRODUCT" "$APP/Contents/MacOS/$PRODUCT"
cp Resources/Info.plist "$APP/Contents/Info.plist"
if [ -f Resources/AppIcon.icns ]; then
  cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
fi

# An ad-hoc signature gives the app a stable identity, which macOS needs to remember
# permissions such as Full Disk Access.
codesign --force --sign - --timestamp=none "$APP"

(cd "$BUILD_DIR" && rm -f Data-Explorer.zip && ditto -c -k --keepParent "$APP_NAME.app" Data-Explorer.zip)
echo "Built $APP"
