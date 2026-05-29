package speccraft

import (
	"os"
	"path/filepath"
	"strings"
)

// DiscoverRustTests walks the crate rooted at `root` and returns the
// sorted, deduplicated canonical IDs (per spec 0005 §What.3) of every
// Rust test found:
//
//   - src/**/*.rs files are scanned for inline `#[cfg(test)] mod` blocks.
//     The file stem comes from the `.rs` filename (so src/foo.rs → "foo",
//     src/lib.rs → "lib"). lib.rs is walked for inline tests; the lib.rs
//     exclusion in AC #3 applies only to stem-mapping (RustProdForTest).
//   - tests/*.rs files are scanned for top-level integration test fns.
//   - The target/ directory is skipped entirely.
//
// Returns an empty slice if no tests are found. Read errors abort the
// walk and propagate.
func DiscoverRustTests(root string) ([]string, error) {
	set := map[string]struct{}{}

	walkDir := func(rel string, isIntegration bool) error {
		base := filepath.Join(root, rel)
		return filepath.Walk(base, func(path string, info os.FileInfo, err error) error {
			if err != nil {
				if os.IsNotExist(err) {
					return nil
				}
				return err
			}
			// Skip target/ if we somehow descended into it via a symlink.
			if info.IsDir() && info.Name() == "target" {
				return filepath.SkipDir
			}
			if info.IsDir() || !strings.HasSuffix(path, ".rs") {
				return nil
			}
			data, err := os.ReadFile(path)
			if err != nil {
				return err
			}
			stem := strings.TrimSuffix(info.Name(), ".rs")
			var ids []string
			if isIntegration {
				ids = CanonicalIntegrationTestIDs(string(data), stem)
			} else {
				ids = CanonicalInlineTestIDs(string(data), stem)
			}
			for _, id := range ids {
				set[id] = struct{}{}
			}
			return nil
		})
	}

	if err := walkDir("src", false); err != nil {
		return nil, err
	}
	if err := walkDir("tests", true); err != nil {
		return nil, err
	}

	out := make([]string, 0, len(set))
	for id := range set {
		out = append(out, id)
	}
	sortStrings(out)
	return out, nil
}

// JustAddedRustTests returns the canonical IDs in `current` that are not
// in `baseline`. The result is sorted and deduplicated.
func JustAddedRustTests(baseline, current []string) []string {
	base := map[string]struct{}{}
	for _, id := range baseline {
		base[id] = struct{}{}
	}
	seen := map[string]struct{}{}
	var out []string
	for _, id := range current {
		if _, inBase := base[id]; inBase {
			continue
		}
		if _, dup := seen[id]; dup {
			continue
		}
		seen[id] = struct{}{}
		out = append(out, id)
	}
	sortStrings(out)
	return out
}
