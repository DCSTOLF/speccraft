package runner

import (
	"context"
	"testing"
)

func TestGoAdapter_BuildArgv_TargetsExactTest(t *testing.T) {
	rec := &recordingExec{stdout: "=== RUN   TestFoo\n--- FAIL: TestFoo (0.00s)\nFAIL\n", exitCode: 1}
	a := &GoAdapter{exec: rec.fn()}
	_, err := a.Run(context.Background(), Request{WorkDir: "/pkg", FullyQualifiedTestName: "TestFoo"})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if rec.name != "go" {
		t.Errorf("argv[0] = %q, want go", rec.name)
	}
	wantArgs := []string{"test", "-run", "^TestFoo$", "-v", "."}
	if !equalArgs(rec.args, wantArgs) {
		t.Errorf("args = %v, want %v", rec.args, wantArgs)
	}
	if rec.workDir != "/pkg" {
		t.Errorf("workDir = %q, want /pkg", rec.workDir)
	}
}

func TestGoAdapter_Classify_AllPassed(t *testing.T) {
	rec := &recordingExec{stdout: "=== RUN   TestFoo\n--- PASS: TestFoo (0.00s)\nPASS\nok  \tpkg\t0.01s\n", exitCode: 0}
	a := &GoAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "TestFoo"})
	if res.Outcome != OutcomeAllPassed {
		t.Errorf("Outcome = %v, want OutcomeAllPassed", res.Outcome)
	}
	if len(res.Records) != 1 || res.Records[0].TestName != "TestFoo" || res.Records[0].Status != "passed" {
		t.Errorf("Records = %+v", res.Records)
	}
}

func TestGoAdapter_Classify_AtLeastOneFailed(t *testing.T) {
	rec := &recordingExec{stdout: "=== RUN   TestFoo\n--- FAIL: TestFoo (0.00s)\nFAIL\n", exitCode: 1}
	a := &GoAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "TestFoo"})
	if res.Outcome != OutcomeAtLeastOneFailed {
		t.Errorf("Outcome = %v, want OutcomeAtLeastOneFailed", res.Outcome)
	}
	if res.Records[0].Status != "failed" {
		t.Errorf("status = %q, want failed", res.Records[0].Status)
	}
}

func TestGoAdapter_Classify_BuildFailed(t *testing.T) {
	rec := &recordingExec{stdout: "", stderr: "./foo.go:3:1: syntax error\nFAIL\tpkg [build failed]\n", exitCode: 1}
	a := &GoAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "TestFoo"})
	if res.Outcome != OutcomeBuildFailed {
		t.Errorf("Outcome = %v, want OutcomeBuildFailed", res.Outcome)
	}
}

func TestGoAdapter_ExecError_PropagatesError(t *testing.T) {
	rec := &recordingExec{err: context.DeadlineExceeded}
	a := &GoAdapter{exec: rec.fn()}
	_, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "TestFoo"})
	if err == nil {
		t.Fatal("expected exec error (timeout surrogate) to propagate")
	}
}

func TestGoAdapter_HonorsConfiguredCommand(t *testing.T) {
	rec := &recordingExec{stdout: "--- FAIL: TestFoo (0.00s)\n", exitCode: 1}
	a := &GoAdapter{exec: rec.fn(), Command: "gotestsum --"}
	if _, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "TestFoo"}); err != nil {
		t.Fatal(err)
	}
	if rec.name != "gotestsum" {
		t.Errorf("argv[0] = %q, want gotestsum (configured command honored)", rec.name)
	}
	if rec.args[0] != "--" {
		t.Errorf("configured base args dropped: %v", rec.args)
	}
}
