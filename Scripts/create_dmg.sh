#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT="$( cd "$SCRIPT_DIR/.." && pwd )"
cd "$ROOT"

APP_NAME="NetCollect"
VERSION="1.0.0"
DMG_NAME="${APP_NAME}-v${VERSION}.dmg"
DIST="$ROOT/dist"

echo "🔨 Building release app bundle..."
"$SCRIPT_DIR/build_app.sh"

APP="$ROOT/${APP_NAME}.app"
if [[ ! -d "$APP" ]]; then
  echo "ERROR: ${APP_NAME}.app not found!" >&2
  exit 1
fi

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

echo "📦 Staging DMG payload..."
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

mkdir -p "$DIST"
DMG_PATH="$DIST/$DMG_NAME"
rm -f "$DMG_PATH"

echo "💿 Creating compressed DMG ($DMG_NAME)..."
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGING" -ov -format UDZO "$DMG_PATH"

# Compute and display SHA256
SHA256=$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')
echo "✨ Created $DMG_PATH"
echo "🔑 SHA256: $SHA256"
