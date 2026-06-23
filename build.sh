#!/bin/zsh
# Build the panelid CLI and PanelID.app for Apple Silicon, ad-hoc sign them,
# and package release artifacts into dist/. Requires only the Xcode Command
# Line Tools (Swift 6+) — no full Xcode.
set -euo pipefail

VERSION="0.1.0"          # keep in sync with PanelKit.panelIDVersion
ARCH="arm64"
ROOT="${0:A:h}"
cd "$ROOT"

DIST="$ROOT/dist"
rm -rf "$DIST"; mkdir -p "$DIST"

echo "==> swift build (release, $ARCH)"
swift build -c release --arch "$ARCH"
BIN="$(swift build -c release --arch "$ARCH" --show-bin-path)"

echo "==> packaging panelid CLI"
cp "$BIN/panelid" "$DIST/panelid"
codesign --force --sign - "$DIST/panelid"
tar -czf "$DIST/panelid-v${VERSION}-${ARCH}.tar.gz" -C "$DIST" panelid

echo "==> assembling PanelID.app"
APP="$DIST/PanelID.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN/PanelIDApp" "$APP/Contents/MacOS/PanelIDApp"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>Panel ID</string>
  <key>CFBundleDisplayName</key><string>Panel ID</string>
  <key>CFBundleIdentifier</key><string>com.alexeyinwerp.apple-panel-id</string>
  <key>CFBundleExecutable</key><string>PanelIDApp</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>${VERSION}</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP"
( cd "$DIST" && ditto -c -k --keepParent "PanelID.app" "PanelID-v${VERSION}-${ARCH}.zip" )

echo "==> artifacts in $DIST:"
ls -1 "$DIST"
