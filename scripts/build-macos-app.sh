#!/bin/bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-release}"
VERSION="${ENVSTORE_VERSION:-0.1.0}"
BUILD_NUMBER="${ENVSTORE_BUILD_NUMBER:-1}"
OUTPUT_DIRECTORY="${ENVSTORE_OUTPUT_DIRECTORY:-$PROJECT_DIRECTORY/dist}"
APP_PATH="$OUTPUT_DIRECTORY/EnvStore.app"

cd "$PROJECT_DIRECTORY"
swift build -c "$CONFIGURATION" --product EnvStoreApp
swift build -c "$CONFIGURATION" --product EnvStoreBroker
swift build -c "$CONFIGURATION" --product envstore
BIN_DIRECTORY="$(swift build -c "$CONFIGURATION" --show-bin-path)"

rm -rf "$APP_PATH"
mkdir -p "$APP_PATH/Contents/MacOS"
mkdir -p "$APP_PATH/Contents/Resources"
mkdir -p "$APP_PATH/Contents/SharedSupport"
mkdir -p "$APP_PATH/Contents/Library/LaunchServices"

install -m 0755 "$BIN_DIRECTORY/EnvStoreApp" "$APP_PATH/Contents/MacOS/EnvStoreApp"
install -m 0755 "$BIN_DIRECTORY/EnvStoreBroker" "$APP_PATH/Contents/Library/LaunchServices/EnvStoreBroker"
install -m 0755 "$BIN_DIRECTORY/envstore" "$APP_PATH/Contents/SharedSupport/envstore"
install -m 0644 "$PROJECT_DIRECTORY/Packaging/Info.plist" "$APP_PATH/Contents/Info.plist"
install -m 0644 "$PROJECT_DIRECTORY/assets/brand/envstore-mark.svg" "$APP_PATH/Contents/Resources/envstore-mark.svg"

/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP_PATH/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"

ICON_WORK_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK_DIRECTORY"' EXIT
ICONSET="$ICON_WORK_DIRECTORY/AppIcon.iconset"
mkdir -p "$ICONSET"

if command -v magick >/dev/null 2>&1; then
    for SIZE in 16 32 128 256 512; do
        DOUBLE_SIZE=$((SIZE * 2))
        magick -background none "$PROJECT_DIRECTORY/assets/brand/envstore-mark.svg" -resize "${SIZE}x${SIZE}" "$ICONSET/icon_${SIZE}x${SIZE}.png"
        magick -background none "$PROJECT_DIRECTORY/assets/brand/envstore-mark.svg" -resize "${DOUBLE_SIZE}x${DOUBLE_SIZE}" "$ICONSET/icon_${SIZE}x${SIZE}@2x.png"
    done
    iconutil -c icns "$ICONSET" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
fi

SIGNING_IDENTITY="${ENVSTORE_SIGN_IDENTITY:--}"
if [[ "$SIGNING_IDENTITY" != "-" ]]; then
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH/Contents/SharedSupport/envstore"
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_PATH/Contents/Library/LaunchServices/EnvStoreBroker"
    codesign --force --options runtime --timestamp --entitlements "$PROJECT_DIRECTORY/Packaging/EnvStore.entitlements" --sign "$SIGNING_IDENTITY" "$APP_PATH"
else
    codesign --force --sign - "$APP_PATH/Contents/SharedSupport/envstore"
    codesign --force --sign - "$APP_PATH/Contents/Library/LaunchServices/EnvStoreBroker"
    codesign --force --deep --sign - "$APP_PATH"
fi

codesign --verify --deep --strict --verbose=2 "$APP_PATH"
echo "$APP_PATH"
