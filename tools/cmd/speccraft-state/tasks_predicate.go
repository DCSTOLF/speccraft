//go:build unix

package main

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// Spec 0047 §Predicate execution — the `done: $ <cmd>` runner.
//
// Contract (mirrors the spec-0045 SPECCRAFT_LEDGER_LOCK_TIMEOUT precedent):
//   - shell   : /bin/sh -c, absolute path, POSIX only (no bashisms)
//   - CWD     : the repo root, so a predicate behaves the same from any subdir
//   - env     : inherited unmodified
//   - streams : stdin /dev/null; stdout+stderr combined, captured, 4 KiB cap
//   - timeout : SPECCRAFT_TASKS_VERIFY_TIMEOUT (Go duration), default 30s;
//     unset/empty/invalid/zero/negative all fall back to the default
//   - kill    : the whole PROCESS GROUP, not just the sh leader. Killing only the
//     leader leaves grandchildren holding the captured pipe open, which hangs the
//     verifier forever on exactly the runaway predicate the timeout exists to
//     bound.

const (
	tasksVerifyTimeoutEnv     = "SPECCRAFT_TASKS_VERIFY_TIMEOUT"
	tasksVerifyDefaultTimeout = 30 * time.Second
	tasksVerifyDetailCap      = 4 << 10 // 4 KiB
	tasksVerifyTruncMarker    = "…[truncated]"
)

// tasksVerifyTimeout resolves the predicate timeout. Any unusable value —
// unset, empty, unparseable, zero, or negative — yields the default.
func tasksVerifyTimeout(raw string) time.Duration {
	d, err := time.ParseDuration(strings.TrimSpace(raw))
	if err != nil || d <= 0 {
		return tasksVerifyDefaultTimeout
	}
	return d
}

// capDetail bounds captured output so a chatty predicate cannot blow up the
// findings stream (AC7).
func capDetail(s string) string {
	if len(s) <= tasksVerifyDetailCap {
		return s
	}
	return s[:tasksVerifyDetailCap] + tasksVerifyTruncMarker
}

// predicateCommand reports the shell command for a `done:` value, and whether
// the value is an executable predicate at all. A value not starting with `$` is
// prose: articulation only, never verified.
func predicateCommand(done string) (string, bool) {
	if !strings.HasPrefix(done, "$") {
		return "", false
	}
	cmd := strings.TrimSpace(strings.TrimPrefix(done, "$"))
	if cmd == "" {
		return "", false
	}
	return cmd, true
}

// runPredicate executes one predicate and returns combined output and error.
func runPredicate(command, dir string, timeout time.Duration) (string, error) {
	cmd := exec.Command("/bin/sh", "-c", command)
	cmd.Dir = dir
	// Own process group so the timeout can signal the whole tree.
	cmd.SysProcAttr = &syscall.SysProcAttr{Setpgid: true}

	var buf bytes.Buffer
	cmd.Stdout = &buf
	cmd.Stderr = &buf
	cmd.Stdin = nil // /dev/null

	if err := cmd.Start(); err != nil {
		return "", err
	}
	pgid := cmd.Process.Pid // == pgid because of Setpgid

	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()

	select {
	case err := <-done:
		return buf.String(), err
	case <-time.After(timeout):
		// Negative pid targets the whole group, so a forked grandchild holding
		// the output pipe dies too and Wait can return.
		_ = syscall.Kill(-pgid, syscall.SIGKILL)
		<-done
		return buf.String(), fmt.Errorf("timed out after %s", timeout)
	}
}

// runPredicates runs the executable predicates of TICKED tasks (AC4/AC5).
// Unticked tasks are skipped: a plan whose later steps legitimately fail today
// must not fail verification.
func runPredicates(doc tasksDoc) []tasksFinding {
	var out []tasksFinding
	root, err := speccraft.FindRoot("")
	if err != nil {
		root = "."
	}
	timeout := tasksVerifyTimeout(os.Getenv(tasksVerifyTimeoutEnv))

	for _, t := range doc.tasks {
		if !t.ticked {
			continue
		}
		command, ok := predicateCommand(t.done)
		if !ok {
			continue
		}
		output, err := runPredicate(command, root, timeout)
		if err != nil {
			out = append(out, tasksFinding{
				id:     t.id,
				kind:   "predicate-failed",
				detail: capDetail(fmt.Sprintf("$ %s: %v: %s", command, err, strings.TrimSpace(output))),
			})
		}
	}
	return out
}
