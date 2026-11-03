#!/bin/bash
# Builds the production Awake.app, Awake-<version>-macos-arm64.dmg, and
# Awake-<version>-macos-arm64.zip in dist/ alongside SHA256SUMS.txt.
#
# - Automatically signs with 'Developer ID Application' (Hardened Runtime +
#   secure timestamp + WidgetKit entitlements) when available in Keychain,
#   and notarizes + staples via `xcrun notarytool` if a notary profile is active.
# - Falls back to clean ad-hoc signing otherwise.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="$(sed -n 's/^AWAKE_VERSION="\([^"]*\)"/\1/p' "$ROOT/awake" | head -1)"
VERSION="${VERSION:-1.0.1}"
DIST="$ROOT/dist"
NOTARY_PROFILE="${AWAKE_NOTARY_PROFILE:-scribiz}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/awake-dmg.XXXXXX")"
trap 'hdiutil detach -quiet "$WORK/mnt" 2>/dev/null || true; rm -rf "$WORK"' EXIT
trap 'exit 130' HUP INT TERM

# Auto-detect Developer ID Application signing identity in Keychain (zero hardcoded IDs in repo)
DEV_ID_CERT="${AWAKE_SIGN_IDENTITY:-}"
DEV_ID_TEAM="${AWAKE_TEAM_ID:-}"
if [ -z "$DEV_ID_CERT" ]; then
  DEV_ID_CERT="$(security find-identity -v -p codesigning 2>/dev/null \
    | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' \
    | head -1 || true)"
fi
if [ -n "$DEV_ID_CERT" ] && [ -z "$DEV_ID_TEAM" ]; then
  DEV_ID_TEAM="$(printf '%s\n' "$DEV_ID_CERT" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p' | head -1 || true)"
fi

cd "$ROOT/control"

if [ -n "$DEV_ID_CERT" ] && [ -n "$DEV_ID_TEAM" ]; then
  echo "Building production Awake.app v$VERSION signed with Developer ID ($DEV_ID_TEAM)..."
  xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$WORK/derived" \
    DEVELOPMENT_TEAM="$DEV_ID_TEAM" \
    CODE_SIGN_IDENTITY="$DEV_ID_CERT" \
    OTHER_CODE_SIGN_FLAGS="--timestamp" \
    CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
    MARKETING_VERSION="$VERSION" -quiet build
else
  echo "Building Awake.app v$VERSION (ad-hoc signed)..."
  xcodebuild -project Awake.xcodeproj -scheme Awake -configuration Release \
    -destination "platform=macOS,arch=arm64" \
    -derivedDataPath "$WORK/derived" \
    CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" AD_HOC_CODE_SIGNING_ALLOWED=YES \
    MARKETING_VERSION="$VERSION" -quiet build
  xattr -cr "$WORK/derived/Build/Products/Release/Awake.app"
  codesign --force --sign - \
    --entitlements "$ROOT/control/Widget/AwakeControl.entitlements" \
    "$WORK/derived/Build/Products/Release/Awake.app/Contents/PlugIns/AwakeControl.appex"
  codesign --force --sign - "$WORK/derived/Build/Products/Release/Awake.app"
fi

APP_BUNDLE="$WORK/derived/Build/Products/Release/Awake.app"
codesign --verify --deep --strict "$APP_BUNDLE"

# Notarize and staple Awake.app first if notarytool credentials are unlocked
NOTARIZED=0
if [ -n "$DEV_ID_CERT" ] && xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1; then
  echo "Notarizing Awake.app with Apple Notary Service (profile: $NOTARY_PROFILE)..."
  /usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$WORK/Awake-notarize.zip"
  if xcrun notarytool submit "$WORK/Awake-notarize.zip" --keychain-profile "$NOTARY_PROFILE" --wait; then
    xcrun stapler staple "$APP_BUNDLE"
    xcrun stapler validate "$APP_BUNDLE"
    NOTARIZED=1
  fi
fi

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
DS_STORE="$ROOT/packaging/dmg/DS_Store"
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

mkdir -p "$DIST" "$WORK/staging"
/usr/bin/ditto "$APP_BUNDLE" "$WORK/staging/Awake.app"
ln -s /Applications "$WORK/staging/Applications"
if [ -f "$BG_TIFF" ]; then
  cp "$BG_TIFF" "$WORK/staging/.background.tiff"
fi
if [ -f "$DS_STORE" ]; then
  cp "$DS_STORE" "$WORK/staging/.DS_Store"
fi

DMG_PATH="$DIST/Awake-$VERSION-macos-arm64.dmg"
ZIP_PATH="$DIST/Awake-$VERSION-macos-arm64.zip"
rm -f "$DMG_PATH" "$ZIP_PATH"

hdiutil create -quiet -fs APFS -format ULFO -volname "Awake" -srcfolder "$WORK/staging" "$DMG_PATH"
if [ -n "$DEV_ID_CERT" ]; then
  codesign --force --timestamp --sign "$DEV_ID_CERT" "$DMG_PATH"
  if [ "$NOTARIZED" -eq 1 ]; then
    echo "Notarizing and stapling $(basename "$DMG_PATH")..."
    xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
    xcrun stapler staple "$DMG_PATH"
    xcrun stapler validate "$DMG_PATH"
  fi
fi

/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_BUNDLE" "$ZIP_PATH"

(
  cd "$DIST"
  shasum -a 256 "Awake-$VERSION-macos-arm64.dmg" "Awake-$VERSION-macos-arm64.zip" > SHA256SUMS.txt
)

echo "Built release artifacts (Developer ID: ${DEV_ID_TEAM:-none}, Notarized: $NOTARIZED):"
cat "$DIST/SHA256SUMS.txt"
