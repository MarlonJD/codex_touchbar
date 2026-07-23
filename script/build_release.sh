#!/usr/bin/env bash
set -euo pipefail

PRODUCT_NAME="CodexTouchBar"
DISPLAY_NAME="Codex Touch Bar"
DEFAULT_SIGN_IDENTITY="Developer ID Application: Burak Karahan (UPK4SC93AN)"
DEFAULT_NOTARY_PROFILE="desktop-updater-notary"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="${1:-0.2.3}"
VERSION="${VERSION#v}"
SIGN_IDENTITY="${CODE_SIGN_IDENTITY:-$DEFAULT_SIGN_IDENTITY}"
NOTARY_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-$DEFAULT_NOTARY_PROFILE}"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$DISPLAY_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_BINARY="$APP_MACOS/$PRODUCT_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
NOTARY_ZIP="$RELEASE_DIR/$PRODUCT_NAME-v$VERSION-notary.zip"
FINAL_ZIP="$RELEASE_DIR/$PRODUCT_NAME-v$VERSION-macOS.zip"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFT_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

swift build \
  --disable-sandbox \
  --configuration release \
  --package-path "$ROOT_DIR" \
  --product "$PRODUCT_NAME"
BUILD_BINARY="$(swift build \
  --disable-sandbox \
  --configuration release \
  --package-path "$ROOT_DIR" \
  --show-bin-path)/$PRODUCT_NAME"

rm -rf "$APP_BUNDLE"
rm -f "$NOTARY_ZIP" "$FINAL_ZIP"
mkdir -p "$APP_MACOS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
cp "$ROOT_DIR/Resources/Info.plist" "$INFO_PLIST"
plutil -replace CFBundleShortVersionString -string "$VERSION" "$INFO_PLIST"
plutil -lint "$INFO_PLIST" >/dev/null

codesign \
  --force \
  --options runtime \
  --timestamp \
  --sign "$SIGN_IDENTITY" \
  "$APP_BUNDLE"
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARY_ZIP"
xcrun notarytool submit \
  "$NOTARY_ZIP" \
  --keychain-profile "$NOTARY_PROFILE" \
  --wait
xcrun stapler staple "$APP_BUNDLE"
xcrun stapler validate "$APP_BUNDLE"
spctl --assess --type execute --verbose=4 "$APP_BUNDLE"

/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$FINAL_ZIP"
rm -f "$NOTARY_ZIP"

echo "$FINAL_ZIP"
