#!/bin/bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
OUTPUT_DIRECTORY="${ENVSTORE_OUTPUT_DIRECTORY:-$PROJECT_DIRECTORY/dist}"
VERSION="${ENVSTORE_VERSION:-0.1.0}"
DMG_PATH="$OUTPUT_DIRECTORY/EnvStore-$VERSION.dmg"

"$SCRIPT_DIRECTORY/build-macos-app.sh"

STAGING_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIRECTORY"' EXIT
ditto "$OUTPUT_DIRECTORY/EnvStore.app" "$STAGING_DIRECTORY/EnvStore.app"
ln -s /Applications "$STAGING_DIRECTORY/Applications"
rm -f "$DMG_PATH"
hdiutil create -volname "EnvStore $VERSION" -srcfolder "$STAGING_DIRECTORY" -ov -format UDZO "$DMG_PATH"
echo "$DMG_PATH"
