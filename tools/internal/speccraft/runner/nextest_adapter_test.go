package runner

import (
	"context"
	"errors"
	"os/exec"
	"strings"
	"testing"
)

func TestNextestAdapter_BuildArgv_TargetsExactTest(t *testing.T) {
	rec := &recordingExec{stdout: `{"type":"test","event":"failed","name":"foo::tests::it_fails"}` + "\n", exitCode: 100}
	a := &NextestAdapter{exec: rec.fn()}
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
	wantArgs := []string{
		"nextest", "run",
		"--no-fail-fast",
		"--message-format", "libtest-json",
		"-E", "test(=foo::tests::it_fails)",
	}
	if !equalArgs(rec.args, wantArgs) {
		t.Errorf("args = %v, want %v", rec.args, wantArgs)
	}
}

func TestNextestAdapter_Classify_AllPassed(t *testing.T) {
	rec := &recordingExec{stdout: `{"type":"test","event":"ok","name":"foo::a"}` + "\n", exitCode: 0}
	a := &NextestAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::a"})
	if res.Outcome != OutcomeAllPassed {
		t.Errorf("Outcome = %v, want OutcomeAllPassed", res.Outcome)
	}
}

func TestNextestAdapter_Classify_AtLeastOneFailed(t *testing.T) {
	rec := &recordingExec{stdout: `{"type":"test","event":"failed","name":"foo::a"}` + "\n", exitCode: 100}
	a := &NextestAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::a"})
	if res.Outcome != OutcomeAtLeastOneFailed {
		t.Errorf("Outcome = %v, want OutcomeAtLeastOneFailed", res.Outcome)
	}
}

func TestNextestAdapter_Classify_BuildFailed(t *testing.T) {
	rec := &recordingExec{
		stdout:   "",
		stderr:   "error[E0425]: cannot find value `whoops`\nerror: could not compile `mycrate`\n",
		exitCode: 101,
	}
	a := &NextestAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::a"})
	if res.Outcome != OutcomeBuildFailed {
		t.Errorf("Outcome = %v, want OutcomeBuildFailed", res.Outcome)
	}
}

func TestNextestAdapter_IgnoredNotFailure(t *testing.T) {
	rec := &recordingExec{stdout: `{"type":"test","event":"ignored","name":"foo::a"}` + "\n", exitCode: 0}
	a := &NextestAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::a"})
	if res.Outcome != OutcomeAllPassed {
		t.Errorf("Outcome = %v, want OutcomeAllPassed (ignored not failure)", res.Outcome)
	}
}

func TestNextestAdapter_MissingBinary_Error(t *testing.T) {
	rec := &recordingExec{
		exitCode: -1,
		err:      &exec.Error{Name: "cargo-nextest", Err: exec.ErrNotFound},
	}
	a := &NextestAdapter{exec: rec.fn()}
	_, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::a"})
	if err == nil {
		t.Fatal("expected error on missing cargo-nextest")
	}
	msg := err.Error()
	for _, want := range []string{"cargo-nextest", "tdd.rust.runner"} {
		if !strings.Contains(msg, want) {
			t.Errorf("error message missing %q: %s", want, msg)
		}
	}
}

func TestNextestAdapter_GenericExecError_Propagates(t *testing.T) {
	rec := &recordingExec{err: errors.New("kaboom")}
	a := &NextestAdapter{exec: rec.fn()}
	_, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "foo::a"})
	if err == nil {
		t.Fatal("expected error to propagate")
	}
}
