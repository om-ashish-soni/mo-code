// Package termux implements the termux-prefix sandbox backend.
//
// The backend runs bionic-linked binaries (busybox, git, nodejs, python3, curl)
// natively on Android, with PATH and LD_LIBRARY_PATH pointing into an
// app-private prefix directory. No ptrace, no VM, no syscall translation —
// binaries execute directly against the Android kernel. Isolation tier 1:
// same UID and same kernel as the host app, but a separate filesystem view
// for the toolchain.
//
// Prefix layout (under $appFiles/termux-prefix):
//
//	bin/          busybox + symlinks (sh, cat, ls, …), git, node, python3, curl
//	lib/          shared libraries for the bundled toolset
//	libexec/      helper executables (git-core, …)
//	share/        read-only data (terminfo, certs, python stdlib, …)
//	etc/          resolv.conf (written at Prepare), profile.d
//	home/         symlink into projectsDir; cwd default
//	tmp/          writable scratch
//	var/          stateful data (pkg cache, if package manager is used)
//	.installed    stamp file recording the bundled tarball version
package termux

import (
	"archive/tar"
	"compress/gzip"
	"context"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"strings"
	"time"
)

// prefixLayout describes the on-disk layout of an extracted termux prefix.
type prefixLayout struct {
	// Root is the absolute path to the prefix directory (e.g. /data/.../termux-prefix).
	Root string

	// Projects is the host path that will appear as $Root/home inside the prefix.
	// May be empty; if set, Prepare creates a symlink (or bind-style link) from
	// $Root/home to Projects.
	Projects string
}

// binDir is the primary executable directory inside the prefix.
func (p *prefixLayout) binDir() string { return filepath.Join(p.Root, "bin") }

// libDir is the shared-library directory inside the prefix.
func (p *prefixLayout) libDir() string { return filepath.Join(p.Root, "lib") }

// usrBinDir is the secondary executable directory (some Termux packages land here).
func (p *prefixLayout) usrBinDir() string { return filepath.Join(p.Root, "usr", "bin") }

// usrLibDir is the secondary shared-library directory.
func (p *prefixLayout) usrLibDir() string { return filepath.Join(p.Root, "usr", "lib") }

// tmpDir is the writable scratch directory inside the prefix.
func (p *prefixLayout) tmpDir() string { return filepath.Join(p.Root, "tmp") }

// homeDir is the cwd default for Exec.
func (p *prefixLayout) homeDir() string { return filepath.Join(p.Root, "home") }

// etcDir holds config files consumed by prefix binaries (resolv.conf, …).
func (p *prefixLayout) etcDir() string { return filepath.Join(p.Root, "etc") }

// stampFile records that a given tarball has been extracted, so repeated
// Prepare() calls become a no-op once the prefix is populated.
func (p *prefixLayout) stampFile() string { return filepath.Join(p.Root, ".installed") }

// shellPath returns the canonical shell inside the prefix. Falls back through
// common Termux/busybox locations.
func (p *prefixLayout) shellPath() string {
	for _, cand := range []string{
		filepath.Join(p.binDir(), "bash"),
		filepath.Join(p.binDir(), "sh"),
		filepath.Join(p.usrBinDir(), "bash"),
		filepath.Join(p.usrBinDir(), "sh"),
	} {
		if isExec(cand) {
			return cand
		}
	}
	// Best-effort fallback: caller's Exec will surface a helpful error.
	return filepath.Join(p.binDir(), "sh")
}

// isExec returns true if path is a regular file with any execute bit set.
func isExec(path string) bool {
	info, err := os.Stat(path)
	if err != nil || info.IsDir() {
		return false
	}
	return info.Mode()&0o111 != 0
}

// ensureDirs creates the writable subdirectories that Exec depends on.
// Safe to call repeatedly.
func (p *prefixLayout) ensureDirs() error {
	for _, dir := range []string{p.Root, p.tmpDir(), p.etcDir(), filepath.Dir(p.homeDir())} {
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return fmt.Errorf("termux: mkdir %s: %w", dir, err)
		}
	}
	return nil
}

// linkHome creates $prefix/home → projectsDir so shell commands that `cd ~`
// land in the user's code. No-op if Projects is empty or the link already
// points at the right target.
func (p *prefixLayout) linkHome() error {
	if p.Projects == "" {
		return os.MkdirAll(p.homeDir(), 0o755)
	}
	if err := os.MkdirAll(p.Projects, 0o755); err != nil {
		return fmt.Errorf("termux: mkdir projects %s: %w", p.Projects, err)
	}
	existing, err := os.Readlink(p.homeDir())
	if err == nil && existing == p.Projects {
		return nil
	}
	// Remove whatever's there (stale link, empty dir) before relinking.
	_ = os.Remove(p.homeDir())
	if err := os.Symlink(p.Projects, p.homeDir()); err != nil {
		return fmt.Errorf("termux: symlink home→projects: %w", err)
	}
	return nil
}

