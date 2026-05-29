package runner

import (
	"context"
	"errors"
	"fmt"
	"os/exec"
)

// NextestAdapter invokes `cargo nextest run --message-format libtest-json
// -E 'test(=<fqtn>)'` and parses the JSONL event stream. Implementation
// per spec 0005 §What.3.
type NextestAdapter struct {
	exec      execFn
	CrateName string
}

// Run invokes cargo-nextest with a targeted single-test filter and classifies
// the outcome per spec §What.3 and AC #4. On a missing `cargo-nextest`
// binary, returns an error naming the binary and the config key that
// selected it (spec §What.1 missing-binary behavior).
func (n *NextestAdapter) Run(ctx context.Context, req Request) (Result, error) {
	args := []string{
		"nextest", "run",
		"--no-fail-fast",
		"--message-format", "libtest-json",
		"-E", fmt.Sprintf("test(=%s)", req.FullyQualifiedTestName),
	}
	stdout, stderr, exitCode, err := n.execOrDefault()(ctx, "cargo", args, req.WorkDir)
	if err != nil {
		if isMissingBinary(err) {
			return Result{Stderr: string(stderr)}, fmt.Errorf(
				"cargo-nextest not found on PATH (selected by [tdd.rust.runner] = \"nextest\"): %w",
				err,
			)
		}
		return Result{Stderr: string(stderr)}, err
	}
	recs := parseLibtestJSON(string(stdout), n.CrateName)
	return Result{
		Outcome: classifyOutcome(recs, exitCode),
		Records: recs,
		Stderr:  string(stderr),
	}, nil
}

func (n *NextestAdapter) execOrDefault() execFn {
	if n.exec != nil {
		return n.exec
	}
	return execCmd
}

// isMissingBinary returns true if err indicates the executable was not found
// on PATH. Wraps both `exec.ErrNotFound` direct returns and `*exec.Error`
// wrappers.
func isMissingBinary(err error) bool {
	if errors.Is(err, exec.ErrNotFound) {
		return true
	}
	var ee *exec.Error
	if errors.As(err, &ee) {
		return errors.Is(ee.Err, exec.ErrNotFound)
	}
	return false
}
