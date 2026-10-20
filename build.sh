#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
TASK_APP="${1:-$TASK_ROOT/build/PaperMemory.app}"
TASK_SOURCES=("$TASK_ROOT"/Sources/**/*.swift)
mkdir -p "$TASK_APP/Contents/MacOS" "$TASK_APP/Contents/Resources"
xcrun swiftc -swift-version 5 -O -target arm64-apple-macosx14.0 \
  -framework AppKit -framework QuartzCore -framework UniformTypeIdentifiers \
  "${TASK_SOURCES[@]}" -o "$TASK_APP/Contents/MacOS/PaperMemory"
cp "$TASK_ROOT/Info.plist" "$TASK_APP/Contents/Info.plist"
if [[ -d "$TASK_ROOT/Resources" ]]; then cp -R "$TASK_ROOT/Resources/" "$TASK_APP/Contents/Resources/"; fi
codesign --force --deep --sign - "$TASK_APP"
print "Built: $TASK_APP"
