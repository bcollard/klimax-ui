#!/usr/bin/env bash
# Local dev bundle: build KlimaxUI via swift-bundler, then ad-hoc sign.
# Produces .build/bundler/apps/KlimaxUI/KlimaxUI.app
#
# For a signed + notarized release build (Developer ID required), use
# scripts/release.sh instead.
set -euo pipefail

cd "$(dirname "$0")"

APP=".build/bundler/apps/KlimaxUI/KlimaxUI.app"

echo "→ swift-bundler bundle -c release"
swift-bundler bundle -c release

echo "→ Ad-hoc codesign"
codesign --force --deep --sign - "$APP"

echo
echo "✓ Built: $APP"
echo "  Open: open \"$APP\""
echo "  Install: cp -R \"$APP\" /Applications/"
