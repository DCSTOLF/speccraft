---
spec: "0013"
status: planned
strategy: tdd
---

# Plan — 0013 Remove dead `ActiveSpec == "null"` checks

## Framing note

Spec 0013 is bounded cleanup: each production edit is a one-line
removal. The TDD framing differs slightly between the two sites,
and the implementer must respect the distinction so the gate
hook (spec 0012) does not block mid-stream.

- **Site A — `tools/internal/speccraft/root.go:45` (`ActiveSpecDir`).**
  This is a classical RED → GREEN cycle. The behavior-change pin
  in AC2 (`ActiveSpecDir(root, "null")` returns
  `filepath.Join(root, "specs", "null")`, not `""`) FAILS against
  current `main` because the dead `|| activeSpec == "null"` clause
  forces the return path to `""`. Writing the test first observes
  the real RED, then the one-line removal flips it GREEN. The
  spec's prose hedges on this because "remove dead code" feels
  refactor-shaped, but the load-bearing assertion is genuinely
  a behavior change that flips today.
- **Site B — `tools/cmd/speccraft-guard/main.go:353`
  (`prodGuardPrologue`).** This is an assertion-pinning refactor,
  not a classical RED → GREEN. The new test (AC3) constructs the
  post-0012 omitempty-cleared `state.json` shape (no `active_spec`
  key) and asserts that `prodGuardPrologue` returns
  `prologueBlock` + an error containing "No active spec". That
  test passes BEFORE the removal (the `state.ActiveSpec == ""`
  arm of the disjunct catches it) and continues to pass AFTER
  the removal (same arm; the `== "null"` arm was the dead one).
  This is the standard form for "lock in the path I'm about to
  shave" — no artificial RED should be manufactured. Document
  this in the implementation commit message.

## Sequencing gate from spec 0012

The PreToolUse hook from spec 0012 will block any production edit
in a Go package unless a sibling test file in the same package
was edited recently in the same session. That forces this strict
ordering:

1. T1 (write `tools/internal/speccraft/root_test.go`) MUST land
   before T2 (edit `root.go`).
2. T3 (extend `tools/cmd/speccraft-guard/main_test.go`) MUST land
   between T2 and T4 — bundling T1+T3 ahead of T2+T4 will not work
   because the hook examines the most-recent sibling-test edit per
   package, and editing root.go (T2) is the package switch that
   would invalidate a T3-then-T2 pairing.

T1 → T2 → T3 → T4 → T5 is the only ordering that satisfies the
hook end-to-end.

## Test-first sequence

### Step 1 — Sibling test for `ActiveSpecDir` (RED) — AC2

- Add `tools/internal/speccraft/root_test.go`:
  - Package: `package speccraft_test` (matches sibling
    `state_test.go`, `state_clear_test.go`).
  - Imports: `path/filepath`, `testing`,
    `github.com/dcstolf/speccraft/tools/internal/speccraft`.
  - `TestActiveSpecDir_EmptyReturnsEmpty` —
    asserts `speccraft.ActiveSpecDir("/repo", "")` returns `""`.
    Covers the cleared/unset case. Passes against current main.
  - `TestActiveSpecDir_RealSpecIdReturnsJoinedPath` — asserts
    `speccraft.ActiveSpecDir("/repo", "0001-foo")` returns
    `filepath.Join("/repo", "specs", "0001-foo")`. Round-trip
    sanity. Passes against current main.
  - `TestActiveSpecDir_LiteralNullReturnsJoinedPath` — **the
    load-bearing behavior pin from AC2.** Asserts
    `speccraft.ActiveSpecDir("/repo", "null")` returns
    `filepath.Join("/repo", "specs", "null")`, NOT `""`. This is
    the case that fails against current main because the dead
    `|| activeSpec == "null"` clause short-circuits to `""`.
- Run `go test ./internal/speccraft/` from `tools/`.
- Tests fail: `TestActiveSpecDir_LiteralNullReturnsJoinedPath`
  fails because the production code still treats `"null"` as the
  cleared sentinel. The other two pass.

### Step 2 — Remove the dead clause in `ActiveSpecDir` (GREEN) — AC1

- Edit `tools/internal/speccraft/root.go`:
  - Inside `ActiveSpecDir` (line 45), change
    `if activeSpec == "" || activeSpec == "null" {` to
    `if activeSpec == "" {`.
  - No other edits in this file.
- Run `go test ./internal/speccraft/` from `tools/`.
- All three step-1 tests pass. The package's existing tests stay
  green (no other call sites changed).

### Step 3 — Sibling test for `prodGuardPrologue`
(assertion-pinning refactor) — AC3

