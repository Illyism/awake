#!/bin/bash
# Builds a clean, privacy-safe (ad-hoc signed, zero personal Team ID) release
# Awake.app, Awake-<version>-macos-arm64.dmg, and Awake-<version>-macos-arm64.zip
# in dist/ alongside SHA256SUMS.txt.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^AWAKE_VERSION="\([^"]*\)"/\1/p' "$ROOT/awake" | head -1)"
VERSION="${VERSION:-1.0.0}"
DIST="$ROOT/dist"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/awake-dmg.XXXXXX")"
trap 'hdiutil detach -quiet "$WORK/mnt" 2>/dev/null || true; rm -rf "$WORK"' EXIT
trap 'exit 130' HUP INT TERM

echo "Building clean release Awake.app v$VERSION (ad-hoc signed, zero personal identifiers)..."
cd "$ROOT/control"
if command -v xcodegen >/dev/null 2>&1; then
  xcodegen generate >/dev/null
fi

xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
  -destination "platform=macOS,arch=arm64" \
  -derivedDataPath "$WORK/derived" \
  CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" AD_HOC_CODE_SIGNING_ALLOWED=YES \
  MARKETING_VERSION="$VERSION" -quiet build

APP_BUNDLE="$WORK/derived/Build/Products/Release/Awake.app"
# Strip extended attributes and sign inner extension with its sandbox entitlements before outer bundle
xattr -cr "$APP_BUNDLE"
codesign --force --sign - \
  --entitlements "$ROOT/control/Widget/AwakeControl.entitlements" \
  "$APP_BUNDLE/Contents/PlugIns/AwakeControl.appex"
codesign --force --sign - "$APP_BUNDLE"
codesign --verify --deep --strict "$APP_BUNDLE"

# Render Retina DMG background if Chrome/Brave is available
CHROME="${CHROME:-}"
for candidate in \
  "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
  "/Applications/Brave Browser.app/Contents/MacOS/Brave Browser"; do
  if [ -z "$CHROME" ] && [ -x "$candidate" ]; then
    CHROME="$candidate"
  fi
done

BG_TIFF="$ROOT/packaging/dmg/background.tiff"
if [ -n "$CHROME" ]; then
  for scale in 1 2; do
    "$CHROME" --headless --disable-gpu --hide-scrollbars --user-data-dir="$WORK/chrome-$scale" \
      --force-device-scale-factor="$scale" --window-size=660,400 \
      --screenshot="$WORK/bg@${scale}x.png" "file://$ROOT/packaging/dmg/background.html" 2>/dev/null || true
  done
  if [ -f "$WORK/bg@1x.png" ] && [ -f "$WORK/bg@2x.png" ]; then
    tiffutil -cathidpicheck "$WORK/bg@1x.png" "$WORK/bg@2x.png" -out "$BG_TIFF" >/dev/null 2>&1 || true
  fi
fi

mkdir -p "$DIST" "$WORK/staging/.background"
/usr/bin/ditto "$APP_BUNDLE" "$WORK/staging/Awake.app"
ln -s /Applications "$WORK/staging/Applications"
if [ -f "$BG_TIFF" ]; then
  cp "$BG_TIFF" "$WORK/staging/.background/background.tiff"
fi

DMG_PATH="$DIST/Awake-$VERSION-macos-arm64.dmg"
ZIP_PATH="$DIST/Awake-$VERSION-macos-arm64.zip"
rm -f "$DMG_PATH" "$ZIP_PATH"

hdiutil create -quiet -fs HFS+ -format UDZO -volname "Awake" -srcfolder "$WORK/staging" "$DMG_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

(
  cd "$DIST"
  shasum -a 256 "Awake-$VERSION-macos-arm64.dmg" "Awake-$VERSION-macos-arm64.zip" > SHA256SUMS.txt
)

echo "Built release artifacts:"
cat "$DIST/SHA256SUMS.txt"
