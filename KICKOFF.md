# speccraft v1 — implementation kickoff

You are Claude Code, and you are implementing the **speccraft** plugin from scratch. The complete specification is in `speccraft-v1-spec.md` in this directory. The user-facing documentation is in `README.md`. Both files are your source of truth. Read them in full before you do anything else.

This file is the one-time kickoff. It tells you how to work, not what to build — that lives in the spec.

---

## 0. Pre-flight

Before reading further, verify these inputs exist in the working directory:

```
speccraft-v1-spec.md
README.md
.devcontainer/devcontainer.json
.devcontainer/Dockerfile
.devcontainer/setup.sh
.devcontainer/install-mock-agents.sh
tests/e2e/run.sh
```

If any are missing, stop and tell the user. Don't try to recreate them — they're the project's seed and the user has them.

---

## 1. Mission

Implement speccraft v1, phase by phase, exactly as specified. Phases are defined in §16 of the spec; tasks in §17. Each phase has explicit done-criteria. Do not:

- Skip phases or merge them.
- Invent features beyond the spec.
- Substitute different technical choices. The locked decisions are: pure-Go binaries (`CGO_ENABLED=0`); GitHub Releases distribution; **no code graph** (the spec deliberately removed it — see §13 and §20.1); regex-only drift in v1; sibling-test heuristic for TDD enforcement; devcontainer-first development.
- Add tree-sitter, AST rule registries, `.speccraft/graph/`, or any related machinery. Earlier drafts had these and they were removed for good reasons. If you find yourself wanting to add one, you've misread the spec — re-read §3 (non-goals) and §13.

If the spec is genuinely ambiguous on a point, see §6 below.

---

## 2. Environment: read this carefully

speccraft hooks fire on every `Edit`/`Write` in any active Claude Code session. A buggy hook on the host machine will lock up unrelated work in unrelated repos. §18 of the spec mandates that **all development happens inside the speccraft devcontainer**.

Before doing anything else, run these checks:

1. **Container check.** Run `cat /etc/os-release 2>/dev/null` and `uname -a`. If you are NOT inside a Linux container (specifically Ubuntu, with `/workspaces/` as the workspace root and `vscode` as a user), **STOP**. Tell the user:
   > "speccraft must be developed inside its devcontainer. Please run `Cmd+Shift+P` → `Dev Containers: Reopen in Container` in VS Code, then start a new Claude Code session inside the container and re-run this prompt."

2. **Toolchain check.** Run `which claude && claude --version`, `which go && go version`, `which jq`, `which git`. If anything is missing, the Feature install or Dockerfile is broken — surface the exact missing tool and stop.

3. **Auth check.** Run `claude --version` (which fails clearly if not authenticated). If unauthenticated, tell the user:
   > "Claude Code is not authenticated inside the container. Run `claude` once interactively to complete the OAuth browser flow. The token will persist in the named volume across rebuilds."

If any check fails, **stop and surface the failure**. Do not attempt to "fix" the environment — those fixes belong to the user (host-side actions, browser flows, container rebuilds).

---

## 3. The recursion: implement speccraft as a speccraft project

The spec for speccraft v1 is *itself* a speccraft spec. Lean into this from day one. As your first action in **Phase 0**, create the canonical structure that speccraft would manage if it already existed:

```
specs/0001-speccraft-v1/
├── spec.md           # frontmatter + §1, §2, §3, §4, §5, §6, §7 of the input spec
├── plan.md           # frontmatter + §16 of the input spec
├── tasks.md          # frontmatter + §17 of the input spec
├── notes.md          # your scratchpad: things to verify outside container, etc.
└── open-questions.md # ambiguities found during implementation, with your call + rationale
```

`tasks.md` is the canonical progress tracker. **Update the checkboxes as you complete tasks.** This is your resumption point if a session is compacted or interrupted.

The original `speccraft-v1-spec.md` stays at the repo root as a single-file reference (and historical artifact). Don't delete it.

---

## 4. Working pattern

For each phase:

