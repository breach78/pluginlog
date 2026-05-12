#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${1:-debug}"
PRODUCT_NAME="BrainUnfog"
EXECUTABLE_NAME="Brain Unfog"
APP_NAME="Brain Unfog.app"

cd "$ROOT_DIR"

swift build -c "$CONFIGURATION"

BIN_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$ROOT_DIR/.build/$APP_NAME"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
EXECUTABLE_PATH="$BIN_DIR/$PRODUCT_NAME"
ENTITLEMENTS_PATH="$ROOT_DIR/import/BUF/BrainUnfog.entitlements"
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

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
cp "$INFO_PLIST_PATH" "$CONTENTS_DIR/Info.plist"
printf "APPL????" > "$CONTENTS_DIR/PkgInfo"

while IFS= read -r -d '' resource_bundle_path; do
  cp -R "$resource_bundle_path" "$RESOURCES_DIR/$(basename "$resource_bundle_path")"
done < <(find "$BIN_DIR" -maxdepth 1 -type d -name '*_BrainUnfog.bundle' -print0)

if [[ -d "$ICONSET_PATH" ]]; then
  TMP_ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/brain-unfog-iconset.XXXXXX")/AppIcon.iconset"
  mkdir -p "$TMP_ICONSET"
  cp "$ICONSET_PATH"/*.png "$TMP_ICONSET/"
  iconutil -c icns "$TMP_ICONSET" -o "$ICON_PATH"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconFile AppIcon" "$CONTENTS_DIR/Info.plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string AppIcon" "$CONTENTS_DIR/Info.plist"
fi

codesign --force --sign - --entitlements "$ENTITLEMENTS_PATH" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

echo "$APP_DIR"
