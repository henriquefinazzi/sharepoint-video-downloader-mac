#!/bin/zsh
# Builds a universal (Apple silicon + Intel), ad-hoc signed app and packs it in a DMG.
# No Apple certificate is needed. Users must allow it in Gatekeeper and enable
# "Allow unsigned extensions" in Safari (see LEIA-ME / README inside the DMG).
#
# Usage: ./scripts/make-dmg.sh [output-dir]   (default: ./dist)
set -euo pipefail

PROJECT_DIR="${0:A:h:h}"
OUT_DIR="${1:-$PROJECT_DIR/dist}"
APP_NAME="SharePoint Video Downloader"
VERSION="$(awk -F'"' '/MARKETING_VERSION/ {print $2; exit}' "$PROJECT_DIR/project.yml")"
BUILD_DIR="$(mktemp -d -t spvd-dmg)"   # outside OneDrive: sync attributes break code signing
STAGE="$BUILD_DIR/stage"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

cleanup() {
  local built="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
  # Keep Safari from registering the temporary build copy.
  [[ -d "$built" ]] && "$LSREGISTER" -u "$built" 2>/dev/null || true
  [[ -d "$STAGE/$APP_NAME.app" ]] && "$LSREGISTER" -u "$STAGE/$APP_NAME.app" 2>/dev/null || true
  rm -rf "$BUILD_DIR"
}
trap cleanup EXIT

cd "$PROJECT_DIR"
swift scripts/make-icons.swift . >/dev/null
xcodegen generate --quiet

xcodebuild -project SPVideoDownloader.xcodeproj -scheme SPVideoDownloader -configuration Release \
  -derivedDataPath "$BUILD_DIR" -quiet \
  ARCHS="arm64 x86_64" ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="-" DEVELOPMENT_TEAM="" PROVISIONING_PROFILE_SPECIFIER="" \
  SPVD_BUNDLE_PREFIX="${SPVD_RELEASE_BUNDLE_PREFIX:-com.henriquefinazzi}" \
  build

APP="$BUILD_DIR/Build/Products/Release/$APP_NAME.app"
codesign --verify --deep --strict "$APP"

mkdir -p "$STAGE" "$OUT_DIR"
ditto "$APP" "$STAGE/$APP_NAME.app"
ln -s /Applications "$STAGE/Applications"
cp "$PROJECT_DIR/packaging/LEIA-ME.txt" "$STAGE/LEIA-ME (Read Me).txt"

DMG="$OUT_DIR/SharePointVideoDownloader-$VERSION.dmg"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDZO -ov "$DMG" -quiet
echo "$DMG"
