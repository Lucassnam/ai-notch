#!/bin/zsh
set -euo pipefail

PROJECT_DIR=${0:A:h:h}
APP_DIR="$PROJECT_DIR/dist/AI Notch.app"

cd "$PROJECT_DIR"
swift build -c release

mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$PROJECT_DIR/.build/release/AINotch" "$APP_DIR/Contents/MacOS/AINotch"
cp "$PROJECT_DIR/Supporting/Info.plist" "$APP_DIR/Contents/Info.plist"
chmod +x "$APP_DIR/Contents/MacOS/AINotch"

codesign --force --deep --sign - "$APP_DIR" >/dev/null
echo "$APP_DIR"
