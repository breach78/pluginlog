#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"
PRODUCT_NAME="BrainUnfogHarness"
APP_NAME="BrainUnfogHarness.app"
RESOURCE_BUNDLE_NAME="pluginlog-harness_BrainUnfogHarness.bundle"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/.build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$BIN_DIR/$PRODUCT_NAME"
RESOURCE_BUNDLE_PATH="$BIN_DIR/$RESOURCE_BUNDLE_NAME"
ENTITLEMENTS_PATH="$ROOT_DIR/import/BUF/BrainUnfogHarness.entitlements"
INFO_PLIST_PATH="$ROOT_DIR/import/BUF/Info.plist"
ICONSET_PATH="$ROOT_DIR/import/BUF/Assets.xcassets/AppIcon.appiconset"
ICON_PATH="$RESOURCES_DIR/AppIcon.icns"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Missing executable: $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ ! -f "$ENTITLEMENTS_PATH" ]]; then
  echo "Missing entitlements: $ENTITLEMENTS_PATH" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$PRODUCT_NAME"
cp "$INFO_PLIST_PATH" "$CONTENTS_DIR/Info.plist"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

if [[ -d "$RESOURCE_BUNDLE_PATH" ]]; then
  cp -R "$RESOURCE_BUNDLE_PATH" "$RESOURCES_DIR/$RESOURCE_BUNDLE_NAME"
fi

if [[ -d "$ICONSET_PATH" ]] && iconutil -c icns "$ICONSET_PATH" -o "$ICON_PATH" 2>/dev/null; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist"
fi

codesign --force --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
