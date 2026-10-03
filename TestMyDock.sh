#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
DEVELOPER_DIR=$(xcode-select -p)
FRAMEWORKS="$DEVELOPER_DIR/Library/Developer/Frameworks"
DEVELOPER_LIB="$DEVELOPER_DIR/Library/Developer/usr/lib"
mkdir -p .build/module-cache .build/swiftpm-module-cache .build/swiftpm-test
VALIDATION_ROOT=$(mktemp -d "$PWD/.build/isolated-tests.XXXXXX")
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