1. **Re-read** the phase description in §16 and its tasks in §17. Don't rely on memory across phases — context shifts.
2. **Read prerequisites.** Phase 4 needs §15 (TDD invariant logic) and §6.3 (guardrails example). Phase 7 needs §14 (drift). Etc. The spec is interlinked.
3. **Implement** the tasks in order. Within a phase, tasks are usually sequenced sensibly — follow the order unless you have a strong reason.
4. **Test.** Run the appropriate command for the phase:
   - Phase 0–0.5: manual verification (plugin loads, devcontainer rebuild preserves auth).
   - Phase 1+: `cd tools && go test ./...` for any binary you've touched.
   - Hooks: `bats tests/hooks/<name>.bats`.
   - End-to-end: `bash tests/e2e/run.sh`. (Initially the e2e run will fail beyond the phase you're in — that's fine; assert that it passes through your phase's steps.)
5. **Update `tasks.md`** — mark completed tasks `[x]`. Add a one-line note for any task you couldn't fully verify (e.g., "host Claude Code unaffected — needs user verification, see notes.md").
6. **Commit.** Phase boundaries are commit boundaries. Format: `phase N: <short description>`. Stage everything except gitignored files.
7. **Pause and report.** Output:
   - Phase complete: ✅ Phase N (<name>)
   - Tasks done this phase: <count> / <total>
   - Tests run: <list>, all passing / <count> failing
   - Open questions accumulated: <count> (see open-questions.md)
   - Next: Phase N+1 (<name>)

   Then wait for the user to say "continue" or to redirect. **Don't run multiple phases unattended unless the user explicitly asks for that.** This is a long-running build and human checkpoints matter.

---

## 5. Compaction and resumption

This is a multi-day project. Your context will be compacted. When you resume:

1. Read `specs/0001-speccraft-v1/tasks.md` first — it tells you exactly where you left off.
2. Read `specs/0001-speccraft-v1/open-questions.md` — these are decisions that may need follow-up.
3. Read `specs/0001-speccraft-v1/notes.md` — gotchas you flagged for yourself.
4. Re-read the active phase from §16 of the spec.
5. Run `git log --oneline -20` to confirm where the codebase actually is.
6. Confirm with the user: "Resuming at Phase N, task TN.M. Continue?"

**Do not** assume your previous in-context understanding is intact. Rebuild it from the files. The files are the truth.

---

## 6. When you hit ambiguity

The spec is detailed but not exhaustive. When something is unclear:

- **Ambiguity with an obvious conservative answer.** Take the conservative answer. Append a short entry to `open-questions.md` noting the ambiguity and your call. Continue.
- **Ambiguity with no obvious answer.** Stop. Ask the user. Append the question and the user's answer to `open-questions.md`.
- **Spec contradiction.** Stop. Report both readings. Ask the user.
- **Test fails because the spec describes the wrong behavior.** Stop. Report. Wait. Don't "fix" the spec yourself — that's a user decision.
- **Phase done-criteria you can't verify from inside the container** (e.g., "host Claude Code unaffected during teardown"). Note it in `notes.md` with explicit instructions for the user to verify, and proceed. Don't block on out-of-band verification.

---

## 7. What NOT to do

- **No host-side `claude` invocations.** While developing speccraft, don't tell the user to run `claude` outside the container for testing. The container is the test environment.
- **No re-introducing removed features.** Specifically: no code graph, no `.speccraft/graph/`, no tree-sitter, no `enforce: ast`, no AST rule registry, no `tools/internal/graph/`, no `speccraft-graph` binary. If you find a stale reference in the spec or README, flag it as a bug, don't act on it.
- **No commits of secrets or generated artifacts.** `.gitignore` should cover `bin/` (except `.gitkeep`), `.binary-version`, `.env*`, `tests/e2e/.logs/`, `.speccraft/state.json`. Verify before each commit.
- **No silent feature additions.** §3 (non-goals) is binding. If you think something is missing from v1 and should be added, file an open question — don't add it.
- **No skipping Phase 0.5.** The devcontainer must work and the e2e harness must run a smoke check before any hook is written. This is the safety net for the rest of the build.
- **No vendored aux-agent CLIs.** The Dockerfile leaves Codex/OpenCode commented out by design. Hermetic mocks via `install-mock-agents.sh` are the v1 default.

---

## 8. Placeholder substitution (one-time, in Phase 0)

The input files contain `<owner>` and `<author>` placeholders. Before any other Phase 0 work, ask the user for:

1. **GitHub organization or user** — substitutes for every `<owner>` in `speccraft-v1-spec.md`, `README.md`, and any new files you create. Example: `acme-corp` or `janedoe`.
2. **Author name and contact** — substitutes for `<author>` in `plugin.json`. Example: `Jane Doe <jane@example.com>`.
3. **License** — default MIT. Confirm or change.
4. **Module path for `tools/go.mod`** — typically `github.com/<owner>/speccraft/tools`. Confirm.

Do this substitution as a single commit (`phase 0: substitute placeholders`) before any other Phase 0 work.

---

## 9. Output style

- **Be concrete.** When you say "I implemented Phase 4," say what files you created/modified and what tests pass.
- **Quote the spec when in doubt.** If you're making a decision based on §15.7 of the spec, name it. This makes course-correction easy for the user.
- **Don't editorialize the design.** The design is locked. Your job is execution and faithful translation, not redesign. If you have a strong opinion that a design choice is wrong, file it as an open question and continue with the spec's choice.
- **Surface costs honestly.** If a phase took longer than its estimate, say so and why. If a test is flaky, say so. If a tool failed and you worked around it, say what the workaround was.

---

## 10. Start here

In order:

1. Read `speccraft-v1-spec.md` end to end. (It's ~2000 lines. Read all of it before writing any code.)
2. Read `README.md` end to end.
3. Run the environment checks in §2 of this kickoff prompt. Stop if any fail.
4. Ask the user for the placeholder values from §8.
5. Begin Phase 0.

When you're ready to start, say:

> "Environment verified. Inputs read. Beginning Phase 0 with substitutions: owner=`<x>`, author=`<y>`, license=`<z>`."

Then proceed.

Good luck.
