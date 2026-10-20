#!/bin/bash
set -euo pipefail

TASK_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TASK_APP="${1:-$TASK_ROOT/build/PaperMemory.app}"
TASK_DIST="$TASK_ROOT/dist"
TASK_STAGE="$(mktemp -d "${TMPDIR:-/tmp}/paper-release.XXXXXX")"
trap 'rm -rf "$TASK_STAGE"' EXIT

codesign --verify --deep --strict "$TASK_APP"
test "$(lipo -archs "$TASK_APP/Contents/MacOS/PaperMemory")" = "arm64"
TASK_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_APP/Contents/Info.plist")"
test "$TASK_VERSION" = "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$TASK_ROOT/Info.plist")"

mkdir -p "$TASK_DIST" "$TASK_STAGE/volume"
ditto "$TASK_APP" "$TASK_STAGE/volume/PaperMemory.app"
ln -s /Applications "$TASK_STAGE/volume/Applications"
cat > "$TASK_STAGE/volume/安装说明.txt" <<'EOF'
贴贴 · StickyNote for AI

适用于 Apple 芯片（M 系列）Mac，macOS 14 或更新版本。

1. 将 PaperMemory.app 拖入 Applications（应用程序）。
2. 从“应用程序”打开贴贴。应用常驻菜单栏，没有 Dock 图标。
3. 从菜单栏或便签右键新建便签。

此版本采用 ad-hoc 签名，尚未经过 Apple 公证。
若首次打开被系统阻止，请在尝试打开后前往：
系统设置 → 隐私与安全性 → 仍要打开，再按系统提示确认。
不需要关闭系统安全检查。

更新前退出旧版贴贴，再替换应用；原有便签保存在用户资料目录，不在应用包内。

Codex、Claude、Cursor 接入教程：
https://github.com/novono/StickyNoteforAI/blob/main/docs/AI-CLIENTS.md
下载与源码：https://github.com/novono/StickyNoteforAI
EOF

ditto -c -k --sequesterRsrc --keepParent \
  "$TASK_STAGE/volume/PaperMemory.app" "$TASK_DIST/PaperMemory-macOS-arm64.zip"
hdiutil create -quiet -ov -format UDZO -fs HFS+ \
  -volname "贴贴 $TASK_VERSION" -srcfolder "$TASK_STAGE/volume" \
  "$TASK_DIST/PaperMemory-macOS-arm64.dmg"
hdiutil verify "$TASK_DIST/PaperMemory-macOS-arm64.dmg"

# Check the actual archive, including its signature after extraction.
ditto -x -k "$TASK_DIST/PaperMemory-macOS-arm64.zip" "$TASK_STAGE/unpacked"
codesign --verify --deep --strict "$TASK_STAGE/unpacked/PaperMemory.app"
PAPER_MEMORY_TEST_BINARY="$TASK_STAGE/unpacked/PaperMemory.app/Contents/MacOS/PaperMemory" \
  python3 "$TASK_ROOT/Tests/test_integration.py"
(
  cd "$TASK_DIST"
  shasum -a 256 PaperMemory-macOS-arm64.dmg PaperMemory-macOS-arm64.zip > SHA256SUMS
)
printf 'Packaged version %s in %s\n' "$TASK_VERSION" "$TASK_DIST"
