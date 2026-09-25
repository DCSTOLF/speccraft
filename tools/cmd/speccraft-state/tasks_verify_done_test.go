//go:build unix

// Tagged unix because the predicate-execution assertions below reach into
// tasks_predicate.go's unix-only symbols (capDetail, tasksVerifyTimeout, …).
// The shipped platforms are linux and macOS; the GOOSWindows test here asserts
// that the non-unix half still BUILDS, which is what actually regressed.

package main

import (
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

// Spec 0047 T4/T6/T8 — `done:` semantics, exit-code taxonomy, TSV encoding, and
// predicate execution.
//
// HONESTY NOTE (recorded as plan correction C4; C2 is the cause): the T4/T6/T8
// assertions below are PINS, not REDs. The
// TDD guard wedged mid-implementation (a forward reference broke the build, and
// the guard then refused the very edit that would fix it), and recovering forced
// the `done:` parser and the predicate runner to land ahead of their tests. These
// assertions were therefore written against existing code and passed on first
// run. They pin the contract against regression; they did not drive it. The
// structural layer (tasks_verify_cmd_test.go) WAS a genuine RED.

// --- T4: done: presence, emptiness, duplication, boundary, indent ----------

func Test_StateCmd_TasksVerify_Contract_MissingDoneIsViolation(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a thing\n")
	code, stdout, _ := runCmd(t, repo, "tasks-verify", p)
	if code != 1 {
		t.Fatalf("contract file with no done: must exit 1; code=%d", code)
	}
	if !strings.Contains(stdout, "missing-done") {
		t.Errorf("finding kind must be missing-done; got:\n%s", stdout)
	}
}

func Test_StateCmd_TasksVerify_Contract_MissingDoneOnUntickedTaskAlsoFires(t *testing.T) {
	repo := makeRepo(t)
	// AC2: EVERY task, regardless of tick state, so the omission surfaces at plan
	// time rather than after completion.
	p := writeTasks(t, repo, fmContract+"- [ ] T1 — not started\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 1 {
		t.Fatalf("unticked task under contract still needs done:; code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_NoContractKey_MissingDoneIsNotReported(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+"- [x] T1 — a thing\n")
	if code, stdout, _ := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("no contract key ⇒ missing done: is not a violation; code=%d out=%s", code, stdout)
	}
}

func Test_StateCmd_TasksVerify_EmptyDoneIsMalformed(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a thing\n  done:\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 2 {
		t.Fatalf("empty done: must be malformed; code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_DuplicateDoneIsMalformed(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a thing\n  done: one\n  done: two\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 2 {
		t.Fatalf("duplicate done: must be malformed; code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_DoneBlockEndsAtNextTask(t *testing.T) {
	repo := makeRepo(t)
	// Two tasks each with their own done: — the block boundary is the next
	// column-0 task line, so this is NOT a duplicate.
	p := writeTasks(t, repo, fmContract+
		"- [x] T1 — a\n  done: prose one\n"+
		"- [x] T2 — b\n  done: prose two\n")
	if code, out, _ := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("per-task done: must not read as duplicate; code=%d out=%s", code, out)
	}
}

func Test_StateCmd_TasksVerify_DoneIndentIsTwoSpaces(t *testing.T) {
	repo := makeRepo(t)
	// A four-space `done:` is not a done: line, so AC2 fires under the contract.
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a\n    done: wrong indent\n")
	if code, stdout, _ := runCmd(t, repo, "tasks-verify", p); code != 1 || !strings.Contains(stdout, "missing-done") {
		t.Fatalf("4-space done: is not a done: line; code=%d out=%s", code, stdout)
	}
}

// --- T6: exit codes + encoding --------------------------------------------

func Test_StateCmd_TasksVerify_ExitCodes_ZeroOneTwo(t *testing.T) {
	repo := makeRepo(t)
	clean := writeTasks(t, repo, fmPlain+"- [x] T1 — a\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", clean); code != 0 {
		t.Errorf("clean ⇒ 0; got %d", code)
	}
	viol := writeTasks(t, repo, fmPlain+"- [x] T1 — a\n  - [ ] T1.a — b\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", viol); code != 1 {
		t.Errorf("violation ⇒ 1; got %d", code)
	}
	bad := writeTasks(t, repo, "no frontmatter\n- [x] T1 — a\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", bad); code != 2 {
		t.Errorf("malformed ⇒ 2; got %d", code)
	}
}

func Test_StateCmd_TasksVerify_Findings_TSVEscaping(t *testing.T) {
	repo := makeRepo(t)
	// A tab inside the task text must not create a phantom fourth field.
	p := writeTasks(t, repo, fmPlain+"- [x] T1 — has\ta tab\n  - [ ] T1.a — child\n")
	code, stdout, _ := runCmd(t, repo, "tasks-verify", p)
	if code != 1 {
		t.Fatalf("expected a violation; code=%d", code)
	}
	for _, line := range strings.Split(strings.TrimSpace(stdout), "\n") {
		if n := len(strings.Split(line, "\t")); n != 3 {
			t.Errorf("finding must have exactly 3 tab-separated fields, got %d: %q", n, line)
		}
	}
	if strings.Contains(stdout, "\\t") == false && strings.Contains(stdout, "has\ta tab") {
		t.Error("literal tab leaked into a field unescaped")
	}
}

// --- T8: predicate execution ----------------------------------------------

func Test_StateCmd_TasksVerify_Run_PredicatePasses(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a\n  done: $ true\n")
	if code, out, _ := runCmd(t, repo, "tasks-verify", p, "--run"); code != 0 {
		t.Fatalf("passing predicate ⇒ 0; code=%d out=%s", code, out)
	}
}

func Test_StateCmd_TasksVerify_Run_PredicateFails(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a\n  done: $ false\n")
	code, stdout, _ := runCmd(t, repo, "tasks-verify", p, "--run")
	if code != 1 {
		t.Fatalf("failing predicate ⇒ 1; code=%d", code)
	}
	if !strings.Contains(stdout, "predicate-failed") {
		t.Errorf("finding kind must be predicate-failed; got:\n%s", stdout)
	}
}

func Test_StateCmd_TasksVerify_NoRun_DoesNotExecute(t *testing.T) {
	repo := makeRepo(t)
	sentinel := filepath.Join(repo, "sentinel")
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a\n  done: $ touch "+sentinel+" && false\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p); code != 0 {
		t.Fatalf("without --run a failing predicate is not reported; code=%d", code)
	}
	if _, err := os.Stat(sentinel); err == nil {
		t.Error("predicate executed without --run")
	}
}

func Test_StateCmd_TasksVerify_Run_SkipsUntickedTasks(t *testing.T) {
	repo := makeRepo(t)
	// AC5: a plan whose later steps legitimately fail today must still verify.
	p := writeTasks(t, repo, fmContract+"- [ ] T1 — later\n  done: $ false\n")
	if code, out, _ := runCmd(t, repo, "tasks-verify", p, "--run"); code != 0 {
		t.Fatalf("unticked predicates are skipped; code=%d out=%s", code, out)
	}
}

func Test_StateCmd_TasksVerify_Run_CWDIsRepoRoot(t *testing.T) {
	repo := makeRepo(t)
	if err := os.WriteFile(filepath.Join(repo, "marker.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	// The predicate is relative to the repo root even though tasks.md lives two
	// directories down.
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a\n  done: $ test -f marker.txt\n")
	if code, out, _ := runCmd(t, repo, "tasks-verify", p, "--run"); code != 0 {
		t.Fatalf("predicate CWD must be the repo root; code=%d out=%s", code, out)
	}
}

func Test_StateCmd_TasksVerify_Run_CapturesOutputIntoDetail(t *testing.T) {
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a\n  done: $ echo needle-in-output; false\n")
	_, stdout, _ := runCmd(t, repo, "tasks-verify", p, "--run")
	if !strings.Contains(stdout, "needle-in-output") {
		t.Errorf("captured output must reach detail; got:\n%s", stdout)
	}
}

func Test_TasksVerify_CapDetail_TruncatesAt4KiB(t *testing.T) {
	long := strings.Repeat("z", tasksVerifyDetailCap+500)
	got := capDetail(long)
	if !strings.HasSuffix(got, tasksVerifyTruncMarker) {
		t.Error("truncated detail must carry the marker")
	}
	if len(got) != tasksVerifyDetailCap+len(tasksVerifyTruncMarker) {
		t.Errorf("cap not applied; len=%d", len(got))
	}
	if short := capDetail("abc"); short != "abc" {
		t.Errorf("short detail must pass through; got %q", short)
	}
}

func Test_TasksVerify_Timeout_Matrix(t *testing.T) {
	// Mirrors the spec-0045 parseLockTimeout matrix: every unusable value falls
	// back to the default; a valid value wins.
	for _, raw := range []string{"", "   ", "banana", "0s", "0", "-5s"} {
		if got := tasksVerifyTimeout(raw); got != tasksVerifyDefaultTimeout {
			t.Errorf("tasksVerifyTimeout(%q) = %v, want default %v", raw, got, tasksVerifyDefaultTimeout)
		}
	}
	if got := tasksVerifyTimeout("2s"); got != 2*time.Second {
		t.Errorf("valid duration must win; got %v", got)
	}
}

// --- T15: holes found by memory-keeper's adversarial close pass ------------
// These ARE genuine REDs: each reproduces a defect the shipped code had.

func Test_StateCmd_TasksVerify_BarePredicateMarkerIsMalformed(t *testing.T) {
	// `done: $` (or `$` plus whitespace) is non-empty to the parser, so AC8 let it
	// through, and predicateCommand then silently reclassified it as PROSE — a
	// ticked task that LOOKS executable exited 0 unverified. That is this spec's
	// own failure mode reproduced inside its own tool.
	repo := makeRepo(t)
	for _, body := range []string{
		fmContract + "- [x] T1 — a\n  done: $\n",
		fmContract + "- [x] T1 — a\n  done: $   \n",
	} {
		p := writeTasks(t, repo, body)
		if code, out, _ := runCmd(t, repo, "tasks-verify", p, "--run"); code != 2 {
			t.Errorf("bare `done: $` must be malformed; code=%d out=%s body=%q", code, out, body)
		}
	}
}

func Test_StateCmd_TasksVerify_HelpFlagPrintsBoundary(t *testing.T) {
	// AC14 requires the help text to state the prose-vs-executable boundary. It
	// only ever printed on the no-argument path: `--help` was treated as a
	// filename ("cannot read --help").
	repo := makeRepo(t)
	for _, flag := range []string{"--help", "-h"} {
		code, stdout, _ := runCmd(t, repo, "tasks-verify", flag)
		if code != 0 {
			t.Errorf("%s must exit 0; code=%d", flag, code)
		}
		if !strings.Contains(stdout, "never verified") || !strings.Contains(stdout, "side effects") {
			t.Errorf("%s must state the boundary; got:\n%s", flag, stdout)
		}
	}
}

func Test_StateCmd_TasksVerify_ExtraPositionalArgIsRejected(t *testing.T) {
	// A second path was silently ignored, so a typo'd invocation reported clean.
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmPlain+"- [x] T1 — a\n")
	if code, _, _ := runCmd(t, repo, "tasks-verify", p, "bogus-extra"); code != 2 {
		t.Fatalf("extra positional arg must be rejected; code=%d", code)
	}
}

func Test_StateCmd_TasksVerify_EscapingSurvivesTabInPredicateOutput(t *testing.T) {
	// The original escaping test never placed a tab in an emitted field — no
	// finding detail carries the task description — so AC7 was unpinned. Predicate
	// OUTPUT does reach detail, so drive it from there.
	repo := makeRepo(t)
	p := writeTasks(t, repo, fmContract+
		"- [x] T1 — a\n  done: $ printf 'col1\\tcol2\\nline2\\n'; false\n")
	code, stdout, _ := runCmd(t, repo, "tasks-verify", p, "--run")
	if code != 1 {
		t.Fatalf("failing predicate ⇒ 1; code=%d", code)
	}
	line := strings.TrimSpace(stdout)
	if n := strings.Count(line, "\n"); n != 0 {
		t.Errorf("a newline in predicate output must not split the finding; got %d newlines:\n%s", n, stdout)
	}
	if n := len(strings.Split(line, "\t")); n != 3 {
		t.Errorf("tab in predicate output must not add fields; got %d:\n%q", n, line)
	}
	if !strings.Contains(line, `\t`) || !strings.Contains(line, `\n`) {
		t.Errorf("tab/newline must appear escaped; got:\n%q", line)
	}
}

func Test_StateCmd_CrossCompilesForNonUnix_GOOSWindows(t *testing.T) {
	// RED: currently fails with `undefined: runPredicates` for GOOS=windows.
	// plan.md §Risk promised to mirror the ledger_flock_unix.go /
	// ledger_flock_other.go precedent "exactly". Only the unix half shipped, so
	// `GOOS=windows go build ./...` broke with `undefined: runPredicates` — a
	// cross-compile regression no existing test catches. A build-tag split must
	// ship BOTH halves.
	cmd := exec.Command("go", "build", "./...")
	cmd.Dir = "../.."
	cmd.Env = append(os.Environ(), "GOOS=windows", "GOARCH=amd64", "CGO_ENABLED=0")
	if out, err := cmd.CombinedOutput(); err != nil {
		t.Fatalf("GOOS=windows go build ./... failed: %v\n%s", err, out)
	}
}

// --- T11: tasks-done-pct non-regression ------------------------------------

func Test_StateCmd_TasksDonePct_IgnoresSubCheckboxes(t *testing.T) {
	// speccraft.TasksDonePct is a SECOND tasks.md reader (state.go). It counts
	// only column-0 `- [` lines, so under the new grammar it reports parent-level
	// progress and ignores indented sub-checkboxes. That is correct — but it is
	// correct by construction, not by intent, so pin it. Deliberately NOT
	// refactored onto the new parser: that would need an exported internal/
	// symbol and would break AC11's zero-override budget.
	repo := makeRepo(t)
	dir := filepath.Join(repo, "specs", "0099-fixture")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		t.Fatal(err)
	}
	body := fmContract +
		"- [x] T1 — done\n  - [ ] T1.a — child still open\n  done: prose\n" +
		"- [ ] T2 — open\n  done: prose\n"
	if err := os.WriteFile(filepath.Join(dir, "tasks.md"), []byte(body), 0o644); err != nil {
		t.Fatal(err)
	}
	if code, _, stderr := runCmd(t, repo, "set", "active_spec", "0099-fixture"); code != 0 {
		t.Fatalf("set active_spec failed: %s", stderr)
	}
	code, stdout, stderr := runCmd(t, repo, "tasks-done-pct")
	if code != 0 {
		t.Fatalf("tasks-done-pct exit=%d stderr=%s", code, stderr)
	}
	// 1 of 2 PARENT tasks ticked ⇒ 50, regardless of the unticked sub-checkbox.
	if got := strings.TrimSpace(stdout); got != "50" {
		t.Errorf("tasks-done-pct = %q, want \"50\" (parents only)", got)
	}
}

func Test_StateCmd_TasksVerify_Timeout_KillsProcessGroup(t *testing.T) {
	// THE load-bearing one. The predicate forks a child that outlives its `sh`
	// parent while holding the captured output pipe. Killing only the leader
	// leaves the pipe open and Wait never returns — the verifier hangs forever on
	// exactly the runaway predicate the timeout exists to bound. A group kill
	// reaps both.
	repo := makeRepo(t)
	t.Setenv(tasksVerifyTimeoutEnv, "300ms")
	p := writeTasks(t, repo, fmContract+"- [x] T1 — a\n  done: $ sleep 30 & sleep 30\n")

	done := make(chan int, 1)
	go func() {
		code, _, _ := runCmd(t, repo, "tasks-verify", p, "--run")
		done <- code
	}()

	select {
	case code := <-done:
		if code != 1 {
			t.Fatalf("timed-out predicate is a violation; code=%d", code)
		}
	case <-time.After(20 * time.Second):
		t.Fatal("tasks-verify hung: the timeout did not kill the process group")
	}
}
