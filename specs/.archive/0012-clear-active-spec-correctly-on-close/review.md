---
spec: "0012"
reviewers: [codex, claude-p]
quorum: 1
verdict: approve-with-comments
generated: 2026-06-10T00:00:00Z
---

# Cross-model review — 0012

## codex

**Verdict:** approve-with-comments

Concerns:
- AC5 is a post-merge/close-gate condition, not an implementation AC the planner
  can satisfy during RED→GREEN. It is structurally correct per the spec 0008
  close-gate convention, but its placement in the flat AC list mixes
  locally-verifiable assertions with a future GHA-run dependency.
- AC6 / §What item 4 (test-naming convention cleanup) is orthogonal to the
  active_spec failure. The §Why ties them together only via "the same CI run
  surfaced..." — concurrent, not causal. It is small enough to keep, but must
  be explicitly labeled minor and documentation-only so it does not distract
  the implementation plan.

Suggestions:
- Move AC5 to a dedicated "Post-merge verification" or "Close gate" section
  rather than mixing it with locally-verifiable ACs.
- In AC1, prefer a pure-Go assertion for JSON null/default semantics unless jq
  is guaranteed in the Go test environment; keep a comment linking back to
  tests/e2e/run.sh:281 either way.
- For the hook guardrail (§What item 3 / AC4), specify whether path resolution
  must account for symlinks or only cleaned absolute/relative paths, so the
  planner can write exact tests without guessing.

Guardrail violations: none
Convention violations: none

Cosmetic: stray full-width period `。` appears in the §Why state.go snippet.

---

## claude-p

**Verdict:** approve-with-comments

