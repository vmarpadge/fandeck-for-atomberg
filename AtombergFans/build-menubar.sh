#!/bin/zsh
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 Vineethkumar Marpadge
# Builds "FanDeck for Atomberg.app" (menu bar only) with Command Line Tools - no Xcode or Apple ID needed.
# Optional: BUNDLE_ID_PREFIX=io.github.<you> ./build-menubar.sh
set -euo pipefail
cd "${0:A:h}"

BUNDLE_ID_PREFIX="${BUNDLE_ID_PREFIX:-com.example}"
APP="build/FanDeck for Atomberg.app"
# Build into a temp bundle so a failed compile leaves the previous app intact.
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT
BUNDLE="$STAGE/FanDeck for Atomberg.app"
mkdir -p "$BUNDLE/Contents/MacOS"

swiftc -O -parse-as-library \
  -sdk "$(xcrun --show-sdk-path)" \
  -target "$(uname -m)-apple-macos14.0" \
  -swift-version 5 \
  Shared/Models.swift Shared/AtombergAPI.swift Shared/FanStore.swift \
  MenuBar/*.swift \
  -o "$BUNDLE/Contents/MacOS/AtombergFans"

cat > "$BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>${BUNDLE_ID_PREFIX}.AtombergFans.MenuBar</string>
  <key>CFBundleName</key><string>FanDeck for Atomberg</string>
  <key>CFBundleExecutable</key><string>AtombergFans</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST

codesign --force --sign - "$BUNDLE"
mkdir -p build
rm -rf "$APP"
mv "$BUNDLE" "$APP"
echo "Built $APP (${BUNDLE_ID_PREFIX}.AtombergFans.MenuBar)"
