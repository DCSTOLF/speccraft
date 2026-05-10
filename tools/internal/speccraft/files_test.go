package speccraft_test

import (
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestIsTestFile(t *testing.T) {
	cases := []struct {
		path string
		want bool
	}{
		{"pkg/foo/bar_test.go", true},
		{"pkg/foo/bar.go", false},
		{"pkg/foo/bar.go.bak", false},
		{"/abs/path/handler_test.go", true},
	}
	for _, c := range cases {
		got := speccraft.IsTestFile(c.path)
		if got != c.want {
			t.Errorf("IsTestFile(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}

func TestIsAlwaysAllowed(t *testing.T) {
	root := "/repo"
	cases := []struct {
		path string
		want bool
	}{
		{"/repo/.speccraft/guardrails.md", true},
		{"/repo/specs/0001-foo/spec.md", true},
		{"/repo/docs/README.md", true},
		{"/repo/scratch/exp.go", true},
		{"/repo/README.md", true},
		{"/repo/internal/foo/bar.go", false},
		{"/other/path/file.go", true}, // outside root → always allow
	}
	for _, c := range cases {
		got := speccraft.IsAlwaysAllowed(root, c.path)
		if got != c.want {
			t.Errorf("IsAlwaysAllowed(%q) = %v, want %v", c.path, got, c.want)
		}
	}
}
