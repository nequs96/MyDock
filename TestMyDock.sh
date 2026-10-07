#!/bin/sh
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
DEVELOPER_DIR=$(xcode-select -p)
# Command Line Tools keep Swift Testing under Library/Developer; full Xcode
# (CI runners) keeps it in the macOS platform. Use whichever layout exists.
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
DEVELOPER_LIB="$DEVELOPER_DIR/Library/Developer/usr/lib"
if [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
  PLATFORM_DEVELOPER="$DEVELOPER_DIR/Platforms/MacOSX.platform/Developer"
  FRAMEWORKS="$PLATFORM_DEVELOPER/Library/Frameworks"
  DEVELOPER_LIB="$PLATFORM_DEVELOPER/usr/lib"
fi
if [ ! -d "$FRAMEWORKS/Testing.framework" ]; then
  echo "Swift Testing framework not found under $DEVELOPER_DIR" >&2
  exit 1
fi
mkdir -p .build/module-cache .build/swiftpm-module-cache .build/swiftpm-test
VALIDATION_ROOT=$(mktemp -d "$PWD/.build/isolated-tests.XXXXXX")
# Each run gets a fresh private root. Remove it afterwards; MYDOCK_KEEP_VALIDATION_ROOT=1 keeps it to inspect.
remove_validation_root() {
  status=$?
  if [ "${MYDOCK_KEEP_VALIDATION_ROOT:-0}" = 1 ]; then
    printf 'Kept the validation root at %s\n' "$VALIDATION_ROOT" >&2
  else
    rm -rf "$VALIDATION_ROOT"
  fi
  exit "$status"
}
trap remove_validation_root EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
MYDOCK_VALIDATION_ROOT="$VALIDATION_ROOT" \
MYDOCK_UNIT_TEST_HOST=1 \
MYDOCK_TEST_BUILD=1 \
SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/swiftpm-module-cache" \
CLANG_MODULE_CACHE_PATH="$PWD/.build/module-cache" \
swift test --disable-sandbox --scratch-path .build/swiftpm-test --triple "$(uname -m)-apple-macosx14.0" \
  -Xswiftc -module-cache-path -Xswiftc "$PWD/.build/module-cache" \
  -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$DEVELOPER_LIB" "$@"
