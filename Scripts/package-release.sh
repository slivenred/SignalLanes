#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${1:-${SIGNALLANES_VERSION:-0.1.0}}"
BUILD_NUMBER="${SIGNALLANES_BUILD:-1}"
DIST_DIR="$ROOT_DIR/dist"
APP_ZIP="$DIST_DIR/SignalLanes-$VERSION-macos.zip"
CLI_ZIP="$DIST_DIR/signallanesctl-$VERSION-macos.zip"

SIGNALLANES_VERSION="$VERSION" SIGNALLANES_BUILD="$BUILD_NUMBER" "$ROOT_DIR/Scripts/build-app.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

ditto -c -k --keepParent --norsrc --noextattr --noqtn --noacl "$ROOT_DIR/.build/SignalLanes.app" "$APP_ZIP"
ditto -c -k --norsrc --noextattr --noqtn --noacl "$ROOT_DIR/.build/release/signallanesctl" "$CLI_ZIP"

echo "Created:"
echo "  $APP_ZIP"
echo "  $CLI_ZIP"
