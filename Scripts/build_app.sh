#!/bin/bash
set -e

SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
PROJECT_DIR="$( cd "$SCRIPT_DIR/.." && pwd )"
APP_BUNDLE="$PROJECT_DIR/NetCollect.app"
source "$SCRIPT_DIR/version.sh"

# SwiftUI macros are shipped with full Xcode. Keep an explicit selection intact.
if [ -z "${DEVELOPER_DIR:-}" ] && [ "$(xcode-select -p)" = "/Library/Developer/CommandLineTools" ] &&
   [ -d "/Applications/Xcode.app/Contents/Developer" ]; then
    export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
fi
# Keep the deployment target in sync with Package.swift.
MINIMUM_MACOS="14.0"
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [ "${SDK_VERSION%%.*}" -lt 27 ]; then
    echo "Select Xcode 27 or later to build NetCollect with the macOS 27 SDK." >&2
    exit 1
fi

echo "🎨 Ensuring AppIcon.icns exists..."
if [ ! -f "$PROJECT_DIR/AppIcon.icns" ]; then
    "$SCRIPT_DIR/create_icns.sh"
fi

echo "🔨 Compiling NetCollect (Release)..."
cd "$PROJECT_DIR"
# SwiftPM can stamp the deployment target as the linked SDK. SwiftUI
# checks this metadata to enable the current system's native appearance.
swift build -c release --product NetCollect \
    -Xlinker -platform_version -Xlinker macos -Xlinker "$MINIMUM_MACOS" -Xlinker "$SDK_VERSION"
BUILD_DIR="$(swift build -c release --show-bin-path)"
LINKED_SDK="$(xcrun vtool -show-build "$BUILD_DIR/NetCollect" | awk '$1 == "sdk" { print $2 }')"
if [ "$LINKED_SDK" != "$SDK_VERSION" ]; then
    echo "NetCollect links against macOS SDK $LINKED_SDK, expected $SDK_VERSION." >&2
    exit 1
fi

echo "📦 Packaging NetCollect.app bundle..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BUILD_DIR/NetCollect" "$APP_BUNDLE/Contents/MacOS/NetCollect"
chmod +x "$APP_BUNDLE/Contents/MacOS/NetCollect"
cp "$PROJECT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

cat << EOF > "$APP_BUNDLE/Contents/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>NetCollect</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.netcollect.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>NetCollect</string>
    <key>CFBundleDisplayName</key>
    <string>NetCollect</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$NETCOLLECT_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$NETCOLLECT_BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>$MINIMUM_MACOS</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 NetCollect. All rights reserved.</string>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
EOF

echo "🖊️  Ad-hoc signing NetCollect.app bundle..."
codesign --force --options runtime --timestamp=none --sign - "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

echo "✨ NetCollect.app successfully created with AppIcon at $APP_BUNDLE"
