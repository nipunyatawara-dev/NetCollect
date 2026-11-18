#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
ICNS_FILE="$PROJECT_DIR/AppIcon.icns"
ICON_WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$ICON_WORK_DIR"' EXIT
MASTER_PNG="$ICON_WORK_DIR/netcollect_1024.png"
ICONSET_DIR="$ICON_WORK_DIR/NetCollect.iconset"

echo "🎨 Rendering 1024x1024 Apple Design Icon..."
swift "$SCRIPT_DIR/generate_icon.swift" "$MASTER_PNG"

echo "📐 Generating multi-resolution iconset..."
mkdir -p "$ICONSET_DIR"

sips -z 16 16     "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16.png" > /dev/null
sips -z 32 32     "$MASTER_PNG" --out "$ICONSET_DIR/icon_16x16@2x.png" > /dev/null
sips -z 32 32     "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32.png" > /dev/null
sips -z 64 64     "$MASTER_PNG" --out "$ICONSET_DIR/icon_32x32@2x.png" > /dev/null
sips -z 128 128   "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128.png" > /dev/null
sips -z 256 256   "$MASTER_PNG" --out "$ICONSET_DIR/icon_128x128@2x.png" > /dev/null
sips -z 256 256   "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256.png" > /dev/null
sips -z 512 512   "$MASTER_PNG" --out "$ICONSET_DIR/icon_256x256@2x.png" > /dev/null
sips -z 512 512   "$MASTER_PNG" --out "$ICONSET_DIR/icon_512x512.png" > /dev/null
cp "$MASTER_PNG" "$ICONSET_DIR/icon_512x512@2x.png"

echo "📦 Compiling AppIcon.icns with iconutil..."
iconutil -c icns "$ICONSET_DIR" -o "$ICNS_FILE"

echo "✅ AppIcon.icns generated at $ICNS_FILE"
