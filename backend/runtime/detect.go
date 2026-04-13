package runtime

import (
	"os"
	"path/filepath"
)

// ProjectType represents a detected project type and its required packages.
type ProjectType struct {
	// Name is a human-readable name (e.g. "Node.js", "Python").
	Name string
	// MarkerFile is the file that triggered detection.
	MarkerFile string
	// Packages are the Alpine apk packages to install.
	Packages []string
}

// detectionRules maps marker files to project types and required packages.
var detectionRules = []struct {
	marker   string
	name     string
	packages []string
}{
	{"package.json", "Node.js", []string{"nodejs", "npm"}},
	{"requirements.txt", "Python", []string{"python3", "py3-pip"}},
	{"pyproject.toml", "Python", []string{"python3", "py3-pip"}},
	{"setup.py", "Python", []string{"python3", "py3-pip"}},
	{"go.mod", "Go", []string{"go"}},
	{"Cargo.toml", "Rust", []string{"rust", "cargo"}},
	{"Gemfile", "Ruby", []string{"ruby"}},
	{"pom.xml", "Java", []string{"openjdk17"}},
	{"build.gradle", "Java", []string{"openjdk17"}},
	{"composer.json", "PHP", []string{"php", "php-cli"}},
	{"Makefile", "Make", []string{"make", "gcc"}},
	{"CMakeLists.txt", "C/C++", []string{"cmake", "gcc", "g++", "make"}},
}

// DetectProject scans a directory for marker files and returns all detected
// project types with their required packages. A project can match multiple
// types (e.g. a Node.js project with a Makefile).
func DetectProject(projectDir string) []ProjectType {
	var detected []ProjectType
	seen := make(map[string]bool) // dedupe by name

	for _, rule := range detectionRules {
		markerPath := filepath.Join(projectDir, rule.marker)
		if _, err := os.Stat(markerPath); err == nil {
			if !seen[rule.name] {
				detected = append(detected, ProjectType{
					Name:       rule.name,
					MarkerFile: rule.marker,
					Packages:   rule.packages,
				})
				seen[rule.name] = true
			}
		}
	}

	return detected
}

// AllPackages returns a deduplicated flat list of all packages required
// for the given project types.
func AllPackages(types []ProjectType) []string {
	seen := make(map[string]bool)
	var packages []string
	for _, t := range types {
		for _, pkg := range t.Packages {
			if !seen[pkg] {
				packages = append(packages, pkg)
				seen[pkg] = true
			}
		}
	}
	return packages
}
