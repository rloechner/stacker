#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Stacker"
PROJECT_NAME="stacker.xcodeproj"
SCHEME_NAME="stacker"
CONFIGURATION="Release"
TEAM_ID="44N969GC55"
NOTARY_PROFILE="${NOTARY_PROFILE:-stacker-notary}"
EXPORT_METHOD="developer-id"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="${DIST_DIR:-"$ROOT_DIR/dist"}"
BUILD_DIR="${BUILD_DIR:-"/private/tmp/stacker-release-build"}"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_STAGING_PATH="$BUILD_DIR/dmg-staging"
VERSION="${VERSION:-}"

usage() {
  cat <<USAGE >&2
usage: $(basename "$0") [--skip-notarize]

Creates a Developer ID signed, drag-to-Applications DMG for $APP_NAME.

Environment overrides:
  NOTARY_PROFILE   Keychain profile for xcrun notarytool. Default: stacker-notary
  DIST_DIR         Output directory. Default: ./dist
  BUILD_DIR        Temporary build directory. Default: /private/tmp/stacker-release-build
  VERSION          DMG version suffix. Default: MARKETING_VERSION from the built app

Before running:
  xcrun notarytool store-credentials "$NOTARY_PROFILE"
USAGE
}

SKIP_NOTARIZE=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-notarize)
      SKIP_NOTARIZE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      exit 2
      ;;
  esac
done

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: missing required command: $1" >&2
    exit 1
  fi
}

require_command codesign
require_command hdiutil
require_command plutil
require_command security
require_command spctl
require_command xcodebuild
require_command xcrun
require_command xattr

if ! security find-identity -p codesigning -v | grep -q "Developer ID Application"; then
  echo "error: no Developer ID Application signing identity found in this keychain." >&2
  echo "Run: security find-identity -p codesigning -v" >&2
  exit 1
fi

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null
fi

rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$DIST_DIR"

echo "Archiving $APP_NAME..."
xcodebuild \
  -project "$ROOT_DIR/$PROJECT_NAME" \
  -scheme "$SCHEME_NAME" \
  -configuration "$CONFIGURATION" \
  -destination "generic/platform=macOS" \
  -archivePath "$ARCHIVE_PATH" \
  archive \
  DEVELOPMENT_TEAM="$TEAM_ID"

EXPORT_OPTIONS_PLIST="$BUILD_DIR/ExportOptions.plist"
cat > "$EXPORT_OPTIONS_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>$EXPORT_METHOD</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>teamID</key>
  <string>$TEAM_ID</string>
  <key>stripSwiftSymbols</key>
  <true/>
</dict>
</plist>
PLIST

echo "Exporting Developer ID signed app..."
xcodebuild \
  -exportArchive \
  -archivePath "$ARCHIVE_PATH" \
  -exportPath "$EXPORT_PATH" \
  -exportOptionsPlist "$EXPORT_OPTIONS_PLIST"

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: exported app not found at $APP_PATH" >&2
  exit 1
fi

if [[ -z "$VERSION" ]]; then
  VERSION="$(plutil -extract CFBundleShortVersionString raw "$APP_PATH/Contents/Info.plist")"
fi

DMG_NAME="$APP_NAME-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
MOUNT_DIR=""

cleanup_mount() {
  if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
    hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    rmdir "$MOUNT_DIR" >/dev/null 2>&1 || true
  fi
}

trap cleanup_mount EXIT

echo "Clearing release-blocking extended attributes..."
xattr -cr "$APP_PATH"

echo "Verifying app signature..."
codesign --verify --strict --verbose=2 "$APP_PATH"
codesign -dvvv --entitlements :- "$APP_PATH"
spctl -a -vv "$APP_PATH" || true

echo "Creating DMG..."
rm -rf "$DMG_STAGING_PATH" "$DMG_PATH"
mkdir -p "$DMG_STAGING_PATH"
ditto "$APP_PATH" "$DMG_STAGING_PATH/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING_PATH/Applications"
hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING_PATH" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  echo "Submitting DMG for notarization..."
  xcrun notarytool submit "$DMG_PATH" \
    --keychain-profile "$NOTARY_PROFILE" \
    --wait

  echo "Stapling notarization ticket..."
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
else
  echo "Skipping notarization. This DMG is not suitable for public distribution."
fi

echo "Verifying DMG..."
hdiutil verify "$DMG_PATH"

echo "Assessing mounted app with Gatekeeper..."
MOUNT_DIR="$(mktemp -d /private/tmp/stacker-dmg-verify.XXXXXX)"
hdiutil attach "$DMG_PATH" -readonly -nobrowse -mountpoint "$MOUNT_DIR"

MOUNTED_APP_PATH="$MOUNT_DIR/$APP_NAME.app"
if [[ ! -d "$MOUNTED_APP_PATH" ]]; then
  echo "error: mounted app not found at $MOUNTED_APP_PATH" >&2
  exit 1
fi

if [[ "$SKIP_NOTARIZE" -eq 0 ]]; then
  xcrun stapler validate "$DMG_PATH"
  spctl -a -vv "$MOUNTED_APP_PATH"
else
  spctl -a -vv "$MOUNTED_APP_PATH" || true
fi

codesign --verify --strict --verbose=2 "$MOUNTED_APP_PATH"
cleanup_mount
trap - EXIT

echo "Created $DMG_PATH"
