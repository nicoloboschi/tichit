#!/bin/bash
# Builds Tichit.app into build/. No Xcode required — the bundle is assembled by hand.
set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="release"
INSTALL=""
for arg in "$@"; do
    case "$arg" in
        --install) INSTALL=1 ;;
        debug|release) CONFIG="$arg" ;;
    esac
done
APP="build/Tichit.app"

swift build -c "$CONFIG"
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/Tichit"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Tichit"

# Icon: rendered from Logo.swift, so the app and the .icns can never drift apart.
ICONSET="build/Tichit.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
"$BIN_DIR/IconGen" "$ICONSET" >/dev/null
for size in 16 32 128 256 512; do
    mv "$ICONSET/icon_$size.png" "$ICONSET/icon_${size}x${size}.png"
done
mv "$ICONSET/icon_32.png" "$ICONSET/icon_16x16@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_128x128.png" "$ICONSET/icon_64x64@2x.png" 2>/dev/null || true
cp "$ICONSET/icon_256x256.png" "$ICONSET/icon_128x128@2x.png"
cp "$ICONSET/icon_512x512.png" "$ICONSET/icon_256x256@2x.png"
mv "$ICONSET/icon_1024.png" "$ICONSET/icon_512x512@2x.png"
rm -f "$ICONSET"/icon_64.png
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/Tichit.icns"
rm -rf "$ICONSET"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Tichit</string>
    <key>CFBundleDisplayName</key><string>Tichit</string>
    <key>CFBundleIdentifier</key><string>dev.tichit.app</string>
    <key>CFBundleExecutable</key><string>Tichit</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>0.1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSUIElement</key><true/>
    <key>CFBundleIconFile</key><string>Tichit</string>
    <key>NSHumanReadableCopyright</key><string></string>
</dict>
</plist>
PLIST

# Ad-hoc signature: keeps the Keychain item bound to a stable identity.
codesign --force --sign - "$APP" >/dev/null 2>&1 || echo "warning: ad-hoc codesign failed"

echo "Built $APP"

if [ -n "$INSTALL" ]; then
    # Quit the running copy first: replacing a bundle underneath a live process
    # leaves it running from a deleted path.
    pkill -f "Tichit.app/Contents/MacOS/Tichit" 2>/dev/null || true
    rm -rf /Applications/Tichit.app
    cp -R "$APP" /Applications/Tichit.app
    echo "Installed /Applications/Tichit.app"
fi
