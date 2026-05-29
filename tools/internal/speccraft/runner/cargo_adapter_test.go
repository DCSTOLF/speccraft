package runner

import (
	"context"
	"strings"
	"testing"
)

// recordingExec captures argv and returns canned stdout/stderr/exitcode.
type recordingExec struct {
	name     string
	args     []string
	workDir  string
	stdout   string
	stderr   string
	exitCode int
	err      error
}

func (r *recordingExec) fn() execFn {
	return func(_ context.Context, name string, args []string, workDir string) ([]byte, []byte, int, error) {
		r.name = name
		r.args = args
		r.workDir = workDir
		return []byte(r.stdout), []byte(r.stderr), r.exitCode, r.err
	}
}

func TestCargoAdapter_BuildArgv_TargetsExactTest(t *testing.T) {
	rec := &recordingExec{stdout: "test foo::tests::it_fails ... FAILED\n", exitCode: 101}
	a := &CargoAdapter{exec: rec.fn()}
	_, err := a.Run(context.Background(), Request{
		WorkDir:                "/repo",
		FullyQualifiedTestName: "foo::tests::it_fails",
	})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if rec.name != "cargo" {
		t.Errorf("argv[0] = %q, want %q", rec.name, "cargo")
	}
	wantArgs := []string{"test", "--no-fail-fast", "--quiet", "--", "--exact", "foo::tests::it_fails"}
	if !equalArgs(rec.args, wantArgs) {
		t.Errorf("args = %v, want %v", rec.args, wantArgs)
	}
	if rec.workDir != "/repo" {
		t.Errorf("workDir = %q, want %q", rec.workDir, "/repo")
	}
}

func TestCargoAdapter_Classify_AllPassed(t *testing.T) {
	rec := &recordingExec{stdout: "test foo::tests::a ... ok\n", exitCode: 0}
	a := &CargoAdapter{exec: rec.fn()}
	res, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::tests::a"})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if res.Outcome != OutcomeAllPassed {
		t.Errorf("Outcome = %v, want OutcomeAllPassed", res.Outcome)
	}
}

func TestCargoAdapter_Classify_AtLeastOneFailed(t *testing.T) {
	rec := &recordingExec{stdout: "test foo::tests::a ... FAILED\n", exitCode: 101}
	a := &CargoAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::tests::a"})
	if res.Outcome != OutcomeAtLeastOneFailed {
		t.Errorf("Outcome = %v, want OutcomeAtLeastOneFailed", res.Outcome)
	}
}

func TestCargoAdapter_Classify_BuildFailed(t *testing.T) {
	rec := &recordingExec{
		stdout:   "",
		stderr:   "error[E0425]: cannot find value `whoops` in this scope\n\nerror: could not compile `mycrate`\n",
		exitCode: 101,
	}
	a := &CargoAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::tests::a"})
	if res.Outcome != OutcomeBuildFailed {
		t.Errorf("Outcome = %v, want OutcomeBuildFailed", res.Outcome)
	}
	if !strings.Contains(res.Stderr, "could not compile") {
		t.Errorf("Stderr did not bubble up: %q", res.Stderr)
	}
}

func TestCargoAdapter_IgnoredRecordsAreNotFailures(t *testing.T) {
	rec := &recordingExec{stdout: "test foo::tests::a ... ignored\n", exitCode: 0}
	a := &CargoAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::tests::a"})
	if res.Outcome != OutcomeAllPassed {
		t.Errorf("Outcome = %v, want OutcomeAllPassed (ignored is not a failure)", res.Outcome)
	}
}

func TestCargoAdapter_StripsCratePrefix(t *testing.T) {
	rec := &recordingExec{stdout: "test mycrate::foo::tests::a ... ok\n", exitCode: 0}
	a := &CargoAdapter{exec: rec.fn(), CrateName: "mycrate"}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::tests::a"})
	if len(res.Records) != 1 || res.Records[0].TestName != "foo::tests::a" {
		t.Errorf("Records = %+v", res.Records)
	}
}

func equalArgs(a, b []string) bool {
	if len(a) != len(b) {
		return false
	}
	for i := range a {
		if a[i] != b[i] {
			return false
		}
	}
	return true
}
