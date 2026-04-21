#!/usr/bin/env bash
#
# Build the bionic-linked prefix tarball consumed by the termux-prefix
# sandbox backend (backend/sandbox/termux/backend.go).
#
# Input:  Termux bootstrap archive (APK-adjacent .zip published by the
#         termux-packages project) and a list of extra packages to install
#         through pkg/apt inside a proot+qemu-user staging rootfs.
# Output: flutter/android/app/src/main/assets/termux-prefix/
#           termux-prefix-arm64.tar.gz
#           termux-prefix-arm64.sha256
#           termux-prefix-arm64.version
#
# The tarball layout matches what prefix.go expects on the Android side:
# top-level bin/, lib/, usr/, etc/, var/ with busybox + symlinks and the
# bundled toolchain. The .version file records the bootstrap commit plus the
# pkg set so the Backend can refuse stale extractions.
#
# Prerequisites: bash, curl (or wget), unzip, tar, gzip, sha256sum,
#                proot + qemu-user-static (arm64) for package installation.
#                Debian/Ubuntu: apt-get install proot qemu-user-static unzip
#
# Usage:
#   ./scripts/build-termux-prefix.sh [--bootstrap-url URL] [--pkgs "git nodejs python3 curl"]
#
# The script is idempotent: re-running with the same inputs and cache dir
# produces a byte-identical tarball (modulo tar mtime, which we normalize).

set -euo pipefail

# --- config ----------------------------------------------------------------

# Termux bootstrap: the zip produced by termux-packages CI. Pinned by tag so
# the build is reproducible. Bump this when picking up a newer toolset.
BOOTSTRAP_TAG="${BOOTSTRAP_TAG:-bootstrap-2024.08.15-r1+apt-android-7}"
BOOTSTRAP_ARCH="${BOOTSTRAP_ARCH:-aarch64}"
BOOTSTRAP_URL="${BOOTSTRAP_URL:-https://github.com/termux/termux-packages/releases/download/${BOOTSTRAP_TAG}/bootstrap-${BOOTSTRAP_ARCH}.zip}"

# Packages installed on top of the bootstrap. Keep this list short — each
# addition grows the APK asset.
PKGS="${PKGS:-busybox bash coreutils findutils grep sed gawk tar gzip curl openssl ca-certificates git nodejs python}"

# Output paths.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$PROJECT_DIR/flutter/android/app/src/main/assets/termux-prefix"
CACHE_DIR="${MOCODE_BUILD_CACHE:-$PROJECT_DIR/.build-cache/termux}"

TARBALL="$OUT_DIR/termux-prefix-arm64.tar.gz"
CHECKSUM="$OUT_DIR/termux-prefix-arm64.sha256"
VERSION_FILE="$OUT_DIR/termux-prefix-arm64.version"

# --- cli -------------------------------------------------------------------

while [ "$#" -gt 0 ]; do
    case "$1" in
        --bootstrap-url) BOOTSTRAP_URL="$2"; shift 2 ;;
        --pkgs)          PKGS="$2"; shift 2 ;;
        --arch)          BOOTSTRAP_ARCH="$2"; shift 2 ;;
        --out-dir)       OUT_DIR="$2"; shift 2 ;;
        -h|--help)
            sed -n '2,28p' "$0"
            exit 0
            ;;
        *) echo "unknown flag: $1" >&2; exit 2 ;;
    esac
done

# --- prerequisites ---------------------------------------------------------

require() {
    command -v "$1" >/dev/null 2>&1 || {
        echo "ERROR: $1 not found on PATH — $2" >&2
        exit 1
    }
}

require curl   "install curl"
require unzip  "install unzip"
require tar    "install tar"
require gzip   "install gzip"
require sha256sum "install coreutils"
require proot  "install proot (for arm64 staging inside qemu-user)"

# proot needs qemu-user-static for non-native architectures. Check only when
# the host differs from the target.
HOST_ARCH="$(uname -m)"
if [ "$HOST_ARCH" != "$BOOTSTRAP_ARCH" ] && [ "$HOST_ARCH" != "arm64" ]; then
    require "qemu-aarch64-static" "install qemu-user-static for arm64 emulation"
fi

# --- fetch bootstrap -------------------------------------------------------

mkdir -p "$CACHE_DIR" "$OUT_DIR"
BOOTSTRAP_ZIP="$CACHE_DIR/bootstrap-${BOOTSTRAP_ARCH}.zip"

if [ ! -f "$BOOTSTRAP_ZIP" ]; then
    echo "==> downloading $BOOTSTRAP_URL"
    curl -fSL "$BOOTSTRAP_URL" -o "$BOOTSTRAP_ZIP.part"
    mv "$BOOTSTRAP_ZIP.part" "$BOOTSTRAP_ZIP"
fi

