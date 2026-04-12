#!/bin/bash
# Cross-compile Go daemon for Android architectures and place into Flutter assets.
#
# Usage: ./scripts/build-android-daemon.sh [--arm64-only]
#
# Output: flutter/android/app/src/main/assets/bin/<ABI>/mocode
#         flutter/android/app/src/main/assets/bin/VERSION

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"
ASSETS_DIR="$PROJECT_DIR/flutter/android/app/src/main/assets/bin"

if ! command -v go &> /dev/null; then
    echo "Error: Go not found. Please install Go 1.24+."
    exit 1
fi

# Version tag — bump when the daemon binary changes.
VERSION=$(cd "$BACKEND_DIR" && git describe --tags --always --dirty 2>/dev/null || echo "dev-$(date +%s)")

echo "=== Building Go daemon for Android ==="
echo "Source: $BACKEND_DIR"
echo "Version: $VERSION"
echo ""

cd "$BACKEND_DIR"

# ABI → GOARCH mapping
declare -A TARGETS
if [ "$1" = "--arm64-only" ]; then
    TARGETS=( ["arm64-v8a"]="arm64" )
else
    TARGETS=(
        ["arm64-v8a"]="arm64"
        ["armeabi-v7a"]="arm"
        ["x86_64"]="amd64"
        ["x86"]="386"
    )
fi

for ABI in "${!TARGETS[@]}"; do
    GOARCH="${TARGETS[$ABI]}"
    OUT_DIR="$ASSETS_DIR/$ABI"
    mkdir -p "$OUT_DIR"

    echo "Building $ABI (GOARCH=$GOARCH)..."
    GOOS=linux GOARCH="$GOARCH" CGO_ENABLED=0 \
        go build -trimpath -ldflags="-s -w" -o "$OUT_DIR/mocode" ./cmd/mocode

    SIZE=$(du -h "$OUT_DIR/mocode" | cut -f1)
    echo "  ✓ $OUT_DIR/mocode ($SIZE)"
done

# Write version marker.
echo "$VERSION" > "$ASSETS_DIR/VERSION"

echo ""
echo "Done. Assets written to $ASSETS_DIR"
ls -la "$ASSETS_DIR"/*/mocode 2>/dev/null
