# QEMU sandbox assets

Populated by `scripts/build-qemu-image.sh` and `scripts/build-qemu-binary.sh`.

Expected files (gitignored; ship via GitHub release):

- `qemu-system-aarch64-arm64` — static qemu-system-aarch64 for Android.
- `qemu-img-arm64` — static qemu-img (used to manage per-boot overlay qcow2).
- `alpine-prebaked.qcow2` — Alpine 3.19 aarch64 with sshd + bash + git baked in.

See `docs/SANDBOX_QEMU.md` for the full build and packaging flow.
