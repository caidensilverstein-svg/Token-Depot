#!/bin/bash
# TokenDepot build + install script
# Usage: ./build.sh
# Builds Release, installs to /Applications, relaunches

set -e

PROJ_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="TokenDepot"
TEAM="F799QWRKD6"

echo "→ Building $APP_NAME..."
cd "$PROJ_DIR"
xcodebuild \
  -project "$APP_NAME.xcodeproj" \
  -scheme "$APP_NAME" \
  -configuration Release \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM="$TEAM" \
  build 2>&1 | grep -E "error:|warning:|BUILD SUCCEEDED|BUILD FAILED"

APP_PATH="$PROJ_DIR/build/Build/Products/Release/$APP_NAME.app"

echo "→ Stopping existing instance..."
pkill -x "$APP_NAME" 2>/dev/null || true
sleep 1

echo "→ Installing to /Applications..."
cp -R "$APP_PATH" "/Applications/$APP_NAME.app"
xattr -cr "/Applications/$APP_NAME.app"

echo "→ Launching..."
open "/Applications/$APP_NAME.app"

echo "✓ Done — $APP_NAME running independently"
