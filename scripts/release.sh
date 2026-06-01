#!/usr/bin/env bash
# Build, sign, notarize, staple, and package KlimaxUI for distribution.
# Produces KlimaxUI.zip and KlimaxUI.dmg next to the bundled .app.
set -euo pipefail

IDENTITY="${KLIMAX_SIGN_IDENTITY:-Developer ID Application: Baptiste Collard (PZARL6555S)}"
NOTARY_PROFILE="${KLIMAX_NOTARY_PROFILE:-klimax-notary}"

cd "$(dirname "$0")/.."
OUT_DIR=".build/bundler/apps/KlimaxUI"
APP="$OUT_DIR/KlimaxUI.app"
ZIP="$OUT_DIR/KlimaxUI.zip"
DMG="$OUT_DIR/KlimaxUI.dmg"

step() { printf '\n\033[1;34m▸ %s\033[0m\n' "$*"; }

step "Bundle (release) with swift-bundler"
swift-bundler bundle -c release --codesign --identity "$IDENTITY"

step "Re-sign with hardened runtime + secure timestamp"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
codesign --verify --deep --strict --verbose=2 "$APP"

step "Package zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Notarize app (zip)"
xcrun notarytool submit "$ZIP" --keychain-profile "$NOTARY_PROFILE" --wait

step "Staple ticket to .app"
xcrun stapler staple "$APP"

step "Refresh zip with stapled .app"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"

step "Build DMG"
rm -f "$DMG"
create-dmg \
  --volname "Klimax" \
  --window-size 540 360 \
  --icon-size 96 \
  --icon "KlimaxUI.app" 140 180 \
  --app-drop-link 400 180 \
  --hide-extension "KlimaxUI.app" \
  --no-internet-enable \
  "$DMG" \
  "$APP"

step "Sign DMG"
codesign --force --sign "$IDENTITY" --timestamp "$DMG"

step "Notarize DMG"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait

step "Staple ticket to DMG"
xcrun stapler staple "$DMG"

step "Gatekeeper verification"
spctl -a -vv "$APP"
spctl -a -t open --context context:primary-signature -vv "$DMG"

step "Done"
ls -lh "$ZIP" "$DMG"
shasum -a 256 "$ZIP" "$DMG"
