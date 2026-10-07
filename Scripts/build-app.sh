#!/bin/zsh
set -euo pipefail

ROOT_DIR="${0:A:h:h}"
cd "$ROOT_DIR"

swift build -c release
BIN_DIR="$(swift build -c release --show-bin-path)"
APP_DIR="$ROOT_DIR/ClipboardApp.app"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/ClipboardApp" "$APP_DIR/Contents/MacOS/ClipboardApp"
cp "$ROOT_DIR/Resources/Info.plist" "$APP_DIR/Contents/Info.plist"

codesign --force --deep --sign - "$APP_DIR"
printf '\n已生成：%s\n' "$APP_DIR"
printf '可在“系统设置 -> 隐私与安全性 -> 辅助功能”中添加这个应用。\n'
printf '启动命令：open "%s"\n' "$APP_DIR"
