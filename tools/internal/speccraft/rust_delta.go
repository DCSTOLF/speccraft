package speccraft

import (
	"path/filepath"
	"strings"
)

// IsRustTestEdit classifies an Edit/Write to a Rust source file as a
// "test edit" by computing the canonical-ID delta between the pre-edit
// and proposed post-edit file content. The edit is a test edit iff
// `post − pre` is non-empty.
//
// filePath is the path of the edited file (used to distinguish
// integration files under tests/ from src files). fileStem is the
// canonical-form prefix (per spec §What.3): for src/foo.rs this is
// "foo"; for tests/bar.rs this is "bar".
//
// Implements the AC #2 four-case fixture matrix and the §Limitations
// §L2 documented behavior (macro_rules! phantom IDs are accepted; the
// runner is the backstop).
func IsRustTestEdit(filePath, fileStem, preContent, postContent string) bool {
	pre := CanonicalIDsForFile(filePath, fileStem, preContent)
	post := CanonicalIDsForFile(filePath, fileStem, postContent)

	preSet := map[string]struct{}{}
	for _, id := range pre {
		preSet[id] = struct{}{}
	}
	for _, id := range post {
		if _, exists := preSet[id]; !exists {
			return true
		}
	}
	return false
}

// CanonicalIDsForFile returns the canonical Rust test IDs in content,
// dispatching to the inline-test extractor (for src/**/*.rs) or the
// integration-test extractor (for tests/**/*.rs) based on filePath.
// This is the single helper used by both the static-detection delta
// (IsRustTestEdit) and the guard's post-edit-state modeling
// (speccraft-guard/main.go).
func CanonicalIDsForFile(filePath, fileStem, content string) []string {
	if IsRustIntegrationTestFile(filePath) {
		return CanonicalIntegrationTestIDs(content, fileStem)
	}
	return CanonicalInlineTestIDs(content, fileStem)
}

// IsRustIntegrationTestFile returns true if path is under a top-level
// `tests/` directory (Cargo integration-test target). The check is
// path-based: tests/<stem>.rs at the repo root, or paths containing
// "/tests/" for fixture/test setups.
func IsRustIntegrationTestFile(path string) bool {
	clean := filepath.ToSlash(path)
	return strings.HasPrefix(clean, "tests/") || strings.Contains(clean, "/tests/")
}
