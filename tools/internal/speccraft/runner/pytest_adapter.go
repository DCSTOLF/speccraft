package runner

import (
	"context"
	"regexp"
	"strings"
)

// PytestAdapter invokes `pytest -k <name> -v --no-header` and parses the
// verbose per-test result lines. Spec 0018: the Python red-check runner. A
// collection/import error (no PASSED/FAILED lines, non-zero exit) classifies as
// OutcomeBuildFailed — not a valid RED state (AC6).
type PytestAdapter struct {
	exec execFn
	// Command is the configured base command line ([tdd.python] command);
	// defaults to "pytest". The targeted -k/-v flags are appended.
	Command string
}

// pytestResultLine matches a verbose pytest result line, e.g.:
//
//	tests/test_foo.py::TestK::test_new FAILED [100%]
//	test_foo.py::test_a PASSED
var pytestResultLine = regexp.MustCompile(`^(\S+)\s+(PASSED|FAILED|SKIPPED)\b`)

func (p *PytestAdapter) Run(ctx context.Context, req Request) (Result, error) {
	name, base := splitCommand(p.Command, "pytest")
	args := append(base, "-k", req.FullyQualifiedTestName, "-v", "--no-header")
	stdout, stderr, exitCode, err := p.execOrDefault()(ctx, name, args, req.WorkDir)
	if err != nil {
		return Result{Stderr: string(stderr)}, err
	}
	recs := parsePytestText(string(stdout))
	return Result{
		Outcome: classifyOutcome(recs, exitCode),
		Records: recs,
		Stderr:  string(stderr),
	}, nil
}

func (p *PytestAdapter) execOrDefault() execFn {
	if p.exec != nil {
		return p.exec
	}
	return execCmd
}

func parsePytestText(stdout string) []TestRecord {
	var recs []TestRecord
	for _, line := range strings.Split(stdout, "\n") {
		m := pytestResultLine.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		// nodeid is path::[Class::]func — the just-added set is keyed on the
		// def name, so reduce to the last :: segment.
		name := m[1]
		if idx := strings.LastIndex(name, "::"); idx >= 0 {
			name = name[idx+2:]
		}
		var status string
		switch m[2] {
		case "PASSED":
			status = "passed"
		case "FAILED":
			status = "failed"
		case "SKIPPED":
			status = "ignored"
		}
		recs = append(recs, TestRecord{TestName: name, Status: status})
	}
	return recs
}
