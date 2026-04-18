#!/usr/bin/env bash
# Build a fully-provisioned Alpine arm64 rootfs tarball for proot on Android.
#
# The stock Alpine minirootfs ships empty and relies on `apk update && apk add`
# at runtime. Under Android 15's zygote seccomp filter that path dies silently
# (see docs/issues/ISSUE-010). Prebaking the packages offline removes the
# runtime apk dependency entirely — first launch just extracts this tarball
# and the env is already usable.
#
# Requirements:
#   - docker
#   - qemu-user-static registered with binfmt_misc (for arm64 emulation on
#     x86_64 hosts). The script attempts to register it via tonistiigi/binfmt.
#
# Output:
#   flutter/android/app/src/main/assets/rootfs/alpine-prebaked-arm64.tar.gz
#
# Target: < 150MB compressed. Packages are chosen for mo-code's agent needs:
# git, node, python, curl, ssh — everything required to clone a repo, run
# common tooling, and talk to remote hosts.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"
OUT_DIR="$REPO_ROOT/flutter/android/app/src/main/assets/rootfs"
OUT_FILE="$OUT_DIR/alpine-prebaked-arm64.tar.gz"
VERSION_FILE="$OUT_DIR/PREBAKED_VERSION"

ALPINE_VERSION="3.19"
PLATFORM="linux/arm64"
BUILD_IMAGE="mocode-prebaked-alpine:${ALPINE_VERSION}-arm64"
SIZE_WARN_MB=150

# Packages installed into the rootfs. Keep this list minimal — every addition
# increases the tarball and therefore the APK download. Runtime `apk add` is
# still available as a fallback for anything missing, but the goal is that
# first-launch works without it.
PACKAGES=(
  git
  nodejs
  npm
  python3
  py3-pip
  curl
  openssh-client
  ca-certificates
  bash
)

log() { printf '[prebake] %s\n' "$*" >&2; }
die() { printf '[prebake] ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker not found in PATH"

log "Registering qemu-user-static (arm64 binfmt)..."
docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null 2>&1 \
  || log "binfmt registration failed or already registered — continuing"

mkdir -p "$OUT_DIR"

log "Building prebaked image: $BUILD_IMAGE"
# Heredoc Dockerfile keeps the build self-contained — no separate file to
# keep in sync. BuildKit not required, stays compatible with older docker.
DOCKER_BUILDKIT=0 docker build \
  --platform "$PLATFORM" \
  --tag "$BUILD_IMAGE" \
  - <<DOCKERFILE
FROM alpine:${ALPINE_VERSION}

# Install the prebaked toolset. --no-cache avoids writing apk indexes we'd
# have to clean up afterwards.
RUN apk add --no-cache ${PACKAGES[*]}

# Create the developer home that proot binds projects into, and a matching
# user entry so tools that read /etc/passwd (ssh, git) don't complain.
RUN mkdir -p /home/developer \
 && echo "developer:x:1000:1000:developer:/home/developer:/bin/sh" >> /etc/passwd \
 && echo "developer:x:1000:" >> /etc/group \
 && chown -R 1000:1000 /home/developer

# Fallback resolv.conf — RuntimeBootstrap overwrites this with the device
# DNS at runtime, but we need *something* here so that apk/curl work during
# smoke tests before the runtime overwrites it.
RUN printf 'nameserver 8.8.8.8\nnameserver 8.8.4.4\n' > /etc/resolv.conf

# Trim obvious bulk. Keep /var/cache/apk wiped.
RUN rm -rf /var/cache/apk/* /tmp/* /root/.cache 2>/dev/null || true
DOCKERFILE

log "Exporting rootfs from container..."
CID="$(docker create --platform "$PLATFORM" "$BUILD_IMAGE")"
trap 'docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT

# docker export emits a plain tar of the container filesystem. Pipe through
# gzip -9 for the smallest asset size; the one-time extraction cost on-device
# is dwarfed by download savings.
TMP_TAR="$(mktemp --suffix=.tar)"
trap 'rm -f "$TMP_TAR"; docker rm -f "$CID" >/dev/null 2>&1 || true' EXIT
docker export "$CID" > "$TMP_TAR"

log "Compressing tarball..."
gzip -9 -c "$TMP_TAR" > "$OUT_FILE"

BYTES="$(stat -c%s "$OUT_FILE")"
MB="$(( BYTES / 1024 / 1024 ))"
log "Output: $OUT_FILE (${MB} MB)"

if [ "$MB" -gt "$SIZE_WARN_MB" ]; then
  log "WARNING: tarball is ${MB} MB, exceeds ${SIZE_WARN_MB} MB target"
  log "WARNING: do not commit this file — ship via GitHub release instead"
fi

# Emit a small version marker next to the tarball so RuntimeBootstrap can
# detect when the prebake needs to be re-extracted after an upgrade.
PREBAKED_VERSION="alpine-${ALPINE_VERSION}+$(date -u +%Y%m%d)"
printf '%s\n' "$PREBAKED_VERSION" > "$VERSION_FILE"

SHA="$(sha256sum "$OUT_FILE" | cut -d' ' -f1)"
log "SHA256:  $SHA"
log "Version: $PREBAKED_VERSION"
log "Done."
