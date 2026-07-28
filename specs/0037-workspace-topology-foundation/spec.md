---
id: "0037"
title: "Workspace topology foundation"
status: closed
created: 2026-07-28
authors: [claude]
packages: []
related-specs: []
informed-by: [design/0001-architect-lifecycle-orchestration]
design: 0001-architect-lifecycle-orchestration
---

# Spec 0037 — Workspace topology foundation

## Why

Design 0001 (decided) graduates the architect into a **conductor** that
orchestrates the spec lifecycle across N member repos of a *workspace*. That
orchestration (the conductor, `ledger.md`, dispatch, reconcile) is Spec B. It
cannot be built until speccraft has the underlying **topology primitives** and
the one **missing read surface** reconcile depends on.

This spec delivers *only* that foundation, and delivers it so that existing
single repos are affected **not at all**: the workspace/member distinction, the
membership manifest, workspace-root resolution, an authoritative status reader,
and the `design:` back-reference key. Everything reuses the repo's existing
hand-rolled parsing style — there is **no YAML/frontmatter library in `tools/`**;
config is parsed by `parseSpeccraftTOML` and spec frontmatter by the single
`parseFrontmatterBlock` grammar (spec 0036). Everything is gated behind an
absent-means-`repo` default, so a repo with no `kind` key and no `workspace.yml`
behaves exactly as it does today.

## Layering & conventions (applies to every AC below)

- **Pure logic in `tools/internal/speccraft`** returns typed values and `error`s
  and **never prints** (conventions: "internal returns errors, doesn't print").
  All human-facing messages, exit codes, and stream (`stdout`/`stderr`) contracts
  named below are owned by the **`speccraft-state` cmd layer**.
- **Frontmatter reads route through the single spec-0036 `parseFrontmatterBlock`
  grammar** — no second frontmatter parser is introduced (both `get-status` and
  the `design:` extractor go through it).
- **Override budget (spec-0018-AC13).** The **complete** inventory of new *exported*
  `tools/internal/speccraft` symbols is: `Config.Kind` (struct field);
  `FindWorkspaceRoot(dir)`; `ParseWorkspaceMembers(path)` + its `Member{Path string;
  Present bool}` type; and `ReadFrontmatterField(specMd, key)` (an exported reader
  wrapping the existing **unexported** spec-0036 `parseFrontmatterBlock` — the
  grammar itself is reused, not duplicated). These are introduced in **one
  consolidated bootstrap edit** costing a **single** `/speccraft:spec:override`
  (spec 0036 T1 pattern). Every new `speccraft-state` subcommand (`get-status`,
  `get-frontmatter`, `list-members`) instead rides the `run()` seam (a runtime
  "unknown subcommand" RED — **zero** extra override).

## What

- **`kind` config key** — `kind = "repo" | "workspace"` in `.speccraft/speccraft.toml`,
  read by extending `parseSpeccraftTOML` (`Config.Kind`). **Absent ⇒ `repo`.** A
  monorepo stays a single `repo`-kind member (one repo-wide spec stream).
- **`workspace.yml` membership manifest** — a **constrained hand-rolled subset**
  (no YAML dependency), grammar below. Returns the **full listed membership** with
  a presence flag per entry (see AC3); the `members:` list is **authoritative**.
- **`FindWorkspaceRoot(dir)`** — nearest ancestor whose `.speccraft/speccraft.toml`
  is `kind = workspace`; else returns **exactly** `FindRoot(dir)` (value and error).
  Consumed only by `arch:*` commands and the future conductor — **not** by hooks
  or the guard.
- **`speccraft-state get-status <spec-ref>`** — read-only counterpart to
  `set-status`. See AC4 for the pinned ref grammar and I/O contract.
- **`design:` frontmatter key** — read via `parseFrontmatterBlock` and exposed by a
  `speccraft-state` subcommand (AC6); an advisory, pull-only link. No referent
  resolution here (reconcile-class → Spec B).

_Intentional argument asymmetry: `get-status` takes a `<spec-ref>` (bare
`NNNN-slug`) because it performs dual live/archive **location resolution**, whereas
`get-frontmatter` takes a literal `<spec.md>` **path** because the caller already
holds one. Both are on the same binary by design._

