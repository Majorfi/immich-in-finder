#!/usr/bin/env bash
# Build, notarize, staple, and package Findich.app as a DMG.
# One-time setup and usage: see "Releasing" in README.md.
set -euo pipefail

APP_NAME="Findich"
SCHEME="ImmichDrive"
NOTARY_PROFILE="${NOTARY_PROFILE:-findich-notary}"
BUILD_DIR="build"
ARCHIVE="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_DIR="$BUILD_DIR/export"
DMG="$BUILD_DIR/$APP_NAME.dmg"

xcodegen generate

xcodebuild -project ImmichDrive.xcodeproj -scheme "$SCHEME" \
  -configuration Release -destination 'generic/platform=macOS' \
  -archivePath "$ARCHIVE" archive

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$EXPORT_DIR"

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$EXPORT_DIR/$APP_NAME.app" \
  -ov -format UDZO "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "Done: $DMG (signed, notarized, stapled)."
