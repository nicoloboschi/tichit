#!/bin/bash
# Packages build/Tichit.app into build/Tichit.dmg with an Applications shortcut.
set -euo pipefail

cd "$(dirname "$0")/.."

APP="build/Tichit.app"
DMG="build/Tichit.dmg"
STAGE="build/dmg"

[ -d "$APP" ] || { echo "no $APP — run scripts/build-app.sh first" >&2; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
    -volname "Tichit" \
    -srcfolder "$STAGE" \
    -ov -format UDZO \
    "$DMG" >/dev/null

rm -rf "$STAGE"
echo "Built $DMG"