BOOTSTRAP_SHA="$(sha256sum "$BOOTSTRAP_ZIP" | cut -d' ' -f1)"
echo "    bootstrap sha256: $BOOTSTRAP_SHA"

# --- stage the prefix ------------------------------------------------------

STAGE="$CACHE_DIR/stage"
rm -rf "$STAGE"
mkdir -p "$STAGE"

echo "==> extracting bootstrap → $STAGE"
unzip -q "$BOOTSTRAP_ZIP" -d "$STAGE"

# Termux bootstrap ships a SYMLINKS.txt listing symlinks the installer must
# materialize (unzip cannot represent them). Format: "<target>←<linkname>".
if [ -f "$STAGE/SYMLINKS.txt" ]; then
    echo "==> materializing SYMLINKS.txt"
    (
        cd "$STAGE"
        while IFS='←' read -r target link; do
            [ -z "$target" ] && continue
            mkdir -p "$(dirname "$link")"
            ln -sf "$target" "$link"
        done < SYMLINKS.txt
    )
    rm "$STAGE/SYMLINKS.txt"
fi

# --- install extra packages via proot+qemu --------------------------------

# The Termux prefix is hardcoded to /data/data/com.termux/files/usr at build
# time. Proot lets us present that path inside the staging rootfs so the
# bundled pkg/apt scripts resolve their absolute references. On mo-code's
# Android install the prefix lives at a different path — the Go Backend
# tolerates this because it runs binaries via `$prefix/bin/sh -c` with
# PATH/LD_LIBRARY_PATH overridden, not through the bootstrap installer.

if [ -n "$PKGS" ]; then
    echo "==> installing extra packages: $PKGS"
    TERMUX_ROOT="/data/data/com.termux/files"
    proot \
        -0 \
        -r "$STAGE" \
        -b /dev -b /proc -b /sys \
        -b /etc/resolv.conf:/etc/resolv.conf \
        -b "$STAGE:$TERMUX_ROOT" \
        -w "$TERMUX_ROOT/home" \
        /system/bin/env \
            PATH="$TERMUX_ROOT/usr/bin:$TERMUX_ROOT/usr/bin/applets" \
            HOME="$TERMUX_ROOT/home" \
            PREFIX="$TERMUX_ROOT/usr" \
            TMPDIR="$TERMUX_ROOT/usr/tmp" \
            LANG="C.UTF-8" \
        sh -c "pkg update -y && pkg install -y $PKGS"
fi

# --- repack to the mo-code layout ------------------------------------------

# The Go Backend expects top-level bin/, lib/, etc/ (no usr/ nesting at the
# root) because the stock Termux prefix lives under usr/. We move the usr
# contents up so PATH="$prefix/bin" resolves without an extra level, while
# keeping a usr/ symlink so absolute references from bundled scripts still
# work.

REPACK="$CACHE_DIR/repack"
rm -rf "$REPACK"
mkdir -p "$REPACK"

echo "==> repacking prefix"
# Bootstrap ships everything under ./usr — lift it to the top level.
if [ -d "$STAGE/usr" ]; then
    cp -a "$STAGE/usr/." "$REPACK/"
else
    cp -a "$STAGE/." "$REPACK/"
fi

# Keep a back-compat usr/ pointer so scripts hardcoded to $PREFIX/usr/bin
# still resolve. Use a relative symlink so it survives extraction anywhere.
(cd "$REPACK" && ln -sfn . usr)

mkdir -p "$REPACK/tmp" "$REPACK/home" "$REPACK/var"
chmod 1777 "$REPACK/tmp" || true

# --- produce the tarball ---------------------------------------------------

echo "==> taring $REPACK → $TARBALL"
# --sort=name + --mtime + --owner/--group normalize the archive so repeated
# builds produce the same bytes, which makes APK signing caches happy.
tar \
    --sort=name \
    --mtime='2000-01-01 00:00Z' \
    --owner=0 --group=0 --numeric-owner \
    -C "$REPACK" \
    -czf "$TARBALL" \
    .

sha256sum "$TARBALL" | cut -d' ' -f1 > "$CHECKSUM"
TARBALL_SHA="$(cat "$CHECKSUM")"

cat > "$VERSION_FILE" <<EOF
bootstrap_tag=$BOOTSTRAP_TAG
bootstrap_sha256=$BOOTSTRAP_SHA
arch=$BOOTSTRAP_ARCH
pkgs=$PKGS
tarball_sha256=$TARBALL_SHA
EOF

SIZE_MB="$(du -m "$TARBALL" | cut -f1)"
echo
echo "==> done"
echo "    tarball:  $TARBALL (${SIZE_MB} MB)"
echo "    sha256:   $TARBALL_SHA"
echo "    version:  $VERSION_FILE"
echo
if [ "$SIZE_MB" -gt 50 ]; then
    echo "WARNING: tarball is ${SIZE_MB} MB — check in with the lead before committing."
fi
