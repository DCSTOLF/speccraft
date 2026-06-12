package runner

import (
	"context"
	"testing"
)

func TestPytestAdapter_BuildArgv_TargetsExactTest(t *testing.T) {
	rec := &recordingExec{stdout: "test_foo.py::test_new FAILED\n", exitCode: 1}
	a := &PytestAdapter{exec: rec.fn()}
	_, err := a.Run(context.Background(), Request{WorkDir: "/pkg", FullyQualifiedTestName: "test_new"})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	if rec.name != "pytest" {
		t.Errorf("argv[0] = %q, want pytest", rec.name)
	}
	wantArgs := []string{"-k", "test_new", "-v", "--no-header"}
	if !equalArgs(rec.args, wantArgs) {
		t.Errorf("args = %v, want %v", rec.args, wantArgs)
	}
}

func TestPytestAdapter_Classify_AllPassed(t *testing.T) {
	rec := &recordingExec{stdout: "test_foo.py::test_a PASSED [100%]\n", exitCode: 0}
	a := &PytestAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "test_a"})
	if res.Outcome != OutcomeAllPassed {
		t.Errorf("Outcome = %v, want OutcomeAllPassed", res.Outcome)
	}
	if len(res.Records) != 1 || res.Records[0].TestName != "test_a" || res.Records[0].Status != "passed" {
		t.Errorf("Records = %+v", res.Records)
	}
}

func TestPytestAdapter_Classify_AtLeastOneFailed(t *testing.T) {
	rec := &recordingExec{stdout: "tests/test_foo.py::TestK::test_new FAILED [100%]\n", exitCode: 1}
	a := &PytestAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "test_new"})
	if res.Outcome != OutcomeAtLeastOneFailed {
		t.Errorf("Outcome = %v, want OutcomeAtLeastOneFailed", res.Outcome)
	}
	// Record name is the last :: segment (the def name), to intersect with the
	// just-added set.
	if res.Records[0].TestName != "test_new" {
		t.Errorf("TestName = %q, want test_new", res.Records[0].TestName)
	}
}

func TestPytestAdapter_Classify_CollectionFailed(t *testing.T) {
	rec := &recordingExec{stdout: "", stderr: "ERROR collecting test_foo.py\nImportError\n", exitCode: 2}
	a := &PytestAdapter{exec: rec.fn()}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "test_a"})
	if res.Outcome != OutcomeBuildFailed {
		t.Errorf("Outcome = %v, want OutcomeBuildFailed (collection error)", res.Outcome)
	}
}

func TestPytestAdapter_ExecError_PropagatesError(t *testing.T) {
	rec := &recordingExec{err: context.DeadlineExceeded}
	a := &PytestAdapter{exec: rec.fn()}
	_, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "test_a"})
	if err == nil {
		t.Fatal("expected exec error to propagate")
	}
}

func TestPytestAdapter_HonorsConfiguredCommand(t *testing.T) {
	rec := &recordingExec{stdout: "t.py::test_a PASSED\n", exitCode: 0}
	a := &PytestAdapter{exec: rec.fn(), Command: "python -m pytest"}
	if _, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "test_a"}); err != nil {
		t.Fatal(err)
	}
	if rec.name != "python" || rec.args[0] != "-m" || rec.args[1] != "pytest" {
		t.Errorf("configured command not honored: name=%q args=%v", rec.name, rec.args)
	}
}
