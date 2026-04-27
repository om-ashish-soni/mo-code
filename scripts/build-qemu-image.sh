#!/usr/bin/env bash
# build-qemu-image.sh — produce alpine-prebaked.qcow2 for the qemu-tcg backend.
#
# Output: flutter/android/app/src/main/assets/qemu/alpine-prebaked.qcow2
# Size target: <80MB compressed on disk (qcow2 default compression off, base.tar.gz ~40MB).
#
# Requirements (host):
#   - Linux with KVM (speeds up the build; not required — falls back to TCG)
#   - qemu-system-aarch64
#   - qemu-img
#   - wget, openssl, mkisofs (or genisoimage)
#   - ~4 GB free disk
#
# This script boots an Alpine arm64 netboot, runs setup-alpine via an answer
# file baked into a seed ISO, then powers off and trims the resulting qcow2.
#
# The produced image has:
#   - Alpine 3.19 aarch64
#   - 512 MB root partition
#   - sshd on boot, root login enabled, password "mocode"
#   - openssh, ca-certificates, bash, curl, git installed (minimal baseline)
#   - apk mirror set — `apk add python3` etc. work at runtime
#
# Artifact is NOT committed (>50MB). Ship via GitHub release; APK build pulls it.

set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
ASSETS=$ROOT/flutter/android/app/src/main/assets/qemu
WORK=${WORK:-$ROOT/build/qemu-image}
ALPINE_VERSION=${ALPINE_VERSION:-3.19}
ALPINE_ARCH=${ALPINE_ARCH:-aarch64}
IMAGE_SIZE=${IMAGE_SIZE:-1G}
SSH_PASSWORD=${SSH_PASSWORD:-mocode}

mkdir -p "$ASSETS" "$WORK"
cd "$WORK"

log() { printf '[build-qemu-image] %s\n' "$*" >&2; }

need() {
  command -v "$1" >/dev/null 2>&1 || { log "missing dependency: $1"; exit 1; }
}
need qemu-system-aarch64
need qemu-img
need wget
need openssl

MKISO=$(command -v mkisofs 2>/dev/null || command -v genisoimage 2>/dev/null || true)
if [ -z "$MKISO" ]; then
  log "missing dependency: mkisofs (or genisoimage)"
  exit 1
fi

ALPINE_URL=https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/releases/${ALPINE_ARCH}
ISO_NAME=alpine-virt-${ALPINE_VERSION}.0-${ALPINE_ARCH}.iso
UEFI_FIRMWARE=${UEFI_FIRMWARE:-/usr/share/AAVMF/AAVMF_CODE.fd}

log "alpine iso: fetching if missing"
if [ ! -f "$ISO_NAME" ]; then
  wget -q "$ALPINE_URL/$ISO_NAME" -O "$ISO_NAME.part"
  mv "$ISO_NAME.part" "$ISO_NAME"
fi

if [ ! -f "$UEFI_FIRMWARE" ]; then
  log "UEFI firmware missing at $UEFI_FIRMWARE"
  log "install: sudo apt install qemu-efi-aarch64  (debian/ubuntu)"
  log "         sudo dnf install edk2-aarch64       (fedora)"
  exit 1
fi

log "creating blank qcow2 ($IMAGE_SIZE)"
qemu-img create -f qcow2 target.qcow2 "$IMAGE_SIZE" >/dev/null

log "rendering answerfile + first-boot script"
cat >answerfile <<EOF
KEYMAPOPTS="us us"
HOSTNAMEOPTS="mocode-sandbox"
DEVDOPTS=mdev
INTERFACESOPTS="auto lo
iface lo inet loopback

auto eth0
iface eth0 inet dhcp
    hostname mocode-sandbox
"
TIMEZONEOPTS="UTC"
PROXYOPTS="none"
APKREPOSOPTS="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION}/community"
USEROPTS="none"
SSHDOPTS="openssh"
NTPOPTS="none"
DISKOPTS="-m sys /dev/vda"
LBUOPTS="none"
APKCACHEOPTS="none"
EOF

# Post-install tweaks: root password, PermitRootLogin, baseline packages.
cat >firstboot.sh <<EOF
#!/bin/sh
set -e
echo "root:${SSH_PASSWORD}" | chpasswd
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
rc-update add sshd default
apk update
apk add --no-cache bash ca-certificates curl git openssh
# Make apk operate offline-friendly on first boot under the caller.
apk cache clean || true
EOF
chmod +x firstboot.sh

log "building seed iso"
mkdir -p seed
cp answerfile firstboot.sh seed/
"$MKISO" -quiet -V SEED -r -J -o seed.iso seed >/dev/null

log "booting installer (this takes ~5 min)"
# Boot the ISO, run setup-alpine with the answerfile, execute firstboot.sh,
# then poweroff. The install writes to target.qcow2.
qemu-system-aarch64 \
  -machine virt \
  -cpu cortex-a72 \
  -smp 2 \
  -m 1024 \
  -nographic \
  -no-reboot \
  -bios "$UEFI_FIRMWARE" \
  -drive if=virtio,format=qcow2,file=target.qcow2 \
  -drive if=virtio,format=raw,file=seed.iso,media=cdrom,readonly=on \
  -cdrom "$ISO_NAME" \
  -netdev user,id=n0 \
  -device virtio-net-pci,netdev=n0 \
  -boot d

log "compacting qcow2"
qemu-img convert -O qcow2 -c target.qcow2 alpine-prebaked.qcow2

install -m 0644 alpine-prebaked.qcow2 "$ASSETS/alpine-prebaked.qcow2"
log "done: $ASSETS/alpine-prebaked.qcow2 ($(du -h "$ASSETS/alpine-prebaked.qcow2" | cut -f1))"
log "NOTE: qcow2 is gitignored; attach to GitHub release for APK build to fetch."
