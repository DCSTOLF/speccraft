//go:build !unix

package main

import (
	"fmt"
	"strings"
)

// Spec 0047 — non-unix counterpart to tasks_predicate.go.
//
// Predicate execution needs a process-GROUP kill (Setpgid + kill(-pgid)) so a
// forked grandchild holding the captured output pipe cannot outlive the timeout
// and hang the verifier. That is a POSIX mechanism, so `--run` cannot honour its
// bounded-termination contract off unix. Shipped platforms are linux and macOS.
//
// This file exists because ledger_flock_unix.go / ledger_flock_other.go is the
// precedent: a build-tag split ships BOTH halves. Shipping only the unix half
// broke `GOOS=windows go build ./...` with `undefined: runPredicates` — a
// cross-compile regression nothing caught until a test was added for it.
//
// It fails LOUD (one reported finding per predicate) rather than returning nil:
// a silent no-op would let `--run` report clean while verifying nothing, which
// is strictly worse than refusing.
func runPredicates(doc tasksDoc) []tasksFinding {
	var out []tasksFinding
	for _, t := range doc.tasks {
		if !t.ticked {
			continue
		}
		// Deliberately inlined rather than calling the unix file's
		// predicateCommand: keeping the two tagged files free of cross-references
		// means neither half can break the other's build.
		if !strings.HasPrefix(t.done, "$") {
			continue
		}
		out = append(out, tasksFinding{
			id:     t.id,
			kind:   "predicate-unsupported",
			detail: fmt.Sprintf("--run needs a POSIX process-group kill; unavailable on this platform (task %s)", t.id),
		})
	}
	return out
}
