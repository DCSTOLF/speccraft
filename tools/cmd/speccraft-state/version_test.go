package main

import (
	"strings"
	"testing"
)

func Test_StateCmd_Version_Reports110(t *testing.T) {
	repo := makeRepo(t)
	code, stdout, stderr := runCmd(t, repo, "--version")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	got := strings.TrimSpace(stdout)
	if got != "1.1.0" {
		t.Errorf("--version = %q, want %q", got, "1.1.0")
	}
}
