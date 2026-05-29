package runner

import (
	"context"
)

// CargoAdapter invokes `cargo test --exact <fqtn>` and parses libtest text
// output. Implementation per spec 0005 §What.3.
type CargoAdapter struct {
	// exec runs a command and returns (stdout, stderr, exitCode, err).
	// In production, set to execCmd; tests inject a fake.
	exec      execFn
	CrateName string // optional crate prefix stripped from libtest names
}

// Run invokes cargo with a targeted single-test filter and classifies
// the outcome per spec §What.3 and AC #4.
func (c *CargoAdapter) Run(ctx context.Context, req Request) (Result, error) {
	args := []string{
		"test",
		"--no-fail-fast",
		"--quiet",
		"--",
		"--exact",
		req.FullyQualifiedTestName,
	}
	stdout, stderr, exitCode, err := c.execOrDefault()(ctx, "cargo", args, req.WorkDir)
	if err != nil {
		return Result{Stderr: string(stderr)}, err
	}
	recs := parseLibtestText(string(stdout), c.CrateName)
	return Result{
		Outcome: classifyOutcome(recs, exitCode),
		Records: recs,
		Stderr:  string(stderr),
	}, nil
}

func (c *CargoAdapter) execOrDefault() execFn {
	if c.exec != nil {
		return c.exec
	}
	return execCmd
}

// classifyOutcome implements the AC #4 priority rule shared by both adapters:
//
//   - any record with Status == "failed" → OutcomeAtLeastOneFailed
//   - else exit == 0                     → OutcomeAllPassed
//   - else (non-zero exit, no failed)    → OutcomeBuildFailed
//
// `ignored` records do not satisfy the accept branch (AC #4).
func classifyOutcome(recs []TestRecord, exitCode int) Outcome {
	for _, r := range recs {
		if r.Status == "failed" {
			return OutcomeAtLeastOneFailed
		}
	}
	if exitCode == 0 {
		return OutcomeAllPassed
	}
	return OutcomeBuildFailed
}
