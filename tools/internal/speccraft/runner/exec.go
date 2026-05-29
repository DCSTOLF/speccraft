package runner

import (
	"bytes"
	"context"
	"os/exec"
)

// execFn is the shape of a process runner the adapters depend on. Real
// adapters use execCmd; tests inject a fake to record argv and return
// canned stdout/stderr/exitcode without touching the real toolchain.
type execFn func(ctx context.Context, name string, args []string, workDir string) (stdout, stderr []byte, exitCode int, err error)

// ExecCmd is the exported production execFn (alias of the unexported
// execCmd used by the adapters internally). The speccraft-guard cmd
// passes this as its production exec injection.
func ExecCmd(ctx context.Context, name string, args []string, workDir string) ([]byte, []byte, int, error) {
	return execCmd(ctx, name, args, workDir)
}

// execCmd is the production execFn. Runs `name args...` in workDir,
// captures stdout and stderr, returns the exit code (0 on success,
// non-zero on failure). Returns a non-nil err only on exec failure
// (e.g. binary not found); a non-zero exit is reported via exitCode.
func execCmd(ctx context.Context, name string, args []string, workDir string) ([]byte, []byte, int, error) {
	cmd := exec.CommandContext(ctx, name, args...)
	if workDir != "" {
		cmd.Dir = workDir
	}
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	err := cmd.Run()
	if err == nil {
		return stdout.Bytes(), stderr.Bytes(), 0, nil
	}
	if ee, ok := err.(*exec.ExitError); ok {
		return stdout.Bytes(), stderr.Bytes(), ee.ExitCode(), nil
	}
	// Not a process exit error (e.g. command not found): report verbatim.
	return stdout.Bytes(), stderr.Bytes(), -1, err
}
