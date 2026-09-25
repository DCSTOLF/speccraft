package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

// Spec 0047 T1/T2 — `speccraft-state tasks-verify <tasks.md>` structural oracle.
//
// RED before implementation: the subcommand is unknown, so run() returns non-zero
// with nothing on stdout (the run()-seam contract → override budget 0, AC11).
//
// Contract pinned here:
//   - AC1 parent/child consistency fires on ALL files, contract key or not.
//   - §Grammar recognition is SYNTACTIC and resolution comes after: a valid
//     `T<digits>.<suffix>` bullet IS a sub-checkbox (an unresolvable parent is
//     exit 2), while a bullet that never matched the shape is prose at any depth.
//   - AC8 exit codes: 0 clean, 1 violations, 2 malformed.
//
// The archive shapes asserted here are real: specs/.archive/0016-.../tasks.md
// carries T1.1–T1.10 sub-checkboxes, a deeper `- [x] #1 …` prose level, **bold**
// task text, and both `id:` and `spec:` frontmatter keys.

// writeTasks writes a tasks.md into a temp repo and returns its path.
func writeTasks(t *testing.T, repo, body string) string {
	t.Helper()
	dir := filepath.Join(repo, "specs", "0099-fixture")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	p := filepath.Join(dir, "tasks.md")
	if err := os.WriteFile(p, []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	return p
}

const fmPlain = "---\nspec: \"0099\"\n---\n\n# Tasks\n\n"
const fmContract = "---\nspec: \"0099\"\ncontract: done-means-v1\n---\n\n# Tasks\n\n"

// --- T1: the subcommand exists at all -------------------------------------

func Test_StateCmd_TasksVerify_CleanFile_ExitZero(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+"- [x] T1 — did a thing\n- [ ] T2 — not yet\n")
	code, stdout, stderr := runCmd(t, repo, "tasks-verify", p)
	if code != 0 {
		t.Fatalf("clean file must exit 0; code=%d stderr=%s", code, stderr)
	}
	if strings.TrimSpace(stdout) != "" {
		t.Errorf("clean file ⇒ no findings; got %q", stdout)
	}
}

func Test_StateCmd_TasksVerify_MissingFile_ExitTwo(t *testing.T) {
	repo := makeRepo(t)
	code, _, _ := runCmd(t, repo, "tasks-verify", filepath.Join(repo, "nope.md"))
	if code != 2 {
		t.Fatalf("missing file must exit 2 (malformed); code=%d", code)
	}
}

// --- T2a: parent/child, with and without the contract key ------------------

func Test_StateCmd_TasksVerify_ParentChild_TickedParentUntickedChild(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+
		"- [x] T1 — seam plus tests\n"+
		"  - [x] T1.a — the seam\n"+
		"  - [ ] T1.b — the tests\n")
	code, stdout, stderr := runCmd(t, repo, "tasks-verify", p)
	if code != 1 {
		t.Fatalf("ticked parent with unticked child must exit 1; code=%d stderr=%s", code, stderr)
	}
	if !strings.Contains(stdout, "T1\t") {
		t.Errorf("finding must name the offending parent T1; got:\n%s", stdout)
	}
}

