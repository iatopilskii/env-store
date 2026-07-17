#!/bin/bash
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "$SCRIPT_DIRECTORY/.." && pwd)"
OUTPUT_DIRECTORY="${ENVSTORE_OUTPUT_DIRECTORY:-$PROJECT_DIRECTORY/dist}"
VERSION="${ENVSTORE_VERSION:-0.1.0}"

"$SCRIPT_DIRECTORY/build-macos-dmg.sh"

tar -C "$OUTPUT_DIRECTORY/EnvStore.app/Contents/SharedSupport" -czf "$OUTPUT_DIRECTORY/envstore-cli-$VERSION-macos.tar.gz" envstore
tar -C "$PROJECT_DIRECTORY/skills" -czf "$OUTPUT_DIRECTORY/envstore-agent-skill-$VERSION.tar.gz" envstore

cd "$OUTPUT_DIRECTORY"
shasum -a 256 "EnvStore-$VERSION.dmg" "envstore-cli-$VERSION-macos.tar.gz" "envstore-agent-skill-$VERSION.tar.gz" > "SHA256SUMS-$VERSION.txt"
cat "SHA256SUMS-$VERSION.txt"
