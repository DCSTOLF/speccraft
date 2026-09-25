package main

import (
	"fmt"
	"io"
	"os"
	"regexp"
	"strings"

	"github.com/dcstolf/speccraft/tools/internal/speccraft"
)

// Spec 0047 — `speccraft-state tasks-verify <tasks.md> [--run]`.
//
// A read-only oracle over tasks.md. Its OWN logic writes nothing; a `done: $ …`
// predicate is arbitrary shell and may have side effects (see §Boundary).
//
// Exit codes (AC8): 0 clean, 1 violations found, 2 malformed input. The split is
// load-bearing for the close runbook: 2 is a bug to hand-fix, 1 is a decision.
//
// Recognition is SYNTACTIC and resolution comes after (§Grammar). That split is
// what keeps "sub-checkbox with an unresolvable parent" (malformed, exit 2)
// distinct from "an indented bullet that was never a sub-checkbox" (prose,
// ignored at any depth) — the latter is how specs/.archive/0016-.../tasks.md,
// with its `- [x] #1 …` second level, stays clean.

const tasksContractV1 = "done-means-v1"

// bomPrefix is a UTF-8 BOM written as an escape (a literal BOM in source is a
// Go syntax error).
const bomPrefix = "\uFEFF"

// A task line lives at column 0. Bold may wrap the whole text, so `**` is
// tolerated before the id (spec 0016 writes `- [x] **T1 — …**`).
//
// A task id may itself be dotted, including multi-dot: spec 0001 uses `T0.1` and
// `T0.5.1` at column 0. INDENTATION alone makes a sub-checkbox — a dot in a
// column-0 id does not.
var reTaskLine = regexp.MustCompile(`^- \[([ xX])\] *(?:\*\*)? *(T[0-9]+(?:\.[A-Za-z0-9]+)*)\b`)

// A sub-checkbox is an INDENTED checkbox whose id is its parent's id plus one
// more dotted segment. The suffix charset is [A-Za-z0-9]+ because the archive
// already uses multi-digit numerics (T1.10) — an alpha-only rule would misread
// real files.
var reSubLine = regexp.MustCompile(`^(\s+)- \[([ xX])\] *(?:\*\*)? *(T[0-9]+(?:\.[A-Za-z0-9]+)*)\b`)

// parentOfSubID returns the id a sub-checkbox claims as its parent (its id minus
// the final dotted segment) and whether the id was dotted at all.
func parentOfSubID(id string) (string, bool) {
	i := strings.LastIndex(id, ".")
	if i < 0 {
		return "", false
	}
	return id[:i], true
}

// `done:` sits at exactly two spaces of indent (§Grammar pins this so
// implementations cannot diverge on 2-vs-4).
var reDoneLine = regexp.MustCompile(`^( *)done:(.*)$`)

var reHeading = regexp.MustCompile(`^#{1,6} `)

type tasksSub struct {
	id     string
	ticked bool
}

type tasksTask struct {
	id     string
	ticked bool
	subs   []tasksSub
	done   string // raw value after `done:`, trimmed
	nDone  int
}

type tasksDoc struct {
	contract bool
	tasks    []tasksTask
}

type tasksFinding struct {
	id     string
	kind   string
	detail string
}

// malformedErr marks input the parser refuses (exit 2) as opposed to a
// well-formed file that merely violates a rule (exit 1).
type malformedErr struct{ msg string }

func (e malformedErr) Error() string { return e.msg }

// hasFrontmatterFence reports whether the document opens a frontmatter block.
// This is a FENCE check only — the key grammar itself is never re-implemented
// here; `contract:` is read through speccraft.ReadFrontmatterField, which routes
// through the single shared parseFrontmatterBlock (AC12).
func hasFrontmatterFence(b []byte) bool {
	s := strings.TrimPrefix(string(b), bomPrefix)
	if !strings.HasPrefix(s, "---\n") && !strings.HasPrefix(s, "---\r\n") {
		return false
	}
	rest := s[strings.Index(s, "\n")+1:]
	for _, line := range strings.Split(rest, "\n") {
		if strings.TrimRight(line, "\r") == "---" {
			return true
		}
	}
	return false
}

