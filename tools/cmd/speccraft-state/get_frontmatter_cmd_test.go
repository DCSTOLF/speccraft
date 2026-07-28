package main

import (
	"path/filepath"
	"testing"
)

func Test_StateCmd_GetFrontmatter_Design_PrintsValue(t *testing.T) {
	repo := makeRepo(t)
	dir := mkSpecDir(t, repo, "0037-x", "---\ndesign: 0001-foo\n---\n")
	specMd := filepath.Join(dir, "spec.md")
	code, stdout, stderr := runCmd(t, repo, "get-frontmatter", specMd, "design")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	if stdout != "0001-foo\n" {
		t.Errorf("stdout=%q, want %q", stdout, "0001-foo\n")
	}
}

func Test_StateCmd_GetFrontmatter_Design_AbsentPrintsEmptyLineExitZero(t *testing.T) {
	repo := makeRepo(t)
	dir := mkSpecDir(t, repo, "0037-x", "---\ntitle: x\n---\n")
	specMd := filepath.Join(dir, "spec.md")
	code, stdout, _ := runCmd(t, repo, "get-frontmatter", specMd, "design")
	if code != 0 {
		t.Fatalf("want exit 0 for absent key (never errors on the key), got %d", code)
	}
	if stdout != "\n" {
		t.Errorf("stdout=%q, want a single empty line", stdout)
	}
}

func Test_StateCmd_GetFrontmatter_MissingFile_NonZero(t *testing.T) {
	repo := makeRepo(t)
	code, _, _ := runCmd(t, repo, "get-frontmatter", filepath.Join(repo, "nope.md"), "design")
	if code == 0 {
		t.Fatal("want non-zero for missing file (unrelated to the key)")
	}
}
