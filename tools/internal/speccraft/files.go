package speccraft

import (
	"os"
	"path/filepath"
	"strings"
)

// IsTestFile returns true for Go, Python, or JS/TS test files.
func IsTestFile(path string) bool {
	base := filepath.Base(path)
	return strings.HasSuffix(base, "_test.go") ||
		strings.HasSuffix(base, "_test.py") ||
		(strings.HasPrefix(base, "test_") && strings.HasSuffix(base, ".py")) ||
		IsJSTSTestFile(path)
}

// IsProductionGoFile returns true for Go source files that are not tests.
func IsProductionGoFile(path string) bool {
	base := filepath.Base(path)
	return strings.HasSuffix(base, ".go") && !strings.HasSuffix(base, "_test.go")
}

// IsProductionPythonFile returns true for Python source files that are not tests.
func IsProductionPythonFile(path string) bool {
	return strings.HasSuffix(path, ".py") && !IsTestFile(path)
}

// jsTSExts is the set of JS/TS file extensions (without leading dot).
var jsTSExts = []string{"js", "ts", "jsx", "tsx", "mjs", "cjs", "mts", "cts"}

// isExcludedJSTSPath returns true when the path contains node_modules or dist
// as an exact slash-separated path segment (filepath.Clean semantics).
func isExcludedJSTSPath(path string) bool {
	clean := filepath.ToSlash(filepath.Clean(path))
	for _, seg := range strings.Split(clean, "/") {
		if seg == "node_modules" || seg == "dist" {
			return true
		}
	}
	return false
}

// isDeclarationFile returns true for .d.ts, .d.mts, and .d.cts files.
func isDeclarationFile(base string) bool {
	return strings.HasSuffix(base, ".d.ts") ||
		strings.HasSuffix(base, ".d.mts") ||
		strings.HasSuffix(base, ".d.cts")
}

// IsJSTSTestFile returns true for JavaScript/TypeScript test files:
// - suffix patterns: *.test.<ext> or *.spec.<ext> for the 8 JS/TS extensions
// - __tests__/ path-segment convention for any of the 8 extensions
// Excludes node_modules/, dist/, and declaration files (.d.ts/.d.mts/.d.cts).
func IsJSTSTestFile(path string) bool {
	if isExcludedJSTSPath(path) {
		return false
	}
	base := filepath.Base(path)
	if isDeclarationFile(base) {
		return false
	}
	// Suffix patterns: *.test.<ext> and *.spec.<ext>
	for _, ext := range jsTSExts {
		if strings.HasSuffix(base, ".test."+ext) || strings.HasSuffix(base, ".spec."+ext) {
			return true
		}
	}
	// __tests__/ directory convention: exact path segment + JS/TS extension
	clean := filepath.ToSlash(filepath.Clean(path))
	segs := strings.Split(clean, "/")
	hasTestsDir := false
	for _, seg := range segs[:len(segs)-1] { // exclude the filename itself
		if seg == "__tests__" {
			hasTestsDir = true
			break
		}
	}
	if hasTestsDir {
		for _, ext := range jsTSExts {
			if strings.HasSuffix(base, "."+ext) {
				return true
			}
		}
	}
	return false
}

// IsProductionJSTSFile returns true for JS/TS production source files:
// not excluded, not a test file, not a declaration file, with a JS/TS extension.
func IsProductionJSTSFile(path string) bool {
	if isExcludedJSTSPath(path) {
		return false
	}
	if IsJSTSTestFile(path) {
		return false
	}
	base := filepath.Base(path)
	if isDeclarationFile(base) {
		return false
	}
	for _, ext := range jsTSExts {
		if strings.HasSuffix(base, "."+ext) {
			return true
		}
	}
	return false
}

// IsRustFile returns true for any `.rs` source file. Rust does not have a
// dedicated test-file naming convention (unit tests live inline inside
// production files; integration tests live under tests/), so the
// guard's Rust dispatch (spec 0005) uses delta-based classification
// rather than a name-based test/prod split.
func IsRustFile(path string) bool {
	return strings.HasSuffix(strings.ToLower(path), ".rs")
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

// SiblingTestFiles returns test files that cover path using a two-tier lookup.
//
// Tier 1 — same-directory siblings (language-appropriate globs):
//   - Go:     *_test.go
//   - Python: test_*.py, *_test.py
//
// Tier 2 — configured test roots (Python only, only when tier 1 finds nothing):
// each root under repoRoot is walked recursively; files whose base name is
// test_<stem>.py or <stem>_test.py are collected.
//
// Pass nil/empty testRoots to get tier-1-only behaviour (same as pre-0003).
// Go files are never affected by testRoots.
func SiblingTestFiles(path, repoRoot string, testRoots []string) ([]string, error) {
	dir := filepath.Dir(path)
	isPython := strings.ToLower(filepath.Ext(path)) == ".py"

	var patterns []string
	if isPython {
		patterns = []string{
			filepath.Join(dir, "test_*.py"),
			filepath.Join(dir, "*_test.py"),
		}
	} else {
		patterns = []string{filepath.Join(dir, "*_test.go")}
	}

	seen := make(map[string]struct{})
	var results []string
	for _, pattern := range patterns {
		matches, err := filepath.Glob(pattern)
		if err != nil {
			return nil, err
		}
		for _, m := range matches {
			if _, ok := seen[m]; !ok {
				seen[m] = struct{}{}
				results = append(results, m)
			}
		}
	}

	// Tier 2: walk configured test roots for a stem match.
	if len(results) == 0 && isPython && len(testRoots) > 0 {
		stem := strings.TrimSuffix(filepath.Base(path), ".py")
		want1 := "test_" + stem + ".py"
		want2 := stem + "_test.py"
		for _, rel := range testRoots {
			absRoot := filepath.Join(repoRoot, rel)
			_ = filepath.Walk(absRoot, func(p string, info os.FileInfo, err error) error {
				if err != nil || info.IsDir() {
					return nil
				}
				base := filepath.Base(p)
				if base == want1 || base == want2 {
					if _, ok := seen[p]; !ok {
						seen[p] = struct{}{}
						results = append(results, p)
					}
				}
				return nil
			})
		}
	}

	return results, nil
}
