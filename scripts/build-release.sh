#!/bin/bash
# Build, sign (Developer ID), notarize, and staple Container Manager for distribution.
#
# Requirements:
#   - Full Xcode installed (this uses `xcodebuild`, not just Command Line Tools).
#   - XcodeGen:            brew install xcodegen
#   - A "Developer ID Application" certificate in your keychain.
#   - A stored notarytool credential profile named by NOTARY_PROFILE (default
#     "container-manager-notary"). Create it once with:
#
#       xcrun notarytool store-credentials container-manager-notary \
#         --apple-id "you@example.com" \
#         --team-id MKTMGKS2F9 \
#         --password "app-specific-password"   # from appleid.apple.com
#
# Usage:  ./scripts/build-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

SCHEME="Container Manager"
APP_NAME="Container Manager"
NOTARY_PROFILE="${NOTARY_PROFILE:-container-manager-notary}"
BUILD_DIR="$ROOT/build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
APP="$EXPORT_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/$APP_NAME.zip"

echo "▸ Regenerating Xcode project…"
xcodegen generate

echo "▸ Archiving…"
rm -rf "$ARCHIVE" "$EXPORT_DIR"
xcodebuild archive \
    -project "$APP_NAME.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Release \
    -archivePath "$ARCHIVE" \
    -destination "generic/platform=macOS" \
    -allowProvisioningUpdates

echo "▸ Exporting Developer ID-signed app…"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$ROOT/scripts/ExportOptions.plist" \
    -allowProvisioningUpdates

echo "▸ Zipping for notarization…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "▸ Submitting to Apple notary service (this can take a few minutes)…"
xcrun notarytool submit "$ZIP" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

echo "▸ Stapling the notarization ticket…"
xcrun stapler staple "$APP"

echo "▸ Re-zipping the stapled app for distribution…"
rm -f "$ZIP"
/usr/bin/ditto -c -k --keepParent "$APP" "$ZIP"

echo "✓ Done."
echo "  Signed & notarized app: $APP"
echo "  Distributable zip:      $ZIP"
echo
echo "  Verify with:"
echo "    codesign --verify --deep --strict --verbose=2 \"$APP\""
echo "    spctl --assess --type execute --verbose \"$APP\""
