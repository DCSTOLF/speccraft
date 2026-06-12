package runner

import (
	"context"
	"regexp"
	"strings"
)

// JSTSAdapter invokes the host-configured JS/TS test command (spec 0018
// `[tdd.javascript]` / `[tdd.typescript]` `command`) and parses TAP output to
// classify the outcome. JavaScript and TypeScript share this one adapter; the
// config key only selects the command line. The configured command is expected
// to emit TAP (e.g. `vitest run --reporter=tap`, `jest` with a TAP reporter) so
// per-test pass/fail names are observable — required by Decision D1's just-added
// intersection.
type JSTSAdapter struct {
	exec execFn
	// Command is the full configured command line (binary + flags). The
	// targeted test name is appended as the final argument.
	Command string
}

// tapLine matches a TAP result line, e.g.:
//
//	ok 1 - existing
//	not ok 1 - brandnew
var tapLine = regexp.MustCompile(`^(not ok|ok)\s+\d+\s*-?\s*(.*)$`)

func (j *JSTSAdapter) Run(ctx context.Context, req Request) (Result, error) {
	fields := strings.Fields(j.Command)
	if len(fields) == 0 {
		// No configured command: the factory should have refused to build this
		// adapter (fail-closed, D2). Defensive guard for direct callers.
		return Result{Stderr: "no JS/TS test command configured"}, nil
	}
	name := fields[0]
	args := append([]string{}, fields[1:]...)
	args = append(args, req.FullyQualifiedTestName)

	stdout, stderr, exitCode, err := j.execOrDefault()(ctx, name, args, req.WorkDir)
	if err != nil {
		return Result{Stderr: string(stderr)}, err
	}
	recs := parseTAP(string(stdout))
	return Result{
		Outcome: classifyOutcome(recs, exitCode),
		Records: recs,
		Stderr:  string(stderr),
	}, nil
}

func (j *JSTSAdapter) execOrDefault() execFn {
	if j.exec != nil {
		return j.exec
	}
	return execCmd
}

func parseTAP(stdout string) []TestRecord {
	var recs []TestRecord
	for _, line := range strings.Split(stdout, "\n") {
		m := tapLine.FindStringSubmatch(strings.TrimSpace(line))
		if m == nil {
			continue
		}
		status := "passed"
		if m[1] == "not ok" {
			status = "failed"
		}
		name := strings.TrimSpace(m[2])
		recs = append(recs, TestRecord{TestName: name, Status: status})
	}
	return recs
}
