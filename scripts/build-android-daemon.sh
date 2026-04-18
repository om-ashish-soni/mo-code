#!/bin/bash
# Cross-compile Go daemon for Android architectures and place into jniLibs.
#
# Usage: ./scripts/build-android-daemon.sh [--arm64-only]
#
# Primary output: flutter/android/app/src/main/jniLibs/<ABI>/libmocode.so
#   DaemonService.kt execs this from applicationInfo.nativeLibraryDir —
#   apk_data_file SELinux context, mmap(PROT_EXEC) allowed on Android 15.
# Mirror: flutter/android/app/src/main/assets/bin/<ABI>/mocode
#   Kept for fallback loaders; DO NOT treat assets as authoritative.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
BACKEND_DIR="$PROJECT_DIR/backend"
ASSETS_DIR="$PROJECT_DIR/flutter/android/app/src/main/assets/bin"
JNILIBS_DIR="$PROJECT_DIR/flutter/android/app/src/main/jniLibs"

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
    JNI_OUT="$JNILIBS_DIR/$ABI"
    ASSET_OUT="$ASSETS_DIR/$ABI"
    mkdir -p "$JNI_OUT" "$ASSET_OUT"

    echo "Building $ABI (GOARCH=$GOARCH)..."
    # jniLibs is the primary output — DaemonService execs libmocode.so from here.
    GOOS=linux GOARCH="$GOARCH" CGO_ENABLED=0 \
        go build -trimpath -ldflags="-s -w" -o "$JNI_OUT/libmocode.so" ./cmd/mocode
    # Mirror to assets for legacy callers.
    cp "$JNI_OUT/libmocode.so" "$ASSET_OUT/mocode"

    SIZE=$(du -h "$JNI_OUT/libmocode.so" | cut -f1)
    echo "  ✓ $JNI_OUT/libmocode.so ($SIZE)"
done

# Write version marker.
echo "$VERSION" > "$ASSETS_DIR/VERSION"

echo ""
echo "Done. Primary output: $JNILIBS_DIR (jniLibs)."
ls -la "$JNILIBS_DIR"/*/libmocode.so 2>/dev/null
