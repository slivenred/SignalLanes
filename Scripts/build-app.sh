#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="${SIGNALLANES_VERSION:-0.1.0}"
BUILD_NUMBER="${SIGNALLANES_BUILD:-1}"
BUNDLE_IDENTIFIER="${SIGNALLANES_BUNDLE_ID:-local.signal-lanes}"
DEFAULT_CODE_SIGN_IDENTITY="SignalLanes Local Code Signing"
CODE_SIGN_IDENTITY="${SIGNALLANES_CODE_SIGN_IDENTITY:-}"
CODE_SIGN_TIMEOUT="${SIGNALLANES_CODE_SIGN_TIMEOUT:-20}"

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  if security find-certificate -c "$DEFAULT_CODE_SIGN_IDENTITY" "$HOME/Library/Keychains/login.keychain-db" >/dev/null 2>&1; then
    CODE_SIGN_IDENTITY="$DEFAULT_CODE_SIGN_IDENTITY"
  else
    CODE_SIGN_IDENTITY="-"
  fi
fi

sign_app() {
  local identity="$1"
  local app_dir="$2"

  if [[ "$identity" == "-" ]]; then
    codesign --force --deep --sign "$identity" "$app_dir"
    CODE_SIGN_IDENTITY="$identity"
    return
  fi

  codesign --force --deep --sign "$identity" "$app_dir" &
  local codesign_pid=$!
  local elapsed=0

  while kill -0 "$codesign_pid" 2>/dev/null; do
    if (( elapsed >= CODE_SIGN_TIMEOUT )); then
      echo "codesign timed out after ${CODE_SIGN_TIMEOUT}s with '$identity'; falling back to ad-hoc signing." >&2
      pkill -P "$codesign_pid" 2>/dev/null || true
      kill "$codesign_pid" 2>/dev/null || true
      wait "$codesign_pid" 2>/dev/null || true
      codesign --force --deep --sign - "$app_dir"
      CODE_SIGN_IDENTITY="-"
      return
    fi

    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$codesign_pid"
  CODE_SIGN_IDENTITY="$identity"
}

swift build -c release --product SignalLanes
swift build -c release --product signallanesctl

APP_DIR="$ROOT_DIR/.build/SignalLanes.app"
rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

cp "$ROOT_DIR/.build/release/SignalLanes" "$APP_DIR/Contents/MacOS/SignalLanes"

ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.png"
if [[ -f "$ICON_SOURCE" ]]; then
  ICONSET_DIR="$ROOT_DIR/.build/AppIcon.iconset"
  rm -rf "$ICONSET_DIR"
  mkdir -p "$ICONSET_DIR"

  sips -z 16 16 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$ICON_SOURCE" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>SignalLanes</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_IDENTIFIER</string>
  <key>CFBundleName</key>
  <string>SignalLanes</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

sign_app "$CODE_SIGN_IDENTITY" "$APP_DIR"

echo "Built $APP_DIR"
echo "Signed with: $CODE_SIGN_IDENTITY"
echo "Run: open '$APP_DIR'"
echo "CLI: $ROOT_DIR/.build/release/signallanesctl"
