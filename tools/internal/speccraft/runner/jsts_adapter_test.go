package runner

import (
	"context"
	"strings"
	"testing"
)

func TestJSTSAdapter_CommandFromConfig_BuildsArgv(t *testing.T) {
	rec := &recordingExec{stdout: "ok 1 - x\n", exitCode: 0}
	a := &JSTSAdapter{exec: rec.fn(), Command: "vitest run --reporter=tap"}
	_, err := a.Run(context.Background(), Request{WorkDir: "/app", FullyQualifiedTestName: "x"})
	if err != nil {
		t.Fatalf("Run: %v", err)
	}
	// The configured command's first token is the binary; the rest are args,
	// followed by the targeted test-name filter.
	if rec.name != "vitest" {
		t.Errorf("argv[0] = %q, want vitest", rec.name)
	}
	joined := strings.Join(rec.args, " ")
	if !strings.Contains(joined, "run --reporter=tap") {
		t.Errorf("args missing configured flags: %v", rec.args)
	}
	if !strings.Contains(joined, "x") {
		t.Errorf("args missing test-name filter: %v", rec.args)
	}
	if rec.workDir != "/app" {
		t.Errorf("workDir = %q, want /app", rec.workDir)
	}
}

func TestJSTSAdapter_Classify_AllPassed(t *testing.T) {
	rec := &recordingExec{stdout: "TAP version 13\n1..1\nok 1 - existing\n", exitCode: 0}
	a := &JSTSAdapter{exec: rec.fn(), Command: "vitest run --reporter=tap"}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "existing"})
	if res.Outcome != OutcomeAllPassed {
		t.Errorf("Outcome = %v, want OutcomeAllPassed", res.Outcome)
	}
	if len(res.Records) != 1 || res.Records[0].TestName != "existing" || res.Records[0].Status != "passed" {
		t.Errorf("Records = %+v", res.Records)
	}
}

func TestJSTSAdapter_Classify_AtLeastOneFailed(t *testing.T) {
	rec := &recordingExec{stdout: "1..1\nnot ok 1 - brandnew\n", exitCode: 1}
	a := &JSTSAdapter{exec: rec.fn(), Command: "vitest run --reporter=tap"}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "brandnew"})
	if res.Outcome != OutcomeAtLeastOneFailed {
		t.Errorf("Outcome = %v, want OutcomeAtLeastOneFailed", res.Outcome)
	}
	if res.Records[0].TestName != "brandnew" || res.Records[0].Status != "failed" {
		t.Errorf("Records = %+v", res.Records)
	}
}

func TestJSTSAdapter_Classify_BuildFailed(t *testing.T) {
	rec := &recordingExec{stdout: "", stderr: "SyntaxError: Unexpected token\n", exitCode: 1}
	a := &JSTSAdapter{exec: rec.fn(), Command: "vitest run --reporter=tap"}
	res, _ := a.Run(context.Background(), Request{FullyQualifiedTestName: "x"})
	if res.Outcome != OutcomeBuildFailed {
		t.Errorf("Outcome = %v, want OutcomeBuildFailed", res.Outcome)
	}
}

func TestJSTSAdapter_ExecError_PropagatesError(t *testing.T) {
	rec := &recordingExec{err: context.DeadlineExceeded}
	a := &JSTSAdapter{exec: rec.fn(), Command: "vitest run --reporter=tap"}
	_, err := a.Run(context.Background(), Request{FullyQualifiedTestName: "x"})
	if err == nil {
		t.Fatal("expected exec error to propagate")
	}
}
