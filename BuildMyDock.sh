#!/bin/sh
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
. "$ROOT_DIR/Scripts/product-identity.sh"
PRODUCT_NAME=$MYDOCK_PRODUCT_NAME
if [ "$#" -eq 0 ]; then
  OUTPUT_APP=build/MyDock.app
elif [ "$#" -eq 2 ] && [ "$1" = --output ]; then
  OUTPUT_APP=$2
else
  printf 'Usage: %s [--output path/to/MyDock.app]\n' "$0" >&2
  exit 2
fi
case "$OUTPUT_APP" in
  /*) APP=$OUTPUT_APP ;;
  *) APP=$ROOT_DIR/$OUTPUT_APP ;;
esac
mkdir -p "$(dirname "$APP")"
APP=$(CDPATH= cd -- "$(dirname "$APP")" && pwd -P)/$(basename "$APP")

ensure_output_is_not_running() {
  if ! command -v pgrep >/dev/null 2>&1 || ! command -v lsof >/dev/null 2>&1; then
    printf 'Cannot check whether %s is running; refusing to overwrite it.\n' "$APP" >&2
    exit 1
  fi
  RUNNING_PIDS=$(pgrep -x "$PRODUCT_NAME" || true)
  for RUNNING_PID in $RUNNING_PIDS; do
    if lsof -nP -a -p "$RUNNING_PID" -d txt -Fn 2>/dev/null |
       grep -Fx "n$APP/Contents/MacOS/$PRODUCT_NAME" >/dev/null; then
      printf 'Refusing to overwrite a running app: %s\n' "$APP" >&2
      printf 'Quit MyDock, rebuild, then reopen build/MyDock.app.\n' >&2
      printf 'Use --output under .build/ only for isolated validation bundles.\n' >&2
      exit 1
    fi
  done
}

source_fingerprint() {
  {
    find Sources/MyDock Resources Tools -type f -exec shasum -a 256 {} + | LC_ALL=C sort
    shasum -a 256 Package.swift BuildMyDock.sh Scripts/product-identity.sh Xcode/MyDock-Info.plist
  } | shasum -a 256 | cut -d ' ' -f 1
}

assert_sources_unchanged() {
  CURRENT_FINGERPRINT=$(source_fingerprint)
  if [ "$CURRENT_FINGERPRINT" != "$SOURCE_FINGERPRINT" ]; then
    printf 'Source files changed during the build; the release bundle was not updated.\n' >&2
    exit 1
  fi
}

ensure_output_is_not_running
SOURCE_FINGERPRINT=$(source_fingerprint)
mkdir -p .build/module-cache .build/swiftpm-module-cache .build/swiftpm-release-arm64 .build/swiftpm-release-x86_64
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift build --disable-sandbox -c release --scratch-path .build/swiftpm-release-arm64 \
  --triple arm64-apple-macosx13.0 \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
assert_sources_unchanged
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift build --disable-sandbox -c release --scratch-path .build/swiftpm-release-x86_64 \
  --triple x86_64-apple-macosx13.0 \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
assert_sources_unchanged
UNIVERSAL_BINARY="$ROOT_DIR/.build/MyDock-universal"
lipo -create \
  "$ROOT_DIR/.build/swiftpm-release-arm64/arm64-apple-macosx/release/MyDock" \
  "$ROOT_DIR/.build/swiftpm-release-x86_64/x86_64-apple-macosx/release/MyDock" \
  -output "$UNIVERSAL_BINARY"
# Assemble and sign a complete bundle off to the side, so a failed step never leaves the
# canonical app half-updated, and no file from an earlier build survives into this one.
STAGE="$ROOT_DIR/.build/app-stage/MyDock.app"
rm -rf "$STAGE"
mkdir -p "$STAGE/Contents/MacOS" "$STAGE/Contents/Resources"
cp "$UNIVERSAL_BINARY" "$STAGE/Contents/MacOS/MyDock"
swift "$ROOT_DIR/Tools/GenerateAppIcon.swift" "$ROOT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$ROOT_DIR/.build/AppIcon.iconset" -o "$STAGE/Contents/Resources/AppIcon.icns"
# Xcode/MyDock-Info.plist (generated from project.yml) is the one Info.plist definition; fill in the
# build settings Xcode would expand.
PLIST="$STAGE/Contents/Info.plist"
cp Xcode/MyDock-Info.plist "$PLIST"
plutil -replace CFBundleDevelopmentRegion -string en "$PLIST"
plutil -replace CFBundleExecutable -string MyDock "$PLIST"
plutil -replace CFBundleIdentifier -string "$MYDOCK_BUNDLE_IDENTIFIER" "$PLIST"
plutil -replace CFBundleName -string "$PRODUCT_NAME" "$PLIST"
plutil -replace CFBundleDisplayName -string "$PRODUCT_NAME" "$PLIST"
plutil -replace CFBundleShortVersionString -string "$MYDOCK_MARKETING_VERSION" "$PLIST"
plutil -replace CFBundleVersion -string "$MYDOCK_BUILD_NUMBER" "$PLIST"
plutil -replace CFBundleSupportedPlatforms -json '["MacOSX"]' "$PLIST"
if grep -F '$(' "$PLIST" >/dev/null; then
  printf 'Info.plist still contains an unexpanded build setting; teach BuildMyDock.sh to fill it in.\n' >&2
  exit 1
fi
plutil -lint "$PLIST" >/dev/null
printf 'APPL????' > "$STAGE/Contents/PkgInfo"
codesign --force --sign - "$STAGE"
codesign --verify --strict "$STAGE"
assert_sources_unchanged
ensure_output_is_not_running
rm -rf "$APP.old"
if [ -e "$APP" ]; then
  mv "$APP" "$APP.old"
fi
mv "$STAGE" "$APP"
rm -rf "$APP.old"
printf 'Built %s\n' "$APP"
