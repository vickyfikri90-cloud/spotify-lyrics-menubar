#!/usr/bin/env bash
set -euo pipefail

APP_NAME="LyricsMenuBar"
BUNDLE="$APP_NAME.app"
BUILD_DIR=".build/release"

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

echo "==> Done: $(pwd)/$BUNDLE"
echo
echo "Run it with: open $BUNDLE"
echo "Or move it to /Applications: mv $BUNDLE /Applications/"
