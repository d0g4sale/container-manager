#!/bin/bash
# Builds Container Manager and assembles a macOS .app bundle.
# Usage: ./build.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
APP_NAME="Container Manager"       # display name & .app bundle
TARGET="ContainerUI"               # SwiftPM product / binary name
BUNDLE_ID="com.mckaymic.Container-Manager"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/$APP_NAME.app"

echo "▸ Compiling ($CONFIG)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/$TARGET"
if [[ ! -f "$BIN_PATH" ]]; then
    echo "✗ Build produced no binary at $BIN_PATH" >&2
    exit 1
fi

echo "▸ Assembling $APP_NAME.app…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
mkdir -p "$APP/Contents/Resources"
cp "$BIN_PATH" "$APP/Contents/MacOS/$TARGET"

# Copy SwiftPM resource bundles next to the .app root, where the generated
# `Bundle.module` accessor looks for them (Bundle.main.bundleURL/<name>.bundle).
for bundle in "$(dirname "$BIN_PATH")"/*.bundle; do
    [[ -e "$bundle" ]] && cp -R "$bundle" "$APP/"
done

# App icon
if [[ -f "$ROOT/Assets/ContainerManager.icns" ]]; then
    cp "$ROOT/Assets/ContainerManager.icns" "$APP/Contents/Resources/ContainerManager.icns"
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>     <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>$TARGET</string>
    <key>CFBundleIconFile</key>        <string>ContainerManager</string>
    <key>LSMinimumSystemVersion</key>  <string>14.0</string>
    <key>NSHighResolutionCapable</key> <true/>
    <key>NSPrincipalClass</key>        <string>NSApplication</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

# Ad-hoc code signature so the app launches without Gatekeeper complaints.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || true

echo "✓ Built $APP"
echo "  Run with:  open \"$APP\"   (or: \"$APP/Contents/MacOS/$TARGET\")"
