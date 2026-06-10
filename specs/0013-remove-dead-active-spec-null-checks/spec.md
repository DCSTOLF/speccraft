---
id: "0013"
title: "Remove dead ActiveSpec == \"null\" checks"
status: in-progress
created: 2026-06-10
authors: [claude]
packages: ["tools/cmd/speccraft-guard", "tools/internal/speccraft"]
related-specs: ["0012"]
---

# Spec 0013 — Remove dead `ActiveSpec == "null"` checks

## Why

Spec 0012 (`Clear active_spec correctly on close`) added `,omitempty` to
the `ActiveSpec` JSON tag and special-cased the `null`/`""` argv form in
`SetField` so that the cleared shape on disk is "key absent." After
2e48a0f, no production path can produce `"active_spec": "null"` (the
literal string) on disk anymore — the only paths that ever wrote the
string `"null"` were the now-fixed `speccraft-state set active_spec null`
call and the model workaround pattern that the new PreToolUse hook also
blocks.

Two defensive readers still check for the literal string anyway:

```
tools/cmd/speccraft-guard/main.go:353:	if state.ActiveSpec == "" || state.ActiveSpec == "null" {
tools/internal/speccraft/root.go:45:	if activeSpec == "" || activeSpec == "null" {
```

The `== "null"` disjunct on each line is dead code. Spec 0012's plan
§Risk anticipated the `guard/main.go:353` site and named it as
"harmless after the omitempty change." The plan did not catch the
`root.go:45` site; spec 0012's changelog flagged both as deliberate
carry-forwards because the TDD hook correctly blocked editing them
mid-0012 (no fresh sibling-test edit in their respective packages
during that session). This spec is the bounded follow-up.

Leaving the dead-code clauses is harmless but corrosive: a future
reader trying to understand "what does `"null"` mean on disk?" finds
two false-positive answers ("it's a sentinel value the guard
defensively handles") instead of the truth ("it's an artifact of a
fixed bug; it can no longer happen"). Spec 0012's history.md ADR
explicitly flags this as queued cleanup.

## What

Two file edits, each preceded by a sibling-test addition that pins the
post-removal behavior so the dead-code removal is verifiable, not just
plausible.

1. **`tools/internal/speccraft/root.go`** — remove `|| activeSpec ==
   "null"` from the guard at line 45 inside `ActiveSpecDir`. New sibling
   test at `tools/internal/speccraft/root_test.go` (file does not exist
   yet; this spec creates it). The test asserts:
   - `ActiveSpecDir(root, "")` returns `""` (cleared / unset case).
   - `ActiveSpecDir(root, "0001-foo")` returns the joined path (real
     spec id round-trip).
   - **Pins the intentional behavior change.** `ActiveSpecDir(root,
     "null")` returns `filepath.Join(root, "specs", "null")`, **not**
     `""`. The function now treats `"null"` as an ordinary string id
     — harmless because nothing in the repo produces `"null"` as a
     real spec id post-0012. This assertion is what makes the
     dead-clause removal verifiable; without it the test only proves
     the empty-string case, which the old code already handled.

2. **`tools/cmd/speccraft-guard/main.go`** — remove `|| state.ActiveSpec
   == "null"` from the guard at line 353 inside `prodGuardPrologue`.
   New sibling test (or extension to existing) in
   `tools/cmd/speccraft-guard/main_test.go` asserts:
   - With `state.json` carrying no `active_spec` key (omitempty cleared
     shape, as produced by `speccraft-state set active_spec null`
     post-0012), `prodGuardPrologue` returns `prologueBlock` with an
     error message containing `"No active spec"`. This pins the
     current behavior, which the `== "null"` disjunct only "added"
     when the cleared shape was the literal string — never the case
     post-0012.

**Note for the planner.** Both edits are tightly scoped to the dead
clause. The behavior change is purely "what does the function do when
fed the literal string `"null"` as a spec id?" — before this spec, it
treats it as cleared/unset; after, it treats it as a literal string
(which would be a nonsense spec id, but no path produces it). This is
the right behavior change because:

- The reason for the special-case (a fixed tooling bug) no longer
  applies.
- The pre-0012 disk shape (`"active_spec": "null"`) cannot reappear at
  runtime unless someone reverts spec 0012, in which case 0012's own
  Go tests fail loudly first.

## Acceptance criteria

1. After the change,
   `grep -rnE 'ActiveSpec == "null"|activeSpec == "null"' tools/`
   returns zero matches. Verifiable mechanically.

2. `tools/internal/speccraft/root_test.go` exists, contains at minimum
   these three assertions:
   - **Cleared case:** `ActiveSpecDir(root, "")` returns `""`.
   - **Real-spec-id round-trip:** `ActiveSpecDir(root, "0001-foo")`
     returns `filepath.Join(root, "specs", "0001-foo")`.
   - **Behavior-change pin (the load-bearing assertion):**
     `ActiveSpecDir(root, "null")` returns
     `filepath.Join(root, "specs", "null")`, **not** `""`. Locks in
     the removal of the `== "null"` special case so a future
     reintroduction is caught at test time.

   Verifiable (from `tools/`): `go test ./internal/speccraft/` passes,
   and the new test functions appear when listed via
   `go test -list 'TestActiveSpecDir.*' ./internal/speccraft/`.

3. `tools/cmd/speccraft-guard/main_test.go` contains a test that
   asserts: with a `state.json` whose `active_spec` key is absent
   (the 0012 cleared shape), the production-edit guard returns
   `prologueBlock` plus an error whose message contains
   `"No active spec"`.

   **Fixture setup (pinned).** The test constructs the cleared
   shape via `os.WriteFile` on a tmpdir-rooted
   `.speccraft/state.json`, writing the literal JSON
   `{"version":1,"session":{"id":"","edited_test_files":[],"edited_prod_files":[]}}`
   (no `active_spec` key). Do **not** shell out to
   `speccraft-state set active_spec null` from a Go test — that
   would couple `go test ./cmd/speccraft-guard/...` to a built binary
   on `$PATH`, breaking unit-test hermeticity.

   Verifiable (from `tools/`): the test passes; the test function
   name appears under
   `go test -list '<NewTest>' ./cmd/speccraft-guard/`.

4. Full `go test ./...` from `tools/` is green; full `bats tests/hooks/`
   from repo root is green. No existing test regresses.

## Out of scope

- The two dead clauses on lines 353 and 45 are the **only** sites
  named in this spec. Other defensive fallbacks elsewhere in the
  codebase (if any exist) are not in scope; bundling them would
  defeat the bounded-cleanup purpose.
- Schema or semantics changes to `State.ActiveSpec` (already settled
  by spec 0012; this spec only removes downstream readers' dead
  branches).
- README + `speccraft-v1-spec.md` CodeGraphContext cleanup (still
  queued from spec 0011's §Out of scope).
- `/speccraft:spec:revise` command (still queued from spec 0011's
  §Out of scope).
- Refactoring `ActiveSpecDir` or `prodGuardPrologue` beyond the
  one-line removal each. If either function needs a larger redesign,
  file a separate spec.

## Open questions

_none_