**`workspace.yml` grammar (the entire accepted subset).** `members:` at column 0;
each entry is exactly `␣␣- path: <value>` (two-space indent, `- path:` key). After
`- path: `, the rest of the line is the raw value, from which a trailing
`␣#␣…` **inline comment** is stripped (Design 0001's example uses one), then
surrounding whitespace is trimmed. `<value>` is then either:
- **bare** — no unescaped `#` (would start a comment) and no interior whitespace; or
- **double-quoted** — `"…"` taken literally between the quotes (no escape processing).

The value must be **relative**: a leading `/` is a parse error (POSIX-absolute
rejection — this is a syntactic check only; `..` is syntactically valid, and full
path canonicalization/symlink-escape is Spec B, out of scope). An empty value
(after trim) is a parse error. Blank lines and full-line `#` comments are ignored.
**Parse error** (AC3) also on: any other top-level key, a `- path:` entry bearing
extra keys, a duplicate `members:` key, flow style (`[a, b]`), or any construct
outside this subset. A fixture table drives the tests (spec-0028/0036 fixture-first
discipline), and MUST include Design 0001's own example line
`- path: ./api      # each has its own .speccraft/` as a passing case.

## Acceptance criteria

1. **Backward compat + `kind` parsing.** `speccraft.toml` with no `kind` resolves
   to `repo` via `ReadConfig`, and the existing hook/state/guard suite passes
   **unmodified**. An **adjacent table-test pair** pins the divergence on an
   *unknown* `kind` value: `ReadConfigStrict` returns a validation error, while
   non-strict `ReadConfig` **coerces to `repo`** (mirroring `applyDefaults`) so a
   bad value can never silently promote a repo to a workspace.
2. **Root resolution.** `FindWorkspaceRoot(dir)` returns the **nearest ancestor**
   `.speccraft/` whose `kind` is `workspace`; when none exists it returns
   **exactly** `FindRoot(dir)` — same path, and the **same error** on a dir with no
   `.speccraft/`. Table cases, each with the expected return stated: repo-under-
   workspace → the workspace; **the workspace root itself → itself**; lone repo →
   `FindRoot`; no-`.speccraft` → `FindRoot`'s error; workspace-nested-in-workspace
   → nearest; and an ancestor with a **malformed `kind`** value → that ancestor is
   **not** treated as a workspace (non-strict coercion, per AC1).
3. **Membership (authoritative, presence-preserving).** The parser returns **every
   syntactically valid `- path:` entry** as a member carrying a `Present bool`
   (resolved against disk) — it **never drops** a listed member (Design 0001: the
   manifest is authoritative; a missing path is a *member* that Spec B renders as a
   `blocked` overlay). Given `members:` / `- path: ./api` / `- path: ./web` with
   only `./api` on disk, the result is exactly `[{./api, present:true}, {./web,
   present:false}]`. A repo dir physically **under** the workspace but **not listed**
   is **not** a member. Cmd-layer I/O contract (surface: `speccraft-state
   list-members`, run at/relative to a workspace root, one line per member on
   stdout as `<present|missing>\t<path>`):
   - A member with `present:false` emits a **non-fatal warning on stderr** whose
     message contains the substring `missing member` and the path; **exit 0**.
   - **Empty membership** — `members:` with **zero** entries → the empty set,
     **exit 0** (a workspace mid-setup is valid).
   - **Manifest absent** — a `kind = workspace` root with **no `workspace.yml`** →
     **exit non-zero**, stderr contains `no workspace.yml`. (`FindWorkspaceRoot` is
     unaffected — it keys only on `kind`.)
   - **Malformed manifest** (outside the grammar) → **exit non-zero**, stderr
     contains `malformed workspace.yml`.
4. **Status reader.** `speccraft-state get-status <spec-ref>`, where `<spec-ref>` is
   an `NNNN-slug` **directory name** (not a path — a deliberate, design-intent
   deviation from Design 0001's literal `<spec.md>`, since dual-location fallback
   needs a ref). Resolution, relative to the repo root: `specs/<ref>/spec.md`, else
   `specs/.archive/<ref>/spec.md`; **live wins** if both exist. Reads `status:` via
   `parseFrontmatterBlock`. **I/O contract:** on success, print exactly the bare
   status value plus a trailing newline (`<value>\n`) to **stdout**; on failure,
   print **nothing to stdout** and **exit non-zero** with stderr containing
   `not found` (neither location resolves) or `no status field` (resolved file
   lacks `status:`).
5. **Hot path untouched.** A source-level test — sibling to
   `tools/internal/speccraft/state_single_writer_test.go` — scans `hooks/` and
   `tools/cmd/speccraft-guard/` and asserts they reference **only `FindRoot`, never
   the `FindWorkspaceRoot` symbol nor a `find-workspace-root` subcommand**, so
   nothing on the Edit/Write path invokes the new resolver.
6. **`design:` extractor.** `speccraft-state get-frontmatter <spec.md> design`
   (rides the `run()` seam) reads the `design:` value via `parseFrontmatterBlock`
   and prints exactly `<value>\n` to stdout; when the key is **absent** it prints an
   **empty line** and **exits 0** — it **never errors** on a present/absent/
   nonexistent-referent value and performs **no** referent resolution (Spec B).
   (An unreadable/missing *file* is the normal non-zero error, unrelated to the key.)

## Out of scope

- The conductor / lifecycle state machine, `ledger.md`, decomposition + dispatch,
  reconcile rollup, and `/speccraft:arch:orchestrate` — **all Spec B**.
- Spawning subagents with member-scoped cwd (multi-repo dispatch) — Spec B.
- Mapping `present:false` members to a `blocked` overlay — Spec B (this spec only
  **preserves** the presence bit).
- **Resolving a `design:` referent's existence/status**, or dangling/closed notes —
  reconcile-class, Spec B.
- **Enforcing** "a workspace root has no specs of its own" — an asserted convention;
  no AC here rejects specs at a workspace root (enforcement, if any, is Spec B).
- **Member-path canonicalization**: duplicate/overlapping paths, symlink-escape,
  absolute-vs-relative beyond the grammar, trailing slashes — deferred to Spec B.
- **Arbitrary YAML** in `workspace.yml` (flow style, anchors, nested maps): only the
  constrained `members:`/`- path:` block subset is supported.
- Any behavioral change to hooks/guard beyond leaving them untouched, and
  `speccraft-state set-status` semantics (shipped in spec 0036; unchanged).

## Open questions

_none — mechanism unknowns belong to Spec B; this foundation is fully decided._
