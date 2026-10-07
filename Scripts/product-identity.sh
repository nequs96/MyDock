# Sourced (not executed) by BuildMyDock.sh and GenerateXcodeProject.sh from the repository root.
# Product.swift is the one definition of the product identity; refuse to build from a value it cannot read.
MYDOCK_PRODUCT_NAME=$(sed -n 's/.*static let name = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
MYDOCK_BUNDLE_IDENTIFIER=$(sed -n 's/.*static let bundleIdentifier = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
MYDOCK_MARKETING_VERSION=$(sed -n 's/.*static let marketingVersion = "\(.*\)".*/\1/p' Sources/MyDock/Core/Product.swift)
if [ -z "$MYDOCK_PRODUCT_NAME" ] || [ -z "$MYDOCK_BUNDLE_IDENTIFIER" ] || [ -z "$MYDOCK_MARKETING_VERSION" ]; then
  printf 'Could not read product identity from Product.swift\n' >&2
  exit 1
fi
case "$MYDOCK_PRODUCT_NAME" in
  *[!A-Za-z0-9\ ]*) printf 'Unexpected product name in Product.swift: %s\n' "$MYDOCK_PRODUCT_NAME" >&2; exit 1 ;;
esac
case "$MYDOCK_BUNDLE_IDENTIFIER" in
  *[!A-Za-z0-9.-]*) printf 'Unexpected bundle identifier in Product.swift: %s\n' "$MYDOCK_BUNDLE_IDENTIFIER" >&2; exit 1 ;;
esac
case "$MYDOCK_MARKETING_VERSION" in
  *[!0-9.]*) printf 'Unexpected marketing version in Product.swift: %s\n' "$MYDOCK_MARKETING_VERSION" >&2; exit 1 ;;
esac
# The build number counts commits, so each committed build is distinguishable in diagnostics.
# Shallow clones (CI) and source archives without history fall back to 1.
MYDOCK_BUILD_NUMBER=$(git rev-list --count HEAD 2>/dev/null || printf '1')
case "$MYDOCK_BUILD_NUMBER" in
  ''|*[!0-9]*) MYDOCK_BUILD_NUMBER=1 ;;
esac
