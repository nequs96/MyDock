#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT_DIR"
if ! command -v xcodegen >/dev/null 2>&1; then
  printf 'XcodeGen is required: brew install xcodegen\n' >&2
  exit 1
fi
MYDOCK_PRODUCT_NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
MYDOCK_BUNDLE_IDENTIFIER=$(sed -n 's/.*static let bundleIdentifier = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
MYDOCK_MARKETING_VERSION=$(sed -n 's/.*static let marketingVersion = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
if [ -z "$MYDOCK_PRODUCT_NAME" ] || [ -z "$MYDOCK_BUNDLE_IDENTIFIER" ] || [ -z "$MYDOCK_MARKETING_VERSION" ]; then
  printf 'Could not read product identity from Product.swift\n' >&2
  exit 1
fi
export MYDOCK_PRODUCT_NAME MYDOCK_BUNDLE_IDENTIFIER MYDOCK_MARKETING_VERSION
xcodegen generate --spec project.yml --project "$ROOT_DIR" --project-root "$ROOT_DIR"
