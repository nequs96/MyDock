#!/bin/sh
set -eu
(set -o pipefail) 2>/dev/null && set -o pipefail

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
if ! command -v xcodegen >/dev/null 2>&1; then
  printf 'XcodeGen is required: brew install xcodegen\n' >&2
  exit 1
fi
. "$ROOT_DIR/Scripts/product-identity.sh"
export MYDOCK_PRODUCT_NAME MYDOCK_BUNDLE_IDENTIFIER MYDOCK_MARKETING_VERSION MYDOCK_BUILD_NUMBER
xcodegen generate --spec project.yml --project "$ROOT_DIR" --project-root "$ROOT_DIR"
