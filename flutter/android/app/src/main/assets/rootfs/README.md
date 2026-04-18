# Prebaked Alpine rootfs asset

`alpine-prebaked-arm64.tar.gz` is built by `scripts/build-prebaked-rootfs.sh`
and consumed by `RuntimeBootstrap` / `proot.ExtractPrebaked`.

The tarball itself is gitignored (see repo root `.gitignore`). To produce it
locally before building a release APK:

```bash
./scripts/build-prebaked-rootfs.sh
```

Output drops into this directory next to `PREBAKED_VERSION`. See
`docs/SANDBOX_PREBAKED.md` for the package set and rationale.

For CI and release, the tarball is shipped via GitHub Releases and fetched
by the release build script — do not commit binaries >80MB to the repo.
