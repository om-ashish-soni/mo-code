package proot

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
)

// ExtractPrebaked unpacks a prebaked Alpine rootfs tarball (gzip-compressed
// tar, as produced by scripts/build-prebaked-rootfs.sh) into destDir.
//
// It is a self-contained replacement for the runtime `apk update && apk add`
// path that dies silently under Android 15's zygote seccomp filter
// (see docs/issues/ISSUE-010). The extracted tree already contains git,
// node, python, and friends, so the first Exec() on a fresh install does
// not need network or a working package manager.
//
// The caller is expected to have verified the tarball's integrity upstream
// (e.g. CHECKSUMS asset on the Kotlin side). This function focuses on safe
// extraction: zip-slip protection, symlink handling, and respecting ctx
// cancellation for cooperative abort on slow devices.
//
// destDir is created if missing. Existing contents are left alone — the
// caller should wipe the directory first if a clean reinstall is required.
func ExtractPrebaked(ctx context.Context, tarballPath, destDir string) error {
	if tarballPath == "" {
		return errors.New("prebaked: tarballPath is empty")
	}
	if destDir == "" {
		return errors.New("prebaked: destDir is empty")
	}

	f, err := os.Open(tarballPath)
	if err != nil {
		return fmt.Errorf("prebaked: open tarball: %w", err)
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("prebaked: gzip reader: %w", err)
	}
	defer gz.Close()

	if err := os.MkdirAll(destDir, 0o755); err != nil {
		return fmt.Errorf("prebaked: create destDir: %w", err)
	}

	// Resolve once so zip-slip checks compare canonical paths.
	destAbs, err := filepath.Abs(destDir)
	if err != nil {
		return fmt.Errorf("prebaked: abs destDir: %w", err)
	}

	tr := tar.NewReader(gz)
	for {
		if err := ctx.Err(); err != nil {
			return err
		}

		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("prebaked: tar next: %w", err)
		}

		// Strip any leading "./" so paths join cleanly with destDir.
		name := strings.TrimPrefix(hdr.Name, "./")
		if name == "" || name == "." {
			continue
		}

		target := filepath.Join(destAbs, name)
		if !isWithin(destAbs, target) {
			// Zip-slip: entry tries to escape destDir. Skip silently —
			// erroring out would let a single bad entry kill extraction
			// of an otherwise-valid tarball.
			continue
		}

		mode := os.FileMode(hdr.Mode) & os.ModePerm

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, 0o755); err != nil {
				return fmt.Errorf("prebaked: mkdir %s: %w", target, err)
			}

		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return fmt.Errorf("prebaked: mkdir parent of %s: %w", target, err)
			}
			if err := writeRegular(tr, target, mode); err != nil {
				return err
			}

		case tar.TypeSymlink:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return fmt.Errorf("prebaked: mkdir parent of %s: %w", target, err)
			}
			// Remove any existing entry so repeat extractions don't fail
			// on symlink creation. Safe because ExtractPrebaked is
			// documented as additive-over-clean.
			_ = os.Remove(target)
			if err := os.Symlink(hdr.Linkname, target); err != nil {
				return fmt.Errorf("prebaked: symlink %s -> %s: %w", target, hdr.Linkname, err)
			}

		case tar.TypeLink:
			// Hard link. Android's app data dir supports hard links within
			// the same filesystem, but fall back to a copy if Link fails —
			// some bind-mounted layouts reject cross-subtree links.
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return fmt.Errorf("prebaked: mkdir parent of %s: %w", target, err)
			}
			linkSource := filepath.Join(destAbs, strings.TrimPrefix(hdr.Linkname, "./"))
			_ = os.Remove(target)
			if err := os.Link(linkSource, target); err != nil {
				if copyErr := copyFile(linkSource, target); copyErr != nil {
					return fmt.Errorf("prebaked: link %s -> %s: %w (copy fallback: %v)", target, linkSource, err, copyErr)
				}
			}

		default:
			// Skip char/block/fifo devices — proot doesn't need them inside
			// the rootfs (it binds /dev from the host).
		}
	}
	return nil
}

func writeRegular(r io.Reader, target string, mode os.FileMode) error {
	// O_TRUNC so re-extraction overwrites stale content cleanly.
	out, err := os.OpenFile(target, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return fmt.Errorf("prebaked: create %s: %w", target, err)
	}
	if _, err := io.Copy(out, r); err != nil {
		out.Close()
		return fmt.Errorf("prebaked: write %s: %w", target, err)
	}
	if err := out.Close(); err != nil {
		return fmt.Errorf("prebaked: close %s: %w", target, err)
	}
	// Preserve exec bits when present. proot-launched shells rely on
	// /bin/sh, /usr/bin/git etc. actually being executable inside the
	// extracted tree.
	if mode != 0 {
		if err := os.Chmod(target, mode); err != nil {
			return fmt.Errorf("prebaked: chmod %s: %w", target, err)
		}
	}
	return nil
}

func copyFile(src, dst string) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_TRUNC, 0o644)
	if err != nil {
		return err
	}
	if _, err := io.Copy(out, in); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

func isWithin(parent, child string) bool {
	rel, err := filepath.Rel(parent, child)
	if err != nil {
		return false
	}
	return rel != ".." && !strings.HasPrefix(rel, ".."+string(filepath.Separator))
}
