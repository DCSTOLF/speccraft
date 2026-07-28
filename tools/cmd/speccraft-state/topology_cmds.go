package main

import (
	"fmt"
	"io"
	"os"
	"path/filepath"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// listMembers implements `speccraft-state list-members` (spec 0037 AC3): resolve
// the workspace root, read workspace.yml, and print one line per member as
// `<present|missing>\t<path>` to stdout; a missing member also warns on stderr.
// Absent or malformed manifest → non-zero with a clear stderr message.
func listMembers(stdout, stderr io.Writer) int {
	root, err := speccraft.FindWorkspaceRoot("")
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	yml := filepath.Join(root, "workspace.yml")
	if _, statErr := os.Stat(yml); statErr != nil {
		fmt.Fprintf(stderr, "no workspace.yml at workspace root %s\n", root)
		return 1
	}
	members, perr := speccraft.ParseWorkspaceMembers(yml)
	if perr != nil {
		fmt.Fprintf(stderr, "malformed workspace.yml: %v\n", perr)
		return 1
	}
	for _, m := range members {
		state := "present"
		if !m.Present {
			state = "missing"
			fmt.Fprintf(stderr, "missing member %s\n", m.Path)
		}
		fmt.Fprintf(stdout, "%s\t%s\n", state, m.Path)
	}
	return 0
}

// getStatus implements `speccraft-state get-status <spec-ref>` (spec 0037 AC4):
// resolve the NNNN-slug ref to specs/<ref>/spec.md, else specs/.archive/<ref>/
// spec.md (live wins), read status via ReadFrontmatterField, and print the bare
// value + newline. Not found / no status field → non-zero, nothing on stdout.
// resolveOutcome distinguishes the three spec-resolution results so both
// get-status (which prints distinct messages) and reconcile (which collapses
// everything but "resolved" to found==false) can share one resolver.
type resolveOutcome int

const (
	resolveResolved resolveOutcome = iota
	resolveNotFound
	resolveNoStatus
	resolveReadErr
)

// resolveSpecStatus resolves a spec-ref to its frontmatter status via the dual
// specs/<ref> → specs/.archive/<ref> lookup (live wins), returning the resolved
// spec.md path and outcome. Shared by get-status and reconcile (spec 0038).
func resolveSpecStatus(root, ref string) (status, specMd string, outcome resolveOutcome, err error) {
	live := filepath.Join(root, "specs", ref, "spec.md")
	archived := filepath.Join(root, "specs", ".archive", ref, "spec.md")
	switch {
	case fileExists(live):
		specMd = live // live wins
	case fileExists(archived):
		specMd = archived
	default:
		return "", "", resolveNotFound, nil
	}
	v, ok, rerr := speccraft.ReadFrontmatterField(specMd, "status")
	if rerr != nil {
		return "", specMd, resolveReadErr, rerr
	}
	if !ok {
		return "", specMd, resolveNoStatus, nil
	}
	return v, specMd, resolveResolved, nil
}

func getStatus(ref string, stdout, stderr io.Writer) int {
	root, err := speccraft.FindRoot("")
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	v, specMd, outcome, rerr := resolveSpecStatus(root, ref)
	switch outcome {
	case resolveNotFound:
		fmt.Fprintf(stderr, "spec %q not found in specs/ or specs/.archive/\n", ref)
		return 1
	case resolveReadErr:
		fmt.Fprintln(stderr, rerr)
		return 1
	case resolveNoStatus:
		fmt.Fprintf(stderr, "no status field in %s\n", specMd)
		return 1
	}
	fmt.Fprintln(stdout, v)
	return 0
}

// getFrontmatter implements `speccraft-state get-frontmatter <spec.md> <key>`
// (spec 0037 AC6): print the frontmatter value + newline (an absent key yields
// an empty line and exit 0 — it never errors on the key; only an unreadable
// file is an error). No referent resolution (that is Spec B).
func getFrontmatter(specMd, key string, stdout, stderr io.Writer) int {
	v, _, err := speccraft.ReadFrontmatterField(specMd, key)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 1
	}
	fmt.Fprintln(stdout, v)
	return 0
}

func fileExists(p string) bool {
	_, err := os.Stat(p)
	return err == nil
}
