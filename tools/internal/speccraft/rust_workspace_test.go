package speccraft_test

import (
	"os"
	"path/filepath"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func TestIsCargoWorkspace_NoCargoToml(t *testing.T) {
	root := t.TempDir()
	got, err := speccraft.IsCargoWorkspace(root)
	if err != nil {
		t.Fatal(err)
	}
	if got {
		t.Error("expected false for empty root (no Cargo.toml)")
	}
}

func TestIsCargoWorkspace_PackageOnly(t *testing.T) {
	root := t.TempDir()
	if err := os.WriteFile(filepath.Join(root, "Cargo.toml"),
		[]byte("[package]\nname = \"foo\"\nversion = \"0.1.0\"\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.IsCargoWorkspace(root)
	if err != nil {
		t.Fatal(err)
	}
	if got {
		t.Error("expected false for [package]-only Cargo.toml")
	}
}

func TestIsCargoWorkspace_WorkspaceOnly(t *testing.T) {
	root := t.TempDir()
	content := "[workspace]\nmembers = [\"crate-a\", \"crate-b\"]\n"
	if err := os.WriteFile(filepath.Join(root, "Cargo.toml"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.IsCargoWorkspace(root)
	if err != nil {
		t.Fatal(err)
	}
	if !got {
		t.Error("expected true for [workspace] Cargo.toml")
	}
}

func TestIsCargoWorkspace_HybridPackageAndWorkspace(t *testing.T) {
	root := t.TempDir()
	content := `[package]
name = "foo"
version = "0.1.0"

[workspace]
members = ["crate-a"]
`
	if err := os.WriteFile(filepath.Join(root, "Cargo.toml"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.IsCargoWorkspace(root)
	if err != nil {
		t.Fatal(err)
	}
	if !got {
		t.Error("expected true for hybrid [package]+[workspace] Cargo.toml")
	}
}

func TestIsCargoWorkspace_WorkspaceInCommentNotMatched(t *testing.T) {
	root := t.TempDir()
	content := "# [workspace] this is a comment\n[package]\nname = \"foo\"\n"
	if err := os.WriteFile(filepath.Join(root, "Cargo.toml"), []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
	got, err := speccraft.IsCargoWorkspace(root)
	if err != nil {
		t.Fatal(err)
	}
	if got {
		t.Error("expected false when [workspace] appears only in a comment")
	}
}
