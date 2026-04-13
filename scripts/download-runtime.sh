#!/bin/bash
# Download proot static binary and Alpine Linux minirootfs for bundling in APK.
#
# Run this once before building the release APK. The downloaded files go into
# flutter/android/app/src/main/assets/runtime/ and are bundled into the APK.
#
# Prerequisites: curl, sha256sum
#
# Usage:
#   ./scripts/download-runtime.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
ASSETS_DIR="$PROJECT_DIR/flutter/android/app/src/main/assets/runtime"

# --- Versions ---
ALPINE_VERSION="3.21.3"
ALPINE_ARCH="aarch64"
PROOT_VERSION="5.3.0"

# --- URLs ---
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/$ALPINE_ARCH/alpine-minirootfs-$ALPINE_VERSION-$ALPINE_ARCH.tar.gz"
PROOT_URL="https://github.com/proot-me/proot/releases/download/v$PROOT_VERSION/proot-v$PROOT_VERSION-aarch64-static"

# --- Checksums (update when bumping versions) ---
# Leave empty to skip verification (first download to get the checksum)
ALPINE_SHA256="ead8a4b37867bd19e7417dd078748e2312c0aea364403d96758d63ea8ff261ea"
PROOT_SHA256="fa10b1a7818c2f5b1dcb5834450570c368c9ecf66d31521509621b95c4538a45"

echo "=== Mo-Code Runtime Download ==="
echo ""
echo "Alpine: $ALPINE_VERSION ($ALPINE_ARCH)"
echo "proot:  $PROOT_VERSION (arm64 static)"
echo "Target: $ASSETS_DIR"
echo ""

mkdir -p "$ASSETS_DIR"

# --- Download Alpine minirootfs ---
ALPINE_FILE="$ASSETS_DIR/alpine-minirootfs.tar.gz"
if [ -f "$ALPINE_FILE" ]; then
    echo "Alpine rootfs already downloaded, skipping"
else
    echo "Downloading Alpine minirootfs..."
    curl -fSL "$ALPINE_URL" -o "$ALPINE_FILE"
    echo "Downloaded: $(du -h "$ALPINE_FILE" | cut -f1)"
fi

if [ -n "$ALPINE_SHA256" ]; then
    echo -n "Verifying Alpine checksum... "
    echo "$ALPINE_SHA256  $ALPINE_FILE" | sha256sum -c --quiet
    echo "OK"
else
    echo "Alpine SHA256: $(sha256sum "$ALPINE_FILE" | cut -d' ' -f1)"
    echo "(no expected checksum set — update ALPINE_SHA256 in this script)"
fi

# --- Download proot static binary ---
PROOT_FILE="$ASSETS_DIR/proot-arm64"
if [ -f "$PROOT_FILE" ]; then
    echo "proot binary already downloaded, skipping"
else
    echo "Downloading proot static binary..."
    curl -fSL "$PROOT_URL" -o "$PROOT_FILE"
    chmod +x "$PROOT_FILE"
    echo "Downloaded: $(du -h "$PROOT_FILE" | cut -f1)"
fi

if [ -n "$PROOT_SHA256" ]; then
    echo -n "Verifying proot checksum... "
    echo "$PROOT_SHA256  $PROOT_FILE" | sha256sum -c --quiet
    echo "OK"
else
    echo "proot SHA256: $(sha256sum "$PROOT_FILE" | cut -d' ' -f1)"
    echo "(no expected checksum set — update PROOT_SHA256 in this script)"
fi

# --- Write version file (used by RuntimeBootstrap.kt to skip re-extraction) ---
VERSION_FILE="$ASSETS_DIR/RUNTIME_VERSION"
RUNTIME_VERSION="alpine-$ALPINE_VERSION+proot-$PROOT_VERSION"
echo "$RUNTIME_VERSION" > "$VERSION_FILE"
echo ""
echo "Version: $RUNTIME_VERSION"

# --- Write checksums file (used by RuntimeBootstrap.kt for integrity check) ---
CHECKSUMS_FILE="$ASSETS_DIR/CHECKSUMS"
{
    echo "alpine-minirootfs.tar.gz $(sha256sum "$ALPINE_FILE" | cut -d' ' -f1)"
    echo "proot-arm64 $(sha256sum "$PROOT_FILE" | cut -d' ' -f1)"
} > "$CHECKSUMS_FILE"

echo ""
echo "============================================"
echo "Runtime assets ready at:"
echo "  $ASSETS_DIR/"
ls -lh "$ASSETS_DIR/"
echo ""
echo "Total size: $(du -sh "$ASSETS_DIR" | cut -f1)"
echo "============================================"
