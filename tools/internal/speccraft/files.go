package speccraft

import (
	"path/filepath"
	"strings"
)

// IsTestFile returns true for Go test files (*_test.go).
func IsTestFile(path string) bool {
	base := filepath.Base(path)
	return strings.HasSuffix(base, "_test.go")
}

// IsProductionGoFile returns true for Go source files that are not tests.
func IsProductionGoFile(path string) bool {
	base := filepath.Base(path)
	return strings.HasSuffix(base, ".go") && !strings.HasSuffix(base, "_test.go")
}

// IsAlwaysAllowed returns true for paths that bypass the TDD invariant:
// .speccraft/, specs/, docs/, *.md, scratch/.
func IsAlwaysAllowed(root, absPath string) bool {
	rel, err := filepath.Rel(root, absPath)
	if err != nil {
		return false
	}
	// Normalize to forward slashes.
	rel = filepath.ToSlash(rel)

	// Outside the repo root → allow.
	if strings.HasPrefix(rel, "../") {
		return true
	}

	prefix := func(p string) bool { return strings.HasPrefix(rel, p) }
	ext := filepath.Ext(absPath)

	return prefix(".speccraft/") ||
		prefix("specs/") ||
		prefix("docs/") ||
		prefix("scratch/") ||
		ext == ".md" ||
		rel == ".speccraft" ||
		rel == "specs"
}

// SiblingTestFiles returns all *_test.go files in the same directory as path.
func SiblingTestFiles(path string) ([]string, error) {
	dir := filepath.Dir(path)
	matches, err := filepath.Glob(filepath.Join(dir, "*_test.go"))
	if err != nil {
		return nil, err
	}
	return matches, nil
}
