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
  -allowProvisioningUpdates -archivePath "$ARCHIVE" archive

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$EXPORT_DIR/$APP_NAME.app" \
  -ov -format UDZO "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "Done: $DMG (signed, notarized, stapled)."

# Pass a version (e.g. ./scripts/release.sh 1.0.0) to also publish the DMG as a
# GitHub Release. Omit it to just build the DMG locally (e.g. for Gumroad only).
if [ -n "${1:-}" ]; then
    VERSION="$1"
    # Build the notes from the commits since the previous release. The new tag is
    # created by `gh release create` below, so the latest existing tag is the
    # previous release; fetch first in case it was created remotely by gh.
    git fetch --tags --quiet 2>/dev/null || true
    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    CHANGELOG=$(git log --no-merges --pretty='- %h %s' "${PREV_TAG:+$PREV_TAG..}HEAD")
    NOTES="macOS 13 or later. Browse your self-hosted Immich library in the Finder. See findich.app.

## Changelog

$CHANGELOG"
    gh release create "v$VERSION" "$DMG" \
        --repo Majorfi/immich-in-finder \
        --title "Findich $VERSION" \
        --notes "$NOTES"
    echo "Published v$VERSION to GitHub Releases."
fi
