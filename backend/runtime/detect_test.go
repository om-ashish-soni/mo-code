package runtime

import (
	"os"
	"path/filepath"
	"testing"
)

func TestDetectProjectNode(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "package.json"), []byte("{}"), 0o644)

	types := DetectProject(dir)
	if len(types) != 1 {
		t.Fatalf("expected 1 type, got %d", len(types))
	}
	if types[0].Name != "Node.js" {
		t.Errorf("expected Node.js, got %s", types[0].Name)
	}
	if types[0].MarkerFile != "package.json" {
		t.Errorf("expected package.json marker, got %s", types[0].MarkerFile)
	}
}

func TestDetectProjectPython(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "requirements.txt"), []byte("flask"), 0o644)

	types := DetectProject(dir)
	if len(types) != 1 {
		t.Fatalf("expected 1 type, got %d", len(types))
	}
	if types[0].Name != "Python" {
		t.Errorf("expected Python, got %s", types[0].Name)
	}
}

func TestDetectProjectMultiple(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "package.json"), []byte("{}"), 0o644)
	os.WriteFile(filepath.Join(dir, "Makefile"), []byte("all:"), 0o644)

	types := DetectProject(dir)
	if len(types) != 2 {
		t.Fatalf("expected 2 types, got %d: %v", len(types), types)
	}
}

func TestDetectProjectNone(t *testing.T) {
	dir := t.TempDir()

	types := DetectProject(dir)
	if len(types) != 0 {
		t.Errorf("expected 0 types for empty dir, got %d", len(types))
	}
}

func TestDetectProjectPythonDedup(t *testing.T) {
	dir := t.TempDir()
	// Both markers exist — Python should only appear once.
	os.WriteFile(filepath.Join(dir, "requirements.txt"), []byte("flask"), 0o644)
	os.WriteFile(filepath.Join(dir, "pyproject.toml"), []byte("[project]"), 0o644)

	types := DetectProject(dir)
	if len(types) != 1 {
		t.Fatalf("expected 1 type (deduped), got %d", len(types))
	}
	if types[0].Name != "Python" {
		t.Errorf("expected Python, got %s", types[0].Name)
	}
}

func TestDetectProjectGo(t *testing.T) {
	dir := t.TempDir()
	os.WriteFile(filepath.Join(dir, "go.mod"), []byte("module test"), 0o644)

	types := DetectProject(dir)
	if len(types) != 1 {
		t.Fatalf("expected 1 type, got %d", len(types))
	}
	if types[0].Name != "Go" {
		t.Errorf("expected Go, got %s", types[0].Name)
	}
}

func TestAllPackages(t *testing.T) {
	types := []ProjectType{
		{Name: "Node.js", Packages: []string{"nodejs", "npm"}},
		{Name: "Make", Packages: []string{"make", "gcc"}},
		{Name: "C/C++", Packages: []string{"cmake", "gcc", "g++", "make"}},
	}

	pkgs := AllPackages(types)

	// gcc and make should be deduped.
	expected := []string{"nodejs", "npm", "make", "gcc", "cmake", "g++"}
	if len(pkgs) != len(expected) {
		t.Fatalf("expected %d packages, got %d: %v", len(expected), len(pkgs), pkgs)
	}

	seen := make(map[string]bool)
	for _, p := range pkgs {
		if seen[p] {
			t.Errorf("duplicate package: %s", p)
		}
		seen[p] = true
	}
}
