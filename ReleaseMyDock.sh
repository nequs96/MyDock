#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
if [ "$#" -ne 3 ]; then
  printf 'Usage: %s "Developer ID Application: Name (TEAMID)" notary-keychain-profile output-directory\n' "$0" >&2
  exit 2
fi
SIGNING_IDENTITY=$1
NOTARY_PROFILE=$2
OUTPUT_DIRECTORY=$3
case "$SIGNING_IDENTITY" in
  'Developer ID Application: '*) ;;
  *) printf 'A Developer ID Application identity is required.\n' >&2; exit 2 ;;
esac
mkdir -p "$OUTPUT_DIRECTORY"
OUTPUT_DIRECTORY=$(CDPATH= cd -- "$OUTPUT_DIRECTORY" && pwd -P)
APP_PATH="$OUTPUT_DIRECTORY/MyDock.app"
if [ -e "$APP_PATH" ]; then
  printf 'Use a fresh output directory; refusing to overwrite %s.\n' "$APP_PATH" >&2
  exit 1
fi
if ! xcodebuild -version >/dev/null 2>&1; then
  printf 'Full Xcode is required for a distribution build with App Intents metadata. Select Xcode, then rerun this script.\n' >&2
  exit 1
fi
./GenerateXcodeProject.sh
xcodebuild -project MyDock.xcodeproj -scheme MyDock -configuration Release \
  -derivedDataPath "$ROOT_DIR/.build/distribution-xcode" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
BUILT_APP="$ROOT_DIR/.build/distribution-xcode/Build/Products/Release/MyDock.app"
if [ ! -d "$BUILT_APP/Contents/Resources/Metadata.appintents" ]; then
  printf 'App Intents metadata is missing; refusing to publish an incomplete Focus integration.\n' >&2
  exit 1
fi
ditto "$BUILT_APP" "$APP_PATH"
codesign --force --options runtime --timestamp --entitlements Xcode/MyDock.entitlements --sign "$SIGNING_IDENTITY" "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
lipo "$APP_PATH/Contents/MacOS/MyDock" -verify_arch arm64 x86_64
ZIP_PATH="$OUTPUT_DIRECTORY/MyDock-notarization.zip"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"
xcrun notarytool submit "$ZIP_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$APP_PATH"
xcrun stapler validate "$APP_PATH"
spctl --assess --type execute --verbose=2 "$APP_PATH"
DMG_PATH="$OUTPUT_DIRECTORY/MyDock.dmg"
DMG_STAGING=$(mktemp -d "$OUTPUT_DIRECTORY/dmg-stage.XXXXXX")
trap 'rm -rf "$DMG_STAGING"' EXIT HUP INT TERM
ditto "$APP_PATH" "$DMG_STAGING/MyDock.app"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create -volname MyDock -srcfolder "$DMG_STAGING" -ov -format UDZO "$DMG_PATH"
codesign --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
shasum -a 256 "$DMG_PATH" > "$DMG_PATH.sha256"
python3 Scripts/WriteReleaseManifest.py --app "$APP_PATH" --output "$OUTPUT_DIRECTORY/release-manifest.json" \
  --qualification release --archive "$DMG_PATH"
printf 'Signed and notarized release: %s\n' "$DMG_PATH"
