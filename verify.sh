#!/bin/zsh
set -euo pipefail
TASK_ROOT="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$TASK_ROOT/build"
TASK_TEST_DIR="$(mktemp -d "$TASK_ROOT/build/check.XXXXXX")"
TASK_SOURCES=("$TASK_ROOT"/Sources/**/*.swift)
TASK_SOURCES=("${(@)TASK_SOURCES:#*/main.swift}")
TASK_APP="${1:-$TASK_ROOT/build/PaperMemory.app}"
if [[ ! -x "$TASK_APP/Contents/MacOS/PaperMemory" ]]; then
  print -u2 "Build the app first with ./build.sh, or pass an existing app path."
  exit 1
fi
print "Isolated test data and generated previews: $TASK_TEST_DIR"
python3 - "$TASK_TEST_DIR/fixture.png" <<'PYIMAGE'
import struct, zlib, sys
from pathlib import Path
def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data))
Path(sys.argv[1]).write_bytes(b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!IIBBBBB', 32, 32, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\x00' + b'\xff\xe8\x99' * 32) * 32)) + chunk(b'IEND', b''))
PYIMAGE
PAPER_MEMORY_TEST_BINARY="$TASK_APP/Contents/MacOS/PaperMemory" python3 "$TASK_ROOT/Tests/test_integration.py"
for TASK_TEST in test-motion test-rich-text test-window-state test-inertia test-paper-age; do
  xcrun swiftc -swift-version 5 -framework AppKit -framework QuartzCore -framework UniformTypeIdentifiers \
    "${TASK_SOURCES[@]}" "$TASK_ROOT"/Tests/Support/*.swift \
    "$TASK_ROOT/Tests/$TASK_TEST.swift" -o "$TASK_TEST_DIR/$TASK_TEST"
  case "$TASK_TEST" in
    test-motion) PAPER_MEMORY_HOME="$TASK_TEST_DIR/motion" "$TASK_TEST_DIR/$TASK_TEST" ;;
    test-rich-text) PAPER_MEMORY_HOME="$TASK_TEST_DIR/rich" "$TASK_TEST_DIR/$TASK_TEST" "$TASK_ROOT/Resources" "$TASK_TEST_DIR/fixture.png" ;;
    test-window-state) "$TASK_TEST_DIR/$TASK_TEST" "$TASK_TEST_DIR/windows" "$TASK_TEST_DIR/fixture.png" ;;
    test-inertia) "$TASK_TEST_DIR/$TASK_TEST" "$TASK_TEST_DIR/inertia" ;;
    test-paper-age) "$TASK_TEST_DIR/$TASK_TEST" "$TASK_ROOT/Resources" "$TASK_TEST_DIR/paper-age" ;;
  esac
done
codesign --verify --deep --strict "$TASK_APP"
print "Verified: $TASK_APP"
