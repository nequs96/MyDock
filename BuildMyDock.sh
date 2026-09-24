#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
PRODUCT_NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
BUNDLE_IDENTIFIER=$(sed -n 's/.*static let bundleIdentifier = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
PRODUCT_VERSION=$(sed -n 's/.*static let marketingVersion = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
mkdir -p .build/module-cache .build/swiftpm-module-cache .build/swiftpm-release-arm64 .build/swiftpm-release-x86_64
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift build --disable-sandbox -c release --scratch-path .build/swiftpm-release-arm64 \
  --triple arm64-apple-macosx13.0 \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift build --disable-sandbox -c release --scratch-path .build/swiftpm-release-x86_64 \
  --triple x86_64-apple-macosx13.0 \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache"
UNIVERSAL_BINARY="$ROOT_DIR/.build/MyDock-universal"
lipo -create \
  "$ROOT_DIR/.build/swiftpm-release-arm64/arm64-apple-macosx/release/MyDock" \
  "$ROOT_DIR/.build/swiftpm-release-x86_64/x86_64-apple-macosx/release/MyDock" \
  -output "$UNIVERSAL_BINARY"
APP="$ROOT_DIR/build/MyDock.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$UNIVERSAL_BINARY" "$APP/Contents/MacOS/MyDock"
swift "$ROOT_DIR/Tools/GenerateAppIcon.swift" "$ROOT_DIR/.build/AppIcon.iconset"
iconutil -c icns "$ROOT_DIR/.build/AppIcon.iconset" -o "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleExecutable</key><string>MyDock</string>
  <key>CFBundleIdentifier</key><string>__BUNDLE_IDENTIFIER__</string>
  <key>CFBundleName</key><string>__PRODUCT_NAME__</string>
  <key>CFBundleDisplayName</key><string>__PRODUCT_NAME__</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleSupportedPlatforms</key><array><string>MacOSX</string></array>
  <key>CFBundleInfoDictionaryVersion</key><string>6.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>CFBundleShortVersionString</key><string>__PRODUCT_VERSION__</string>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSCalendarsFullAccessUsageDescription</key><string>MyDock reads selected calendar events for the Calendar widget.</string>
  <key>NSCalendarsUsageDescription</key><string>MyDock reads selected calendar events for the Calendar widget.</string>
  <key>NSRemindersFullAccessUsageDescription</key><string>MyDock reads, adds, and completes reminders when you use the Reminders widget.</string>
  <key>NSRemindersUsageDescription</key><string>MyDock reads and updates reminders when you use the Reminders widget.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>MyDock uses your location only when you choose current-location weather.</string>
  <key>NSAppleEventsUsageDescription</key><string>MyDock reads and controls Music or Spotify while you use the Now Playing widget, or asks Finder to empty Trash after you confirm.</string>
</dict></plist>
PLIST
sed -i '' "s/__PRODUCT_NAME__/$PRODUCT_NAME/g; s/__BUNDLE_IDENTIFIER__/$BUNDLE_IDENTIFIER/g; s/__PRODUCT_VERSION__/$PRODUCT_VERSION/g" "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$APP"
