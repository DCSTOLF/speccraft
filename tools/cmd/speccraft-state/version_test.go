package main

import (
	"strings"
	"testing"
)

func Test_StateCmd_Version_Is1140(t *testing.T) {
	repo := makeRepo(t)
	code, stdout, stderr := runCmd(t, repo, "--version")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if got != "1.14.0" {
		t.Errorf("--version = %q, want %q", got, "1.14.0")
	}
}

func Test_StateCmd_Version_NotStale1130(t *testing.T) {
	repo := makeRepo(t)
	_, stdout, _ := runCmd(t, repo, "--version")
	if strings.TrimSpace(stdout) == "1.13.0" {
		t.Error("--version still reports the stale 1.13.0")
	}
}
