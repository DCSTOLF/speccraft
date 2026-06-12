package runner

import (
	"context"
	"regexp"
	"strings"
)

// GoAdapter invokes `go test -run ^<name>$ -v .` in the target package
// directory and parses the verbose per-test result lines. Spec 0018: the Go
// red-check runner, mirroring CargoAdapter's shape. The -run filter is anchored
// (^…$) so it cannot accidentally match a longer test name (e.g. TestFoo vs
// TestFooBar).
type GoAdapter struct {
	exec execFn
	// Command is the configured base command line ([tdd.go] command);
	// defaults to "go test". The targeted -run/-v/. flags are appended.
	Command string
}

// goResultLine matches a verbose go-test result line:
//
//	--- PASS: TestFoo (0.00s)
//	--- FAIL: TestFoo (0.00s)
//	--- SKIP: TestFoo (0.00s)
var goResultLine = regexp.MustCompile(`^\s*--- (PASS|FAIL|SKIP): (\S+)`)

func (g *GoAdapter) Run(ctx context.Context, req Request) (Result, error) {
	name, base := splitCommand(g.Command, "go test")
	args := append(base, "-run", "^"+req.FullyQualifiedTestName+"$", "-v", ".")
	stdout, stderr, exitCode, err := g.execOrDefault()(ctx, name, args, req.WorkDir)
	if err != nil {
		return Result{Stderr: string(stderr)}, err
	}
	recs := parseGoTestText(string(stdout))
	return Result{
		Outcome: classifyOutcome(recs, exitCode),
		Records: recs,
		Stderr:  string(stderr),
	}, nil
}

func (g *GoAdapter) execOrDefault() execFn {
	if g.exec != nil {
		return g.exec
	}
	return execCmd
}

func parseGoTestText(stdout string) []TestRecord {
	var recs []TestRecord
	for _, line := range strings.Split(stdout, "\n") {
		m := goResultLine.FindStringSubmatch(line)
		if m == nil {
			continue
		}
		var status string
		switch m[1] {
		case "PASS":
			status = "passed"
		case "FAIL":
			status = "failed"
		case "SKIP":
			status = "ignored"
		}
		recs = append(recs, TestRecord{TestName: m[2], Status: status})
	}
	return recs
}
