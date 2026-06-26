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

# Optional version arg (e.g. ./scripts/release.sh 1.2.0). When set, it stamps the
# build's CFBundleShortVersionString and CFBundleVersion, so a distributed DMG
# carries the real version that auto-update compares against. Without it, the
# build uses project.yml's version, which is fine for a local dev build only.
VERSION="${1:-}"

xcodegen generate

xcodebuild -project ImmichDrive.xcodeproj -scheme "$SCHEME" \
  -configuration Release -destination 'generic/platform=macOS' \
  -allowProvisioningUpdates -archivePath "$ARCHIVE" archive \
  ${VERSION:+MARKETING_VERSION=$VERSION} ${VERSION:+CURRENT_PROJECT_VERSION=$VERSION}

xcodebuild -exportArchive -archivePath "$ARCHIVE" \
  -exportOptionsPlist scripts/ExportOptions.plist -exportPath "$EXPORT_DIR" \
  -allowProvisioningUpdates

rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$EXPORT_DIR/$APP_NAME.app" \
  -ov -format UDZO "$DMG"

xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

echo "Done: $DMG (signed, notarized, stapled)."

# When a version was passed, also publish the DMG as a GitHub Release. Omit the
# version to just build the DMG locally (e.g. for Gumroad only).
if [ -n "$VERSION" ]; then
    # Build the notes from the commits since the previous release. The new tag is
    # created by `gh release create` below, so the latest existing tag is the
    # previous release; fetch first in case it was created remotely by gh.
    git fetch --tags --quiet 2>/dev/null || true
    PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")
    CHANGELOG=$(git log --no-merges --pretty='- %h %s' "${PREV_TAG:+$PREV_TAG..}HEAD")
    NOTES="macOS 13 or later. Browse your self-hosted Immich library in the Finder. See findich.app.

## Changelog

$CHANGELOG"
    # Idempotent: if a previous run already created this release, just re-upload
    # the DMG, so a failure in a later step can be fixed by re-running the script.
    if gh release view "v$VERSION" --repo Majorfi/immich-in-finder >/dev/null 2>&1; then
        gh release upload "v$VERSION" "$DMG" --repo Majorfi/immich-in-finder --clobber
        echo "Re-uploaded the DMG to the existing v$VERSION release."
    else
        gh release create "v$VERSION" "$DMG" \
            --repo Majorfi/immich-in-finder \
            --title "Findich $VERSION" \
            --notes "$NOTES"
        echo "Published v$VERSION to GitHub Releases."
    fi

    # Update the Sparkle appcast (signed with the EdDSA key in your Keychain) so
    # installed copies can auto-update. It is served from the site at
    # findich.app/appcast.xml, so commit and push site/ afterwards to publish it.
    SIGN_UPDATE="${SIGN_UPDATE:-$(find ~/Library/Developer/Xcode/DerivedData -path '*artifacts/sparkle/Sparkle/bin/sign_update' | head -1)}"
    if [ -z "$SIGN_UPDATE" ]; then
        echo "sign_update not found. Build the app once so SPM resolves Sparkle, then re-run." >&2
        exit 1
    fi
    SIG_AND_LEN=$("$SIGN_UPDATE" "$DMG")
    DMG_URL="https://github.com/Majorfi/immich-in-finder/releases/download/v$VERSION/$APP_NAME.dmg"
    python3 scripts/update_appcast.py site/public/appcast.xml "$VERSION" "$DMG_URL" "$SIG_AND_LEN" "$CHANGELOG"

    # Publish the appcast so installed copies can auto-update; it is served from
    # findich.app/appcast.xml, so committing and pushing site/ deploys it.
    if ! git diff --quiet -- site/public/appcast.xml; then
        git add site/public/appcast.xml
        git commit -m "chore(site): publish $VERSION appcast"
        git push
        echo "Committed and pushed the appcast."
    fi

    # Bump the Homebrew cask with the sha of the DMG we just built and uploaded
    # (same artifact, no re-download). TAP_DIR defaults to a sibling clone of the
    # tap repo; override it if yours lives elsewhere. Skipped if the cask is absent.
    REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
    TAP_DIR="${TAP_DIR:-$REPO_ROOT/../homebrew-tap}"
    CASK="$TAP_DIR/Casks/$(echo "$APP_NAME" | tr '[:upper:]' '[:lower:]').rb"
    if [ -f "$CASK" ]; then
        SHA=$(shasum -a 256 "$DMG" | awk '{print $1}')
        sed -i '' -E "s/version \"[^\"]+\"/version \"$VERSION\"/; s/sha256 \"[^\"]+\"/sha256 \"$SHA\"/" "$CASK"
        if git -C "$TAP_DIR" diff --quiet -- "$CASK"; then
            echo "Cask already at $VERSION; nothing to push."
        else
            git -C "$TAP_DIR" commit -m "findich $VERSION" -- "$CASK"
            git -C "$TAP_DIR" push
            echo "Bumped and pushed the Homebrew cask ($VERSION)."
        fi
    else
        echo "Cask not found at $CASK; skipping the Homebrew bump (set TAP_DIR?)." >&2
    fi
fi
