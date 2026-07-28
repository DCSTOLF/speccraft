package main

import (
	"strings"
	"testing"
)

func Test_StateCmd_GetStatus_PrintsBareValueNewline(t *testing.T) {
	repo := makeRepo(t)
	mkSpecDir(t, repo, "0037-x", "---\nstatus: reviewed\n---\n")
	code, stdout, stderr := runCmd(t, repo, "get-status", "0037-x")
	if code != 0 {
		t.Fatalf("exit=%d stderr=%s", code, stderr)
	}
	if stdout != "reviewed\n" {
		t.Errorf("stdout=%q, want %q (bare value + newline)", stdout, "reviewed\n")
	}
}

func Test_StateCmd_GetStatus_LiveWinsOverArchive(t *testing.T) {
	repo := makeRepo(t)
	mkSpecDir(t, repo, "0037-x", "---\nstatus: in-progress\n---\n")
	mkSpecDir(t, repo, ".archive/0037-x", "---\nstatus: closed\n---\n")
	code, stdout, _ := runCmd(t, repo, "get-status", "0037-x")
	if code != 0 || strings.TrimSpace(stdout) != "in-progress" {
		t.Errorf("got (%d, %q), want (0, in-progress) — live wins over archive", code, stdout)
	}
}

func Test_StateCmd_GetStatus_ArchiveFallback(t *testing.T) {
	repo := makeRepo(t)
	mkSpecDir(t, repo, ".archive/0037-x", "---\nstatus: closed\n---\n")
	code, stdout, _ := runCmd(t, repo, "get-status", "0037-x")
	if code != 0 || strings.TrimSpace(stdout) != "closed" {
		t.Errorf("got (%d, %q), want (0, closed) — archive fallback", code, stdout)
	}
}

func Test_StateCmd_GetStatus_NotFound_NonZero(t *testing.T) {
	repo := makeRepo(t)
	code, stdout, stderr := runCmd(t, repo, "get-status", "9999-nope")
	if code == 0 {
		t.Fatal("want non-zero when spec resolves in neither location")
	}
	if stdout != "" {
		t.Errorf("stdout=%q, want empty on failure", stdout)
	}
	if !strings.Contains(stderr, "not found") {
		t.Errorf("stderr=%q, want 'not found'", stderr)
	}
}

func Test_StateCmd_GetStatus_NoStatusField_NonZero(t *testing.T) {
	repo := makeRepo(t)
	mkSpecDir(t, repo, "0037-x", "---\ntitle: x\n---\n")
	code, stdout, stderr := runCmd(t, repo, "get-status", "0037-x")
	if code == 0 {
		t.Fatal("want non-zero when resolved spec lacks a status field")
	}
	if stdout != "" {
		t.Errorf("stdout=%q, want empty on failure", stdout)
	}
	if !strings.Contains(stderr, "no status field") {
		t.Errorf("stderr=%q, want 'no status field'", stderr)
	}
}
