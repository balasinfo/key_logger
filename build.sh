#!/usr/bin/env bash
# Fallback build that uses swiftc directly. Use this when `swift build` fails because the
# Command Line Tools SwiftPM/PackageDescription is mismatched with the Swift toolchain
# (manifest link error: "PackageDescription.Package.__allocating_init ... symbol(s) not found").
# Produces ./.build-direct/activitytracker.
set -euo pipefail
cd "$(dirname "$0")"
OUT=".build-direct"
mkdir -p "$OUT"

# Deployment floor. Default macOS 12 (Monterey) so a binary built on a newer Mac still runs
# on older Intel laptops (2015/2019 top out around Monterey). Override with MACOS_MIN=13.0 etc.
TARGET="x86_64-apple-macosx${MACOS_MIN:-12.0}"
echo "Targeting $TARGET"

echo "Building ActivityCore module..."
swiftc -swift-version 5 -target "$TARGET" -emit-module -emit-library \
  -module-name ActivityCore \
  Sources/ActivityCore/*.swift \
  -o "$OUT/libActivityCore.dylib" \
  -emit-module-path "$OUT/ActivityCore.swiftmodule" \
  -Xlinker -install_name -Xlinker "@rpath/libActivityCore.dylib" \
  -framework AppKit -framework ApplicationServices -lsqlite3

echo "Building activitytracker executable..."
swiftc -swift-version 5 -target "$TARGET" \
  -I "$OUT" -L "$OUT" -lActivityCore -Xlinker -rpath -Xlinker "@executable_path" \
  Sources/activitytracker/*.swift \
  -o "$OUT/activitytracker" \
  -framework AppKit -lsqlite3

echo "Done: $OUT/activitytracker"
