#!/usr/bin/env bash
# build-qemu-binary.sh — produce a static qemu-system-aarch64 for Android.
#
# Output:
#   flutter/android/app/src/main/assets/qemu/qemu-system-aarch64-arm64
#   flutter/android/app/src/main/assets/qemu/qemu-img-arm64
#
# Strategy: build qemu with --static --disable-gtk --disable-sdl inside an
# Android NDK sysroot. Bundle the TCG-only frontend (no KVM path — host is
# usually unrooted). Size target: <25MB stripped.
#
# Dependencies (host):
#   - Android NDK r26+ (env ANDROID_NDK_HOME)
#   - qemu source (vendored under build/qemu-src or fetched fresh)
#   - meson, ninja, pkg-config, python3
#   - curl, tar

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ASSETS=$ROOT/flutter/android/app/src/main/assets/qemu
WORK=${WORK:-$ROOT/build/qemu-binary}
QEMU_VERSION=${QEMU_VERSION:-9.1.0}
ANDROID_API=${ANDROID_API:-28}
TARGET=aarch64-linux-android

mkdir -p "$ASSETS" "$WORK"
cd "$WORK"

log() { printf '[build-qemu-binary] %s\n' "$*" >&2; }

need() { command -v "$1" >/dev/null 2>&1 || { log "missing: $1"; exit 1; }; }
need meson
need ninja
need python3
need curl
need tar

: "${ANDROID_NDK_HOME:?set ANDROID_NDK_HOME to your Android NDK root}"

TOOLCHAIN=$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64
if [ ! -d "$TOOLCHAIN" ]; then
  log "NDK toolchain not found at $TOOLCHAIN"; exit 1
fi

export CC=$TOOLCHAIN/bin/${TARGET}${ANDROID_API}-clang
export CXX=$TOOLCHAIN/bin/${TARGET}${ANDROID_API}-clang++
export AR=$TOOLCHAIN/bin/llvm-ar
export RANLIB=$TOOLCHAIN/bin/llvm-ranlib
export STRIP=$TOOLCHAIN/bin/llvm-strip
export PKG_CONFIG_LIBDIR=""

if [ ! -d "qemu-${QEMU_VERSION}" ]; then
  log "fetching qemu ${QEMU_VERSION}"
  curl -fsSL "https://download.qemu.org/qemu-${QEMU_VERSION}.tar.xz" | tar -xJf -
fi

cd "qemu-${QEMU_VERSION}"

# Generate a cross-file for meson.
cat >android-cross.txt <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
pkg-config = 'false'

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

log "configuring"
./configure \
  --cross-prefix="${TARGET}${ANDROID_API}-" \
  --cc="$CC" \
  --cxx="$CXX" \
  --ar="$AR" \
  --ranlib="$RANLIB" \
  --strip="$STRIP" \
  --target-list=aarch64-softmmu \
  --static \
  --disable-gtk \
  --disable-sdl \
  --disable-vnc \
  --disable-cocoa \
  --disable-opengl \
  --disable-virglrenderer \
  --disable-kvm \
  --disable-docs \
  --disable-tools \
  --enable-tcg \
  --enable-slirp=internal \
  --without-default-features \
  --enable-system

log "building"
make -j"$(nproc)"

$STRIP build/qemu-system-aarch64 -o qemu-system-aarch64-arm64
$STRIP build/qemu-img -o qemu-img-arm64 || log "qemu-img not built (tools disabled); skipping"

install -m 0755 qemu-system-aarch64-arm64 "$ASSETS/qemu-system-aarch64-arm64"
if [ -f qemu-img-arm64 ]; then
  install -m 0755 qemu-img-arm64 "$ASSETS/qemu-img-arm64"
fi

log "done: $ASSETS/qemu-system-aarch64-arm64 ($(du -h "$ASSETS/qemu-system-aarch64-arm64" | cut -f1))"
log "NOTE: binary is gitignored (>50MB). Attach to GitHub release; APK pulls it."
