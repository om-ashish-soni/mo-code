# termux-prefix APK assets

This directory holds the bundled Termux-style bionic prefix consumed by the
`termux-prefix` sandbox backend (`backend/sandbox/termux/`).

## Files

- `termux-prefix-arm64.tar.gz` — bootstrap tarball (built by
  `scripts/build-termux-prefix.sh`). Extracted by `Backend.Prepare()` into
  `$appFiles/termux-prefix/` on first launch.
- `termux-prefix-arm64.sha256` — expected sha256 of the tarball.
- `termux-prefix-arm64.version` — machine-readable build metadata (bootstrap
  tag, pkg set, tarball sha). The backend writes this value to
  `.installed` inside the prefix so stale extractions are re-applied on
  upgrade.

## Building

```sh
./scripts/build-termux-prefix.sh
```

See the script's header comment for options and prerequisites.

## Size policy

Per `docs/SANDBOX_TRACKS.md`, artifacts >50 MB must be reviewed by the lead
before commit. The build script warns when the tarball crosses that line.
If the bundled pkg set grows past the limit, ship the tarball as a GitHub
release asset and have the Flutter side download it on first run instead.