// parseTasksFile is the single tasks.md grammar entrypoint for this command.
func parseTasksFile(path string) (tasksDoc, error) {
	var doc tasksDoc
	b, err := os.ReadFile(path)
	if err != nil {
		return doc, malformedErr{fmt.Sprintf("tasks-verify: cannot read %s: %v", path, err)}
	}
	if !hasFrontmatterFence(b) {
		return doc, malformedErr{fmt.Sprintf("tasks-verify: %s has no frontmatter block", path)}
	}
	if v, found, err := speccraft.ReadFrontmatterField(path, "contract"); err == nil && found {
		doc.contract = strings.TrimSpace(v) == tasksContractV1
	}

	seen := map[string]bool{}
	cur := -1 // index into doc.tasks of the currently open parent
	for n, raw := range strings.Split(strings.TrimPrefix(string(b), bomPrefix), "\n") {
		line := strings.TrimRight(raw, "\r")
		ln := n + 1

		if reHeading.MatchString(line) {
			cur = -1 // a heading closes the open task block
			continue
		}

		if m := reTaskLine.FindStringSubmatch(line); m != nil {
			if seen[m[2]] {
				return doc, malformedErr{fmt.Sprintf("tasks-verify: %s:%d duplicate task id %s", path, ln, m[2])}
			}
			seen[m[2]] = true
			doc.tasks = append(doc.tasks, tasksTask{id: m[2], ticked: m[1] != " "})
			cur = len(doc.tasks) - 1
			continue
		}

		if m := reSubLine.FindStringSubmatch(line); m != nil {
			if parent, dotted := parentOfSubID(m[3]); dotted {
				// Syntactically a sub-checkbox. Resolution happens now: it must
				// name the enclosing task, else the file is malformed — an
				// unresolvable sub-checkbox is an error, never silent prose.
				if cur < 0 || doc.tasks[cur].id != parent {
					return doc, malformedErr{fmt.Sprintf("tasks-verify: %s:%d sub-checkbox %s names no enclosing task", path, ln, m[3])}
				}
				doc.tasks[cur].subs = append(doc.tasks[cur].subs, tasksSub{id: m[3], ticked: m[2] != " "})
				continue
			}
			// An indented, undotted checkbox is prose.
			continue
		}

		if m := reDoneLine.FindStringSubmatch(line); m != nil && len(m[1]) == 2 {
			if cur < 0 {
				return doc, malformedErr{fmt.Sprintf("tasks-verify: %s:%d done: line belongs to no task", path, ln)}
			}
			val := strings.TrimSpace(m[2])
			if val == "" {
				return doc, malformedErr{fmt.Sprintf("tasks-verify: %s:%d empty done: value for %s", path, ln, doc.tasks[cur].id)}
			}
			// A bare `$` marker is non-empty but names no command. Left alone it
			// would fall through to prose and be silently waived — a ticked task
			// that LOOKS executable, never run, never reported. That is this
			// tool's own failure mode, so it is malformed.
			if strings.TrimSpace(strings.TrimPrefix(val, "$")) == "" && strings.HasPrefix(val, "$") {
				return doc, malformedErr{fmt.Sprintf("tasks-verify: %s:%d done: $ with no command for %s", path, ln, doc.tasks[cur].id)}
			}
			doc.tasks[cur].nDone++
			if doc.tasks[cur].nDone > 1 {
				return doc, malformedErr{fmt.Sprintf("tasks-verify: %s:%d duplicate done: line for %s", path, ln, doc.tasks[cur].id)}
			}
			doc.tasks[cur].done = val
			continue
		}
		// Anything else — including an indented bullet that never matched the
		// sub-checkbox shape — is prose and is ignored, at any depth.
	}
	return doc, nil
}

// checkTasks applies the structural rules and returns findings in file order.
func checkTasks(doc tasksDoc) []tasksFinding {
	var out []tasksFinding
	for _, t := range doc.tasks {
		// AC1 — unconditional, contract key or not. This is the check that
		// catches "ticked when only the most visible part was finished".
		if t.ticked {
			for _, s := range t.subs {
				if !s.ticked {
					out = append(out, tasksFinding{t.id, "parent-child",
						fmt.Sprintf("task is [x] but sub-checkbox %s is [ ]", s.id)})
				}
			}
		}
		// AC2 — only under the contract, and for EVERY task regardless of tick
		// state, so an omission surfaces at plan time rather than after the fact.
		if doc.contract && t.nDone == 0 {
			out = append(out, tasksFinding{t.id, "missing-done", "no done: line under contract " + tasksContractV1})
		}
	}
	return out
}

// escapeField keeps TSV field boundaries intact (AC7).
var tasksFieldEscaper = strings.NewReplacer("\\", `\\`, "\t", `\t`, "\n", `\n`, "\r", `\r`)

func escapeField(s string) string { return tasksFieldEscaper.Replace(s) }

// tasksVerifyUsage prints usage plus the two boundaries AC14 requires: prose
// `done:` lines are never verified, and predicates may have side effects even
// though tasks-verify's own logic does not. Single source for both the
// no-argument path and `--help`, so the boundary cannot drift between them.
func tasksVerifyUsage(w io.Writer) {
	fmt.Fprintln(w, "usage: speccraft-state tasks-verify <tasks.md> [--run]")
	fmt.Fprintln(w, "  Structure is always checked. With --run, `done: $ <cmd>` predicates for")
	fmt.Fprintln(w, "  TICKED tasks are executed. A PROSE done: line is articulation only and is")
	fmt.Fprintln(w, "  never verified — this tool cannot evaluate prose.")
	fmt.Fprintln(w, "  tasks-verify's own logic writes nothing, but a predicate is arbitrary")
	fmt.Fprintln(w, "  shell and MAY have side effects.")
	fmt.Fprintln(w, "  Exit: 0 clean, 1 violations, 2 malformed input.")
}

// tasksVerify implements the subcommand. It never writes a file.
func tasksVerify(path string, doRun bool, stdout, stderr io.Writer) int {
	doc, err := parseTasksFile(path)
	if err != nil {
		fmt.Fprintln(stderr, err)
		return 2
	}
	findings := checkTasks(doc)
	if doRun {
		findings = append(findings, runPredicates(doc)...)
	}
	for _, f := range findings {
		fmt.Fprintf(stdout, "%s\t%s\t%s\n", escapeField(f.id), escapeField(f.kind), escapeField(f.detail))
	}
	if len(findings) > 0 {
		return 1
	}
	return 0
}
