package main

// Spec 0048 T22 (AC17) — `speccraft-state build-repair-log`.
//
// The build-repair log is only worth writing if something reads it. Without a
// consumer, a session could admit ten edits against a broken build and close with
// no trace anyone would ever look at — the audit trail would exist purely to
// satisfy its own tests.
//
// The subcommand is INFORMATIONAL and must never gate: it exits 0 whether the log
// is empty or full. A log that could fail the close would make honest mid-repair
// work look like a failure, which would push people to avoid repair mode rather
// than use it.

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

func Test_StateCmd_BuildRepairLog_EmptyLog_SaysSo(t *testing.T) {
	repo := makeRepo(t)
	code, stdout, stderr := runCmd(t, repo, "build-repair-log")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	if !strings.Contains(strings.ToLower(stdout+stderr), "no build-repair") {
		t.Errorf("an empty log must say so plainly, got stdout=%q stderr=%q", stdout, stderr)
	}
}

func Test_StateCmd_BuildRepairLog_NonEmpty_ListsSeqPathSummary(t *testing.T) {
	repo := makeRepo(t)
	pkg := filepath.Join(repo, "pkg")
	if err := os.MkdirAll(pkg, 0o755); err != nil {
		t.Fatal(err)
	}
	first := filepath.Join(pkg, "foo.go")
	second := filepath.Join(pkg, "bar.go")
	if _, err := speccraft.RecordBuildRepair(repo, first, "undefined: alpha"); err != nil {
		t.Fatal(err)
	}
	if _, err := speccraft.RecordBuildRepair(repo, second, "undefined: beta"); err != nil {
		t.Fatal(err)
	}

	code, stdout, stderr := runCmd(t, repo, "build-repair-log")
	if code != 0 {
		t.Fatalf("exit = %d, want 0; stderr=%s", code, stderr)
	}
	out := stdout + stderr
	for _, want := range []string{"1", "2", "foo.go", "bar.go", "undefined: alpha", "undefined: beta"} {
		if !strings.Contains(out, want) {
			t.Errorf("report is missing %q:\n%s", want, out)
		}
	}
}

// AC17 — informational, never gating. Asserted separately from the content test
// because it is the property that makes the report safe to wire into close: if a
// non-empty log exited non-zero, every legitimate multi-step repair would fail the
// close and the feature would become something to route around.
func Test_StateCmd_BuildRepairLog_NeverNonZeroOnContent(t *testing.T) {
	repo := makeRepo(t)
	pkg := filepath.Join(repo, "pkg")
	if err := os.MkdirAll(pkg, 0o755); err != nil {
		t.Fatal(err)
	}
	// Fill the budget completely — the most "alarming" log there can be.
	for i := 0; i < 10; i++ {
		if _, err := speccraft.RecordBuildRepair(repo, filepath.Join(pkg, "foo.go"), "undefined: x"); err != nil {
			t.Fatal(err)
		}
	}
	code, _, stderr := runCmd(t, repo, "build-repair-log")
	if code != 0 {
		t.Errorf("a full log must still exit 0 — the report must not gate the close; stderr=%s", stderr)
	}
}

// A long error is truncated in the stored summary; the report must not then claim
// to be showing the whole thing. Pins that the truncation marker survives to the
// reader.
func Test_StateCmd_BuildRepairLog_TruncatedSummary_MarkerIsVisible(t *testing.T) {
	repo := makeRepo(t)
	pkg := filepath.Join(repo, "pkg")
	if err := os.MkdirAll(pkg, 0o755); err != nil {
		t.Fatal(err)
	}
	big := strings.Repeat("E", (4<<10)+256)
	if _, err := speccraft.RecordBuildRepair(repo, filepath.Join(pkg, "foo.go"), big); err != nil {
		t.Fatal(err)
	}
	code, stdout, stderr := runCmd(t, repo, "build-repair-log")
	if code != 0 {
		t.Fatalf("exit = %d, want 0", code)
	}
	if !strings.Contains(stdout+stderr, "truncated") {
		t.Error("a truncated summary must still read as truncated in the report")
	}
}