- Extend `tools/cmd/speccraft-guard/main_test.go`:
  - Add `Test_ProdGuardPrologue_MissingActiveSpecKeyBlocks`.
  - Package stays `package main` (matches existing tests in this
    file). Reuse existing imports (`os`, `path/filepath`,
    `strings`, `testing`).
  - Fixture **must** use `os.WriteFile` per AC3's pinned shape;
    do NOT shell out to `speccraft-state`. Exact literal:
    `{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
    written to `<tmp>/.speccraft/state.json`. (This is distinct
    from `makeTestRepo`'s shape, which sets `active_spec` to
    JSON null when `activeSpec == ""`; AC3 specifically pins the
    omitempty-cleared shape where the key is absent entirely.)
  - Create a stub `<tmp>/pkg/main.go` to use as the `absPath`
    argument so the error format string can interpolate it.
  - Call `prodGuardPrologue(absPath, root)`.
  - Assert `dec == prologueBlock`.
  - Assert `err != nil` and
    `strings.Contains(err.Error(), "No active spec")`.
- Run `go test ./cmd/speccraft-guard/` from `tools/`.
- Test passes today (the `state.ActiveSpec == ""` arm of the
  disjunct catches the absent-key case via Go's zero value).
  This is the documented assertion-pinning case, not a classical
  RED — see §Framing note above.

### Step 4 — Remove the dead clause in `prodGuardPrologue`
(REFACTOR, behavior-preserved) — AC1

- Edit `tools/cmd/speccraft-guard/main.go`:
  - Inside `prodGuardPrologue` (line 353), change
    `if state.ActiveSpec == "" || state.ActiveSpec == "null" {`
    to `if state.ActiveSpec == "" {`.
  - No other edits in this file.
- Run `go test ./cmd/speccraft-guard/` from `tools/`.
- All existing tests stay green, including the step-3 test
  (which still passes because `state.ActiveSpec` is the empty
  string when the key is absent from JSON — Go's zero value).

### Step 5 — Verification gate, grep oracle, binary rebuild — AC1+AC4

- Run `go test ./...` from `tools/`. All green.
- Run `bats tests/hooks/` from repo root. All green.
- Grep oracle for AC1 (must return zero matches):
  `grep -rnE 'ActiveSpec == "null"|activeSpec == "null"' tools/`
- Rebuild `bin/speccraft-guard` so the runtime hook uses the
  post-removal binary. (The pre-edit `bin/` versions are stale
  after T4.) Command:
  `(cd tools && go build -o ../bin/speccraft-guard ./cmd/speccraft-guard)`.
  Do not stage `bin/` into git — it is gitignored per
  guardrails.md.
- Confirm new test names show up via:
  - `go test -list 'TestActiveSpecDir.*' ./internal/speccraft/`
    (from `tools/`) lists all three new functions.
  - `go test -list 'Test_ProdGuardPrologue_MissingActiveSpecKeyBlocks'
    ./cmd/speccraft-guard/` (from `tools/`) lists the new
    function.

## Delegation

- No aux-agent delegation. The plan is two one-line production
  removals + one new test file + one extended test file, all
  inside `tools/`. Single-author execution by the tdd-implementer
  agent is sufficient and avoids unnecessary review overhead.

## Risk

- **Hook gate blocking mid-stream.** If T2 is attempted before T1
  lands, or T4 before T3, the PreToolUse hook from spec 0012
  rejects the production edit for lack of a recent sibling-test
  edit in the affected package. Mitigation: strict
  T1 → T2 → T3 → T4 ordering as called out in §Sequencing gate.
- **Step-3 test mis-fixtured.** If the test constructs the state
  via the `makeTestRepo(t, "", "")` helper instead of
  `os.WriteFile` of the AC3-pinned literal, it asserts behavior
  against a `"active_spec":null` shape rather than the
  omitempty-absent shape. Both currently produce the same Go
  zero value, but the AC3 fixture-setup clause exists precisely
  to pin which on-disk shape the test guards. Mitigation: write
  the literal verbatim as specified in step 3.
- **Stale `bin/speccraft-guard`.** Forgetting T5's rebuild leaves
  the runtime hook running pre-removal code; subsequent in-session
  edits would not observe the change. Mitigation: include the
  rebuild step in T5 and verify with `go test -list` listings.
- **`bin/` accidentally staged.** Both `bin/` and `tools/bin/`
  are gitignored per guardrails.md; the rebuild in T5 is local
  only. Mitigation: rely on `.gitignore`; do not pass `-f` to
  `git add`.