// writeResolvConf writes $prefix/etc/resolv.conf so bundled tools (curl, git,
// pip) can resolve DNS. Android does not expose /etc/resolv.conf to app UIDs,
// so we bake in Google DNS (override with MOCODE_DNS env, comma-separated).
func (p *prefixLayout) writeResolvConf() error {
	servers := os.Getenv("MOCODE_DNS")
	if servers == "" {
		servers = "8.8.8.8,8.8.4.4"
	}
	var buf strings.Builder
	for s := range strings.SplitSeq(servers, ",") {
		s = strings.TrimSpace(s)
		if s != "" {
			buf.WriteString("nameserver " + s + "\n")
		}
	}
	path := filepath.Join(p.etcDir(), "resolv.conf")
	return os.WriteFile(path, []byte(buf.String()), 0o644)
}

// extractTarball decompresses a .tar.gz into p.Root. It refuses to write
// outside the prefix (zip-slip guard) and preserves file modes + symlinks.
// The tarball is expected to have a flat layout whose top-level entries
// match the prefix layout (bin/, lib/, etc/, …).
func (p *prefixLayout) extractTarball(ctx context.Context, tarballPath string) error {
	f, err := os.Open(tarballPath)
	if err != nil {
		return fmt.Errorf("termux: open tarball: %w", err)
	}
	defer f.Close()

	gz, err := gzip.NewReader(f)
	if err != nil {
		return fmt.Errorf("termux: gzip reader: %w", err)
	}
	defer gz.Close()

	tr := tar.NewReader(gz)
	rootAbs, err := filepath.Abs(p.Root)
	if err != nil {
		return fmt.Errorf("termux: abs prefix: %w", err)
	}
	if err := os.MkdirAll(rootAbs, 0o755); err != nil {
		return err
	}

	for {
		if err := ctx.Err(); err != nil {
			return err
		}
		hdr, err := tr.Next()
		if err == io.EOF {
			break
		}
		if err != nil {
			return fmt.Errorf("termux: tar read: %w", err)
		}

		// Strip a leading "./" so tarballs produced by both GNU tar and
		// bsdtar drop into the same layout.
		name := strings.TrimPrefix(hdr.Name, "./")
		if name == "" || name == "." {
			continue
		}
		target := filepath.Join(rootAbs, name)
		// Zip-slip guard: reject entries that escape the prefix.
		if rel, err := filepath.Rel(rootAbs, target); err != nil || strings.HasPrefix(rel, "..") {
			return fmt.Errorf("termux: tar entry escapes prefix: %s", hdr.Name)
		}

		switch hdr.Typeflag {
		case tar.TypeDir:
			if err := os.MkdirAll(target, os.FileMode(hdr.Mode)&0o777); err != nil {
				return err
			}
		case tar.TypeReg:
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			if err := writeTarFile(tr, target, os.FileMode(hdr.Mode)&0o777); err != nil {
				return err
			}
		case tar.TypeSymlink:
			_ = os.Remove(target)
			if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
				return err
			}
			if err := os.Symlink(hdr.Linkname, target); err != nil {
				return err
			}
		case tar.TypeLink:
			_ = os.Remove(target)
			linkTarget := filepath.Join(rootAbs, strings.TrimPrefix(hdr.Linkname, "./"))
			if err := os.Link(linkTarget, target); err != nil {
				// Hard links can fail across filesystems or on FAT
				// sdcards — fall back to a symlink rather than aborting.
				if err := os.Symlink(linkTarget, target); err != nil {
					return err
				}
			}
		default:
			// Skip devices, FIFOs, xattrs — app-UID cannot create these anyway.
		}
	}
	return nil
}

// writeTarFile copies a single tar entry to disk.
func writeTarFile(src io.Reader, target string, mode os.FileMode) error {
	f, err := os.OpenFile(target, os.O_CREATE|os.O_WRONLY|os.O_TRUNC, mode)
	if err != nil {
		return fmt.Errorf("termux: open %s: %w", target, err)
	}
	defer f.Close()
	if _, err := io.Copy(f, src); err != nil {
		return fmt.Errorf("termux: write %s: %w", target, err)
	}
	return nil
}

// markInstalled writes the stamp file recording a successful extraction.
// stamp is an opaque version string (typically the tarball sha256 or the
// caller-provided version).
func (p *prefixLayout) markInstalled(stamp string) error {
	content := fmt.Sprintf("version=%s\nextracted_at=%s\n", stamp, time.Now().UTC().Format(time.RFC3339))
	return os.WriteFile(p.stampFile(), []byte(content), 0o644)
}

// installedStamp returns the stamp value previously written, or "" if the
// prefix has not been extracted yet.
func (p *prefixLayout) installedStamp() string {
	b, err := os.ReadFile(p.stampFile())
	if err != nil {
		return ""
	}
	for line := range strings.SplitSeq(string(b), "\n") {
		if v, ok := strings.CutPrefix(line, "version="); ok {
			return strings.TrimSpace(v)
		}
	}
	return ""
}
