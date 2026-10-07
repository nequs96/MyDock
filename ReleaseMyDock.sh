#!/bin/sh
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
if [ "$#" -ne 3 ]; then
  printf 'Usage: %s "Developer ID Application: Name (TEAMID)" notary-keychain-profile output-directory\n' "$0" >&2
  exit 2
fi
. "$ROOT_DIR/Scripts/product-identity.sh"
# A release is built only from a committed, tagged revision: no tracked edits anywhere and no
# untracked file among the build inputs (XcodeGen compiles every file under Sources/MyDock).
if [ -n "$(git status --porcelain --untracked-files=no)" ] ||
   [ -n "$(git status --porcelain --untracked-files=all -- Sources Resources Tools Scripts Xcode project.yml Package.swift)" ]; then
  printf 'Commit or remove local changes and untracked build inputs before releasing.\n' >&2
  exit 1
fi
RELEASE_TAG=$(git describe --exact-match --tags HEAD 2>/dev/null || true)
if [ "$RELEASE_TAG" != "v$MYDOCK_MARKETING_VERSION" ]; then
  printf 'HEAD must be tagged v%s (Product.marketingVersion) to release; found "%s".\n' "$MYDOCK_MARKETING_VERSION" "$RELEASE_TAG" >&2
  exit 1
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
# Fresh DerivedData for every release, so no product of an earlier build can reach the bundle.
mkdir -p "$ROOT_DIR/.build"
DERIVED_DATA=$(mktemp -d "$ROOT_DIR/.build/distribution-xcode.XXXXXX")
DMG_STAGING=
trap 'rm -rf "$DERIVED_DATA" ${DMG_STAGING:+"$DMG_STAGING"}' EXIT HUP INT TERM
xcodebuild -project MyDock.xcodeproj -scheme MyDock -configuration Release \
  -derivedDataPath "$DERIVED_DATA" \
  ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO build
BUILT_APP="$DERIVED_DATA/Build/Products/Release/MyDock.app"
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