func Test_StateCmd_TasksVerify_ParentChild_HoldsWithoutContractKey(t *testing.T) {
	repo := makeRepo(t)
	// Identical to the above but explicitly asserting the no-contract-key path:
	// AC1 is unconditional.
	p := writeTasks(t, repo, fmPlain+
		"- [x] T7 — parent\n"+
		"  - [ ] T7.a — child\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 1 {
		t.Fatalf("AC1 must fire without the contract key; code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_ParentChild_UntickedParentUntickedChildIsClean(t *testing.T) {
	repo := makeRepo(t)
	// specs/.archive/0016-.../tasks.md T5 is exactly this shape; AC3 depends on
	// it staying clean.
	p := writeTasks(t, repo, fmPlain+
		"- [ ] T5 — close gate\n"+
		"  - [ ] T5.1 — stage files\n")
	if code, out, _ := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("unticked parent + unticked child is clean; code=%d out=%s", code, out)
	}
}

// --- T2b: grammar ----------------------------------------------------------

func Test_StateCmd_TasksVerify_Grammar_MultiDigitSuffix(t *testing.T) {
	repo := makeRepo(t)
	// T1.10 is a real shape in the archive. An alpha-only suffix rule (which both
	// reviewers proposed) would treat this as prose and miss the violation.
	p := writeTasks(t, repo, fmPlain+
		"- [x] T1 — parent\n"+
		"  - [ ] T1.10 — tenth child\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 1 {
		t.Fatalf("T1.10 must be recognized as a sub-checkbox; code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_Grammar_DeepBulletIsProse(t *testing.T) {
	repo := makeRepo(t)
	// The archive's second-level `- [x] #1 …` bullets never match the
	// sub-checkbox shape, so they are prose at any depth — including unticked.
	p := writeTasks(t, repo, fmPlain+
		"- [x] T1 — parent\n"+
		"  - [x] T1.3 — child\n"+
		"    - [ ] #1 `some literal` note\n")
	if code, out, _ := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("deep non-matching bullet is prose; code=%d out=%s", code, out)
	}
}

func Test_StateCmd_TasksVerify_Grammar_BoldTaskText(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+"- [x] T1 — **Author the oracle (RED)**\n")
	if code, _, stderr := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("bold task text must parse; code=%d stderr=%s", code, stderr)
	}
}

func Test_StateCmd_TasksVerify_Grammar_ExtraFrontmatterKeys(t *testing.T) {
	repo := makeRepo(t)
	// 0016 carries BOTH id: and spec:.
	p := writeTasks(t, repo, "---\nid: \"0016\"\nspec: \"0016\"\n---\n\n# Tasks\n\n- [x] T1 — a\n")
	if code, _, stderr := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("extra frontmatter keys must be tolerated; code=%d stderr=%s", code, stderr)
	}
}

func Test_StateCmd_TasksVerify_Grammar_DottedTaskIDAtColumnZero(t *testing.T) {
	// specs/.archive/0001-speccraft-v1/tasks.md uses dotted — and multi-dot —
	// task ids at COLUMN 0 (`T0.1`, `T0.5.1`). Those are tasks, not misplaced
	// sub-checkboxes: only INDENTATION makes a sub-checkbox.
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+
		"- [x] T0.1 — plugin.json\n"+
		"- [ ] T0.4 — verify plugin loads\n"+
		"- [x] T0.5.1 — devcontainer.json\n")
	if code, out, stderr := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("dotted column-0 ids are tasks; code=%d out=%s stderr=%s", code, out, stderr)
	}
}

func Test_StateCmd_TasksVerify_Grammar_SubCheckboxUnderDottedParent(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+
		"- [x] T0.5 — parent with a dotted id\n"+
		"  - [ ] T0.5.1 — child\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 1 {
		t.Fatalf("child of a dotted parent still triggers AC1; code=%d", code)
	}
}

// --- T2d: malformed --------------------------------------------------------

func Test_StateCmd_TasksVerify_Malformed_OrphanSubCheckbox(t *testing.T) {
	repo := makeRepo(t)
	// Syntactically a sub-checkbox, but T9 does not exist ⇒ exit 2, NOT prose.
	// This is the recognition/resolution split that resolved the round-2
	// grammar-vs-AC8 contradiction.
	p := writeTasks(t, repo, fmPlain+
		"- [x] T1 — parent\n"+
		"  - [x] T9.a — orphan\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 2 {
		t.Fatalf("orphan sub-checkbox must be malformed (exit 2); code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_Malformed_DuplicateTaskID(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+"- [x] T1 — first\n- [x] T1 — second\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 2 {
		t.Fatalf("duplicate task id must be malformed; code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_Malformed_MissingFrontmatter(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, "# Tasks\n\n- [x] T1 — a\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 2 {
		t.Fatalf("missing frontmatter must be malformed; code=%d", code)
	}
}
