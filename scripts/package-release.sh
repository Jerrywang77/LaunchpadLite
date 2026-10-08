#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' Resources/Info.plist)"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_DIR="$ROOT_DIR/.build/LaunchpadLite.app"
ZIP_PATH="$RELEASE_DIR/LaunchpadLite-$VERSION.zip"

mkdir -p "$RELEASE_DIR"

./scripts/build-app.sh

# --norsrc / --noextattr 很重要：App 里带 com.apple.provenance 之类的扩展属性，
# 默认打包会变成 ._* 文件塞进 bundle，解压后代码签名校验会失败（用户会看到
# “应用已损坏”，而不是普通的“未签名”提示）。
ditto -c -k --norsrc --noextattr --keepParent "$APP_DIR" "$ZIP_PATH"

printf '\n分发包已生成：%s\n' "$ZIP_PATH"
printf '把它上传到 GitHub 的 Release，用户解压后把 LaunchpadLite.app 拖进「应用程序」即可。\n'
