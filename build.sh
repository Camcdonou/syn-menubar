#!/usr/bin/env bash
# Builds Syn Usage.app into build/
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Syn Usage.app"
mkdir -p "$APP/Contents/MacOS"

cp Resources/Info.plist "$APP/Contents/Info.plist"

swiftc -O -swift-version 5 \
    Sources/main.swift \
    -o "$APP/Contents/MacOS/syn-menubar"

codesign --force --sign - "$APP"

echo "Built $APP"
