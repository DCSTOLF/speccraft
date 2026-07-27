package speccraft_test

// Spec 0034 AC8 — the JSON manifests must carry the bumped version. plugin.json
// and marketplace.json aren't assertable from a `package main` const, so this is
// the grep-oracle counterpart (spec 0011/0016 pattern): a positive match on the
// new version plus a negative check that the stale version is gone.

import (
	"path/filepath"
	"strings"
	"testing"
)

func Test_Manifests_VersionIs1110(t *testing.T) {
	root := findDocsRoot(t)
	const want = `"version": "1.11.0"`
	const stale = "1.10.0"
	for _, rel := range []string{
		filepath.Join(".claude-plugin", "plugin.json"),
		filepath.Join(".claude-plugin", "marketplace.json"),
	} {
		src := readFile(t, filepath.Join(root, rel))
		if !strings.Contains(src, want) {
			t.Errorf("%s: missing %s (spec 0035 AC12 version bump)", rel, want)
		}
		if strings.Contains(src, stale) {
			t.Errorf("%s: still contains stale version %q", rel, stale)
		}
	}
}
