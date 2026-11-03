#!/bin/bash
# Build the Awake Control Center toggle + Menu Bar app and install it.
# Automatically uses a local 'Apple Development' certificate if available
# (required by macOS WidgetKit for Control Center widgets), and falls back
# to ad-hoc signing otherwise so the Menu Bar app and CLI always work.
set -euo pipefail

cd "$(dirname "$0")"
REPO_DIR="$(cd .. && pwd)"
APP_DEST="${AWAKE_APP_DIR:-$HOME/Applications}/Awake.app"
BIN_DIR="${AWAKE_BIN_DIR:-$HOME/.local/bin}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/awake-build.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 130' HUP INT TERM

# 1. Link CLI binaries (~/.local/bin/awake and ~/.local/bin/asleep)
mkdir -p "$BIN_DIR"
ln -sf "$REPO_DIR/awake" "$BIN_DIR/awake"
ln -sf awake "$BIN_DIR/asleep"

# 2. Detect optional Apple Development signing team in Keychain
TEAM="${DEVELOPMENT_TEAM:-}"
if [ -z "$TEAM" ]; then
  CERT_CN="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Apple Development:[^"]*\)".*/\1/p' \
    | head -1 || true)"
  if [ -n "$CERT_CN" ]; then
    TEAM="$(security find-certificate -c "$CERT_CN" -p 2>/dev/null \
      | openssl x509 -noout -subject 2>/dev/null \
      | sed -n 's/.*OU=\([A-Z0-9]\{10\}\).*/\1/p' \
      | head -1 || true)"
  fi
fi

if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

if [ -n "$TEAM" ]; then
  echo "Building Awake.app (Control Center + Menu Bar) with local Apple Development team..."
  xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$WORK/derived" DEVELOPMENT_TEAM="$TEAM" -quiet build
else
  echo "No 'Apple Development' cert in Keychain — building Awake.app with ad-hoc signing..."
  echo "  (Tip: add a free Apple ID in Xcode > Settings > Accounts to enable the macOS 26 Control Center widget)"
  xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
    -destination "platform=macOS,arch=$(uname -m)" \
    -derivedDataPath "$WORK/derived" CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" AD_HOC_CODE_SIGNING_ALLOWED=YES -quiet build
fi

APP="$WORK/derived/Build/Products/Release/Awake.app"
killall Awake AwakeControl 2>/dev/null || true
mkdir -p "$(dirname "$APP_DEST")"
rm -rf "$APP_DEST"
/usr/bin/ditto "$APP" "$APP_DEST"
open -g "$APP_DEST"
"$APP_DEST/Contents/MacOS/Awake" --reload 2>/dev/null || true

echo "Installed $APP_DEST"
echo "Linked $BIN_DIR/awake and $BIN_DIR/asleep"
echo "Add to Control Center: Control Center > Edit Controls > search \"Awake\"."
