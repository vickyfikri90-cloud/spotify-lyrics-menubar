#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LyricsMenuBar"
BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"
DMG_FILE="$APP_NAME.dmg"
STAGING_DIR=".dmg-staging"

echo "==> Building release executable..."
swift build -c release

echo "==> Assembling .app bundle..."
rm -rf "$BUNDLE"
mkdir -p "$BUNDLE/Contents/MacOS"
mkdir -p "$BUNDLE/Contents/Resources"

cp "$BUILD_DIR/$APP_NAME" "$BUNDLE/Contents/MacOS/"
cp Info.plist "$BUNDLE/Contents/"

echo "==> Ad-hoc code signing..."
codesign --force --deep --sign - "$BUNDLE"

# Skip DMG creation when invoked as ./build.sh --no-dmg (useful during dev).
if [[ "${1:-}" == "--no-dmg" ]]; then
    echo "==> Done: $(pwd)/$BUNDLE (DMG skipped)"
    exit 0
fi

echo "==> Creating .dmg for distribution..."
rm -rf "$STAGING_DIR" "$DMG_FILE"
mkdir -p "$STAGING_DIR"
cp -R "$BUNDLE" "$STAGING_DIR/"
ln -s /Applications "$STAGING_DIR/Applications"

hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov -format UDZO \
    "$DMG_FILE" >/dev/null

rm -rf "$STAGING_DIR"

echo "==> Done:"
echo "    App: $(pwd)/$BUNDLE"
echo "    DMG: $(pwd)/$DMG_FILE ($(du -h "$DMG_FILE" | cut -f1))"
