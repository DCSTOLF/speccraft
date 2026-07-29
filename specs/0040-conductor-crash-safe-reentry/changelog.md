# Changelog — Spec 0040 Crash-safe conductor re-entry

Closed 2026-07-29. Completes design-0001's crash-safety story deferred by the 0039
MVP. Additive shell + markdown (extends `orchestrate.lib.sh`/`.md` + the hermetic
e2e). **Zero `/speccraft:spec:override`** (shell/markdown ungated; bats + e2e are the
RED oracle). Full `tests/hooks/` suite (215) green, `go test ./...` green.

## What shipped (vs spec)

- **AC1 — three ordinal/token helpers (direct tests).** `orch_status_ordinal`
  (`""`/`blocked`→-1, `draft`→0 … `closed`/`archived`→4), `orch_status_token`
  (`draft`→`new` … `closed`→`validated`), `orch_phase_completion_status`
  (`new`→`draft` … `validate`→`closed`).
- **AC2 — `orch_reentry`.** `adopt` iff the member's status ordinal ≥ the in_flight
  phase's completion ordinal, else `reattempt`; `""`/`blocked` never adopt. On adopt
  the pointer jumps to `orch_status_token(status)` (the artifact's true position — an
  out-of-band `review`+`closed` lands on `validated`, no partial replay). Load-bearing:
  `validate`+`closed`→adopt (no re-close), `new`+`""`→reattempt.
- **AC3 — `orch_find_member_spec`.** Keys on the **`informed-by: [design/<id>]`**
  frontmatter `spec:new` actually writes (not `design:`); scans `specs/` + `.archive/`;
  0→empty, ≥2→error (ambiguous adoption), and a `get-frontmatter` **read failure**→error
  (never a false zero, via exit-code-vs-empty discrimination).
- **AC4 — `orch_in_flight_phase`.** Bare token (0039 compat) or first `phase=<p>` (any
  position, first-wins); `=`-without-`phase=` and empty → error.
- **AC5 — runbook.** `orchestrate.md` gains **create-if-absent seeding** (never
  re-`spec ""` on an existing row), a resume/re-entry section (new-first adoption via
  `orch_find_member_spec`; other phases via `orch_reentry` with the `orch_status_token`
  adopt pointer), and the structured `phase=review iteration=<n>` in_flight. Grep-pinned.
- **AC6 — hermetic e2e crash legs (direct, isolated).** Three legs, each in a fresh
  `mktemp` workspace: **no-re-close** (`in_flight=validate` + spec `closed` → adopt →
  `validated`/`done:true`, validate-mock **dispatch sentinel == 0**); **no-double-allocate**
  (`in_flight=new` + design-linked spec exists → adopt the ref, ledger `spec` non-empty,
  no second `specs/` dir, `new`-mock sentinel == 0); **restart-safety** (idempotent
  re-seed preserves a captured ref).

## Notable during review

Cross-model (codex changes-requested → resolved; claude-p approve-with-comments) caught
the load-bearing bugs: the back-reference key had to be `informed-by` (what `spec:new`
writes) not `design:`; unconditional seeding clobbered a captured ref on restart; the
no-double-allocate leg needed a `new`-dispatch sentinel (a dir-count alone can't catch a
mock that overwrites the same ref). The self-check earlier caught the `adopt`-by-one
multi-phase bug (fixed by jumping to the artifact token) and the `in_flight=new` path
dropping the ref (fixed by `new`-first precedence).

## Deviations / deferrals

- **Literal spec-id-before-dispatch is not delivered** (infeasible without changing
  `spec:new`'s allocation contract) — superseded by `orch_find_member_spec` post-hoc
  adoption. The window closed is precisely "delegated command succeeded, ledger advance
  did not."
- Concurrent-conductor locking still deferred. No version bump — with the whole
  design-0001 arc (0037–0040) now complete, a release step can bundle it.

## The design-0001 arc is now complete

0037 topology → 0038 ledger+reconcile → 0039 orchestrate command → **0040 crash-safe
re-entry**. The conductor is buildable, resumable, failure-isolated, and idempotent
against the crash window.
