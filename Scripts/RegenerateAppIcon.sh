#!/bin/sh
# Regenerates the checked-in Resources/AppIcon.icns from Tools/GenerateAppIcon.swift. Run it only after
# changing the icon tool, then commit the new .icns: BuildMyDock.sh and the Xcode project both ship
# that one file, so the local app and a release always carry the same icon.
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$ROOT_DIR"
WORK=$(mktemp -d "${TMPDIR:-/tmp}/mydock-icon.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
swift Tools/GenerateAppIcon.swift "$WORK/AppIcon.iconset"
iconutil -c icns "$WORK/AppIcon.iconset" -o "$WORK/AppIcon.icns"
mv "$WORK/AppIcon.icns" Resources/AppIcon.icns
printf 'Wrote Resources/AppIcon.icns\n'
