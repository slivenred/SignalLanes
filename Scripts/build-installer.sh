#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-${SIGNALLANES_VERSION:-0.1.0}}"
BUILD_NUMBER="${SIGNALLANES_BUILD:-1}"
BUNDLE_IDENTIFIER="${SIGNALLANES_BUNDLE_ID:-local.signal-lanes}"
INSTALLER_IDENTIFIER="${SIGNALLANES_INSTALLER_ID:-$BUNDLE_IDENTIFIER.installer}"
DIST_DIR="$ROOT_DIR/dist"
PKG_ROOT="$ROOT_DIR/.build/pkg-root"
PKG_PATH="$DIST_DIR/SignalLanes-$VERSION-macos-installer.pkg"

SIGNALLANES_VERSION="$VERSION" SIGNALLANES_BUILD="$BUILD_NUMBER" "$ROOT_DIR/Scripts/build-app.sh"

rm -rf "$PKG_ROOT"
mkdir -p "$PKG_ROOT/Applications" "$PKG_ROOT/usr/local/bin" "$DIST_DIR"

ditto --norsrc --noextattr --noacl "$ROOT_DIR/.build/SignalLanes.app" "$PKG_ROOT/Applications/SignalLanes.app"
install -m 0755 "$ROOT_DIR/.build/release/signallanesctl" "$PKG_ROOT/usr/local/bin/signallanesctl"
find "$PKG_ROOT" -name '._*' -delete
xattr -cr "$PKG_ROOT" 2>/dev/null || true

PKGBUILD_ARGS=(
  --root "$PKG_ROOT"
  --identifier "$INSTALLER_IDENTIFIER"
  --version "$VERSION"
  --install-location "/"
  --filter '\.DS_Store$'
  --filter '(^|/)\._[^/]*$'
  --filter '(^|/)\.svn($|/)'
  --filter '(^|/)CVS($|/)'
)

if [[ -n "${SIGNALLANES_PKG_SIGN_ID:-}" ]]; then
  PKGBUILD_ARGS+=(--sign "$SIGNALLANES_PKG_SIGN_ID")
fi

COPYFILE_DISABLE=1 pkgbuild "${PKGBUILD_ARGS[@]}" "$PKG_PATH"

echo "Created:"
echo "  $PKG_PATH"
echo
echo "Installs:"
echo "  /Applications/SignalLanes.app"
echo "  /usr/local/bin/signallanesctl"
