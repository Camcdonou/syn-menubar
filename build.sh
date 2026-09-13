#!/usr/bin/env bash
# Builds Syn Usage.app into build/
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Syn Usage.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp Resources/Info.plist "$APP/Contents/Info.plist"

# App icon: generate full .icns from the 1024 master
ICONSET="build/AppIcon.iconset"
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for spec in "16 icon_16x16" "32 icon_16x16@2x" "32 icon_32x32" "64 icon_32x32@2x" \
            "128 icon_128x128" "256 icon_128x128@2x" "256 icon_256x256" \
            "512 icon_256x256@2x" "512 icon_512x512" "1024 icon_512x512@2x"; do
    set -- $spec
    sips -z "$1" "$1" Assets/icon_1024.png --out "$ICONSET/$2.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

swiftc -O -swift-version 5 \
    Sources/main.swift \
    -o "$APP/Contents/MacOS/syn-menubar"

codesign --force --sign - "$APP"

echo "Built $APP"
