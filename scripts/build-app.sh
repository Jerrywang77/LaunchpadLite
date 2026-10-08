#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/.build/LaunchpadLite.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

swift build -c release --product LaunchpadLite
BIN_DIR="$(swift build -c release --show-bin-path)"

mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
install -m 755 "$BIN_DIR/LaunchpadLite" "$MACOS_DIR/LaunchpadLite"
install -m 644 "$ROOT_DIR/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
install -m 644 "$ROOT_DIR/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"

codesign --force --deep --sign - "$APP_DIR"

printf 'Built: %s\n' "$APP_DIR"
