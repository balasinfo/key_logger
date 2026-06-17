#!/usr/bin/env bash
# Fallback test runner for when `swift test` can't run under the mismatched Command Line Tools.
# Compiles Tests/run.swift against the ActivityCore module and runs the assertions.
set -euo pipefail
cd "$(dirname "$0")"
OUT=".build-direct"

# Ensure the module is built.
swiftc -swift-version 5 -emit-module -emit-library \
  -module-name ActivityCore \
  Sources/ActivityCore/*.swift \
  -o "$OUT/libActivityCore.dylib" \
  -emit-module-path "$OUT/ActivityCore.swiftmodule" \
  -Xlinker -install_name -Xlinker "@rpath/libActivityCore.dylib" \
  -framework AppKit -framework ApplicationServices -lsqlite3

swiftc -swift-version 5 \
  -I "$OUT" -L "$OUT" -lActivityCore -Xlinker -rpath -Xlinker "@executable_path" \
  Tests/run.swift \
  -o "$OUT/runtests" \
  -framework AppKit -lsqlite3

"$OUT/runtests"