Concerns:
- AC6 / §What item 4 (test-naming convention) is genuinely orthogonal. Bundling
  it here gives the planner two unrelated change sets to sequence and dilutes
  focus on the state-clearing fix. The verify.sh oracle pattern would fit a
  follow-up doc-only spec cleanly (natural continuation of spec 0011's work).
- AC4 / §What item 3 do not address legitimate first-write scenarios. If
  `/speccraft:init` or any future bootstrap ever Writes state.json directly
  (rather than letting speccraft-state create it on first call), the new hook
  will block it. The spec should either assert that no such path exists today
  (planner verifies) or carve an explicit allow-list. Without that, there is a
  latent footgun.
- AC4's hook test envelope shape is illustrative, not pinned. It does not
  specify whether the hook must also catch `MultiEdit`, `NotebookEdit`, or
  `Write` with a `content` field. The planner needs the full set of Claude Code
  write-tool names enumerated in §What.
- AC6's decision direction is left open ("either tighten OR document both").
  §What item 4 leans toward documenting both, but the AC does not pin it. The
  planner could ship either outcome and pass AC6. The spec should make the
  recommendation explicit.

Suggestions:
- Split AC6 + §What item 4 into a follow-up doc-only spec (natural continuation
  of spec 0011's verify.sh oracle work).
- Add to §What item 3: the hook must catch the full set of Claude Code write
  tools (Edit, Write, MultiEdit, NotebookEdit). Enumerate them in source so
  adding a new write-tool is a one-line change.
- Add a compatibility check to §What item 3: the planner verifies that no
  current command, hook, or fixture writes state.json via Edit/Write before the
  hook lands. If any do, migrate them to speccraft-state or carve an exception.
- AC4: add a third assertion case — hook does NOT reject Edit/Write on unrelated
  `.speccraft/` files (e.g., conventions.md). Prevents a copy-paste regex error
  from silently locking down the entire memory directory.
- Tighten AC2 wording: "`set active_spec ""`" implies empty-string argv via
  shell, which Bash handles awkwardly. The Go test should assert the
  empty-string-argv form specifically, not the missing-argv form, to make the
  assertion unambiguous.

Guardrail violations: none
Convention violations: none

---

## Synthesis

Both reviewers approve with comments. There are no guardrail or convention
violations. The spec is well-grounded — §Why is anchored in an exact CI run
with a quoted failure, the Bug A / Bug B split is sharp, and AC1–AC4 are
concrete and verifiable. The overall structure is sound.

### Points of strong agreement (two-signal; higher weight)

**AC6 / naming-convention thread is orthogonal.** Both reviewers independently
flag that the justification is "same CI run surfaced it" — concurrent, not
causal. The remedies differ (codex: keep-but-shrink; claude-p: split out), but
the diagnosis is identical and load-bearing. This is the primary scope concern.
Recommended resolution: keep AC6 in this spec only because it is a
one-to-two-line documentation edit that the planner can dispatch in minutes
alongside the main fix. However, the spec must make the decision explicit —
"document both forms as acceptable" — so the planner has no ambiguity.

**AC5 placement.** Both reviewers agree its shape is correct per spec 0008's
close-gate convention; the concern is placement in the flat AC list alongside
locally-verifiable assertions. It should be separated into its own labeled
section (e.g., "Post-merge close gate") to avoid misleading the planner into
thinking it must be satisfied before merging.

**Planner needs more pinning.** Both reviewers independently note that the spec
underspecifies what the planner must implement. The gaps are distinct but
additive: codex wants path/symlink resolution clarified; claude-p wants the
hook's write-tool enumeration and a first-write compatibility check.

### Points of single-reviewer concern (one-signal; must still be addressed)

**Hook write-tool enumeration (claude-p only, load-bearing).** §What item 3
mentions only `Edit` and `Write`. Claude Code exposes at minimum `MultiEdit`
and `NotebookEdit` as additional write tools that could target state.json. If
these are not covered, the guardrail has a bypass. The planner cannot resolve
this correctly without the spec enumerating the target set.

**First-write compatibility (claude-p only, latent risk).** If any current
bootstrap path writes state.json via Edit/Write, the new hook blocks it silently
on the next execution. The spec must direct the planner to verify this before
landing the hook.

**AC4 false-positive case (claude-p only, load-bearing).** The hook test
currently has two positive-rejection cases (absolute path, relative path). It
needs a third negative case: hook must NOT reject Edit/Write on other
`.speccraft/` files such as `conventions.md`. Without this, a regex error that
matches the directory prefix instead of the full path silently locks down
everything under `.speccraft/`.

**AC2 empty-string-argv ambiguity (claude-p only, minor).** The wording implies
a shell invocation, but the Go test should exercise the argument directly.
Worth tightening to prevent the planner from writing a test that only passes
because the shell eats the empty string.

**Path/symlink resolution (codex only, minor).** The spec should state whether
the hook path-match is performed after `filepath.Clean` on the input or also
after `filepath.EvalSymlinks`. If the `.speccraft/` directory itself is a
symlink (unlikely but possible in worktrees), the hook could be bypassed.

**Cosmetic.** The full-width period `。` in the §Why state.go snippet should be
removed before the spec moves to implementation.

### Priority ordering for the spec author

**Must-fix before plan begins (blocking the planner):**

1. Enumerate the full set of Claude Code write-tool names the hook must cover
   in §What item 3 (at minimum: Edit, Write, MultiEdit, NotebookEdit).
2. Add to §What item 3: planner verifies no current bootstrap or command writes
   state.json directly via Edit/Write before landing the hook.
3. Add a third assertion case to AC4: hook must NOT fire on Edit/Write targeting
   other `.speccraft/` files.
4. Move AC5 out of the numbered AC list and into a separate "Post-merge close
   gate" section with a note that it is not a pre-merge gate.
5. Resolve AC6's open direction explicitly in the spec text: "document both
   `Test<UpperCamel>` and `Test_<Subject>_<Scenario>` as acceptable; underscore
   form preferred for scenario-specific tests." Remove the "either/or" framing.

**Should-fix (clarifies planner scope but not strictly blocking):**

6. State whether hook path-matching uses `filepath.Clean` only, or also
   `filepath.EvalSymlinks`, so the planner can write exact tests.
7. Tighten AC2 to make clear that the Go test exercises the `""` argument
   directly, not via a shell expansion that may collapse it.
8. In AC1, add a comment linking the Go test back to tests/e2e/run.sh:281, and
   note whether jq is required or a pure-Go equivalent is acceptable.

**Nice-to-have (editorial):**

9. Remove the full-width `。` from the §Why state.go snippet.
10. If AC6 / §What item 4 grows in scope at all during planning (e.g.,
    a regex change is chosen over documentation), split it into a follow-up
    spec rather than expanding this one.

**Action:** Return to draft. Resolve items 1–5 above (all are edits to §What
and the AC list, no new sections required). Items 6–8 are recommended before
handing to the planner but will not block a second review pass. Once items 1–5
are addressed the spec is ready for `/spec:plan`.
