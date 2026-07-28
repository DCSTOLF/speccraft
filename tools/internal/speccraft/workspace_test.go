package speccraft_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func Test_ParseWorkspaceMembers_ListedAndMissing_PreservesPresence(t *testing.T) {
	dir := t.TempDir()
	if err := os.MkdirAll(filepath.Join(dir, "api"), 0o755); err != nil {
		t.Fatal(err)
	}
	yml := filepath.Join(dir, "workspace.yml")
	if err := os.WriteFile(yml, []byte("members:\n  - path: ./api\n  - path: ./web\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.ParseWorkspaceMembers(yml)
	if err != nil {
		t.Fatalf("ParseWorkspaceMembers: %v", err)
	}
	want := []speccraft.Member{{Path: "./api", Present: true}, {Path: "./web", Present: false}}
	if len(got) != len(want) {
		t.Fatalf("got %d members %+v, want %d %+v", len(got), got, len(want), want)
	}
	for i := range want {
		if got[i] != want[i] {
			t.Errorf("member[%d] = %+v, want %+v", i, got[i], want[i])
		}
	}
}

func writeYML(t *testing.T, dir, content string, presentDirs ...string) string {
	t.Helper()
	for _, d := range presentDirs {
		if err := os.MkdirAll(filepath.Join(dir, d), 0o755); err != nil {
			t.Fatal(err)
		}
	}
	p := filepath.Join(dir, "workspace.yml")
	if err := os.WriteFile(p, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

func Test_ParseWorkspaceMembers_Grammar(t *testing.T) {
	pass := []struct {
		name        string
		yml         string
		presentDirs []string
		want        []speccraft.Member
	}{
		{"two_members", "members:\n  - path: ./api\n  - path: ./web\n", []string{"api"},
			[]speccraft.Member{{Path: "./api", Present: true}, {Path: "./web", Present: false}}},
		// Design 0001's own example line MUST parse (inline comment stripped).
		{"design0001_inline_comment", "members:\n  - path: ./api      # each has its own .speccraft/\n", []string{"api"},
			[]speccraft.Member{{Path: "./api", Present: true}}},
		{"quoted_interior_space", "members:\n  - path: \"./a b\"\n", nil,
			[]speccraft.Member{{Path: "./a b", Present: false}}},
		{"blank_and_full_comment_lines", "# top\nmembers:\n\n  - path: ./api\n", []string{"api"},
			[]speccraft.Member{{Path: "./api", Present: true}}},
		{"empty_membership", "members:\n", nil, []speccraft.Member{}},
	}
	for _, tc := range pass {
		t.Run("pass/"+tc.name, func(t *testing.T) {
			dir := t.TempDir()
			p := writeYML(t, dir, tc.yml, tc.presentDirs...)
			got, err := speccraft.ParseWorkspaceMembers(p)
			if err != nil {
				t.Fatalf("unexpected error: %v", err)
			}
			if len(got) != len(tc.want) {
				t.Fatalf("got %d %+v, want %d %+v", len(got), got, len(tc.want), tc.want)
			}
			for i := range tc.want {
				if got[i] != tc.want[i] {
					t.Errorf("member[%d] = %+v, want %+v", i, got[i], tc.want[i])
				}
			}
		})
	}

	fail := []struct{ name, yml string }{
		{"absolute_path", "members:\n  - path: /abs\n"},
		{"empty_value", "members:\n  - path:\n"},
		{"bare_interior_space", "members:\n  - path: ./a b\n"},
		{"bare_unescaped_hash", "members:\n  - path: ./a#b\n"},
		{"other_top_level_key", "name: foo\n"},
		{"extra_key_on_entry", "members:\n  - path: ./api\n    name: x\n"},
		{"duplicate_members", "members:\n  - path: ./api\nmembers:\n  - path: ./web\n"},
		{"flow_style", "members: [./api, ./web]\n"},
	}
	for _, tc := range fail {
		t.Run("fail/"+tc.name, func(t *testing.T) {
			dir := t.TempDir()
			p := writeYML(t, dir, tc.yml)
			if _, err := speccraft.ParseWorkspaceMembers(p); err == nil {
				t.Errorf("expected parse error for %q, got nil", tc.yml)
			}
		})
	}
}
