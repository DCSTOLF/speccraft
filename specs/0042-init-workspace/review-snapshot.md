---
id: "0042"
title: "init --workspace: scaffold a workspace root"
status: draft
created: 2026-07-29
authors: [claude]
packages: ["commands", "templates/speccraft", "tools/internal/speccraft"]
related-specs: ["0037", "0038", "0039", "0040"]
informed-by: [design/0001-architect-lifecycle-orchestration]
---

# Spec 0042 — init --workspace: scaffold a workspace root

## Why

The design-0001 conductor arc (specs 0037–0041) taught the tooling to **read** a
workspace root and drive it: `ReadConfig` recognizes `kind = "workspace"`,
`FindWorkspaceRoot` resolves the nearest workspace ancestor, `ParseWorkspaceMembers`
reads the `workspace.yml` `members:` list, `ParseLedger`/`SetLedgerField` maintain
`.speccraft/ledger.md`, and `/speccraft:arch:orchestrate` drives each member through
its lifecycle. But nothing **creates** a workspace root. `/speccraft:init` only ever
produces a `repo`-kind bootstrap — it writes no `kind` field and no `workspace.yml`.

So today a user who wants to orchestrate a multi-repo workspace must hand-author
`.speccraft/speccraft.toml` with the right `kind` line and reverse-engineer the
constrained (non-YAML) `workspace.yml` grammar from the parser source — an
error-prone, undocumented step that gates the entire conductor feature. This spec
adds the missing bootstrap so a workspace root is created by the same command that
creates a repo root, completing the arc: you can now *create* the topology the
conductor already knows how to *drive*.

## What

Add a `--workspace` mode to `/speccraft:init` that scaffolds a **workspace root**:
the standard `.speccraft/` memory set plus the two artifacts the conductor reads —
a `speccraft.toml` declaring `kind = "workspace"` and a `workspace.yml` member
manifest. The mode only *writes* files that the existing 0037–0040 readers already
accept; it changes none of those readers (`config.go`, `workspace_topology.go`,
`ledger.go`).

**Decomposition.** All deterministic mechanics live in pure, sourceable helpers in
`commands/init.lib.sh` (the existing colocated lib), covered by a `bats` suite under
`tests/hooks/`; `commands/init.md` only orchestrates them and owns the interactive
approval prompt. The named helpers this spec introduces:

- `ws_toml_body` — emit the canonical workspace `speccraft.toml` text. Given existing
  content it returns it unchanged when it already declares exactly one
  `kind = "workspace"` line (preserving other keys); duplicate or malformed `kind`
  lines are normalized to a single `kind = "workspace"` (never left duplicated).
- `ws_detect_members <root>` — the deterministic child-scan (AC3a); prints approved-
  eligible candidate paths, one per line, lexicographically sorted.
- `ws_manifest_body <member>...` — render canonical `workspace.yml` text from a
  (possibly empty) member list.
- `ws_arg_parse` — recognize `--workspace`/`--force` order-independently, accept a
  repeated flag idempotently, and reject unknown flags and stray positional
  arguments with a usage error. `commands/init.md`'s frontmatter `argument-hint` is
  updated from `[--force]` to `[--workspace] [--force]` to match (spec 0015 hint
  accuracy).

**Template decision (resolves Open Question 1).** `--workspace` selects a dedicated,
stack-agnostic index template `templates/speccraft/index.workspace.md` (rather than
model-driven post-copy prose edits), so the workspace framing is deterministic and
testable. `guardrails.md`, `history.md`, and `agents.toml` reuse the shared repo
templates; `conventions.md` is seeded exactly as today (spec 0034), tolerating an
`unknown` stack. This widens scope to add one template file but keeps the readers and
the repo-kind path untouched.

**Ledger stays lazy** (the spec-0038 contract): `--workspace` does NOT write an empty
`.speccraft/ledger.md`; the first `ledger-set`/reconcile creates it when a design is
first orchestrated, and an already-present `ledger.md` is preserved on a `--force`
re-init.

## Canonical `workspace.yml` shape

`ws_manifest_body` emits exactly this (LF terminators, single trailing newline). With
no approved members the `members:` key is present but empty; approved members are
inserted as sorted `  - path: <value>` lines between `members:` and the commented
example:

```
# speccraft workspace manifest — members orchestrated by /speccraft:arch:orchestrate
members:
#  - path: relative/child-repo
```

A member path is a single filesystem path segment (a child basename, so it never
contains `/`). A bare segment is emitted unquoted; a segment containing whitespace or
`#` is emitted in the parser's double-quoted literal form (`  - path: "my repo"`); a
segment containing a `"` (unrepresentable in that grammar) is skipped with a reported
reason. `ParseWorkspaceMembers` must parse the emitted file without error in every
case.

## Acceptance criteria

1. **`kind = "workspace"` is written and round-trips.** Running
   `/speccraft:init --workspace` in a git repo with no `.speccraft/` writes
   `.speccraft/speccraft.toml` containing exactly one top-level `kind = "workspace"`
   line, such that `ReadConfig(root).Kind == "workspace"` and
   `FindWorkspaceRoot(root)` returns `root` (the root resolves as its own workspace).
   `--workspace` requires a git repository exactly as plain init does (walks up for
   `.git`, same "No git repository found" error when absent).

2. **A parser-valid canonical `workspace.yml` is written.** `--workspace` writes
   `workspace.yml` at the repo root whose bytes equal the "Canonical `workspace.yml`
   shape" above for the resolved member set, and which `ParseWorkspaceMembers` parses
   without error. With zero approved members the file has an empty `members:` set (the
   commented example line yields zero parsed members); with members it yields exactly
   the approved paths, each reported `Present`. `ws_manifest_body` is bats-tested for
   the empty, single-member, multi-member (sorted), and quoted-name cases.

3a. **Deterministic member detection (`ws_detect_members`, bats-tested).** The helper
   scans the workspace root's immediate children (depth 1 only, non-recursive) and
   emits, lexicographically sorted, each child directory `D` for which `D/.speccraft/`
   exists and `ReadConfigStrict(D)` succeeds with `Kind == "repo"` (strict read, so a
   malformed child config is a reported skip, never coerced to a candidate). It
   excludes: symlinked children, hidden dot-directories, any child with `Kind ==
   "workspace"`, and a child whose basename cannot be represented in the manifest
   grammar (contains `"`) — each exclusion reported with a reason. A `.speccraft/`
   presence is the sole membership marker; a separate `.git` is not required. Unreadable
   or permission-denied children are skipped with a reason, never aborting the scan.

3b. **Model-driven approval (e2e-covered).** `commands/init.md` presents the
   `ws_detect_members` candidates to the user for approval — mirroring the step-8a
   test-root prompt but per-candidate — and writes only approved paths into the
   manifest via `ws_manifest_body`. Declined-all or no-candidates leaves `members:`
   empty. This model-driven leg is exercised by one credit-gated e2e case; the
   deterministic seed (3a) and rendering (AC2) carry the falsifiable coverage.

4. **The ledger is not created eagerly.** After `/speccraft:init --workspace`,
   `.speccraft/ledger.md` does NOT exist — it remains lazily created by the first
   `speccraft-state ledger-set`/reconcile (spec 0038). A pre-existing `ledger.md` is
   preserved unchanged across a `--force` re-init.

5. **Workspace `index.md` carries a structural marker.** `--workspace` seeds
   `.speccraft/index.md` from `templates/speccraft/index.workspace.md`, which contains
   the structural HTML-comment marker `<!-- speccraft:kind = workspace -->` and a
   `## Members` section header (mirroring the `speccraft:test-command` marker
   convention). The acceptance predicate is the presence of that literal marker and
   header (a grep-able structural signal, per the spec-0014 structural-over-content
   rule), never model-prose content. `guardrails.md`/`history.md`/`agents.toml` reuse
   the shared templates and `conventions.md` is seeded per spec 0034 (an `unknown`
   stack yields a TODO marker, never a wrong default).

6. **Per-file preserve/overwrite matrix (resolves the `--force` policy).**
   `--workspace` obeys this matrix, and `--workspace`/`--force` are order-independent:
   - `.speccraft/` absent, no `--force`: create everything below.
   - `.speccraft/` present, no `--force`: refuse with the existing
     ".speccraft/ already exists. Use `/speccraft:init --workspace --force`" message.
   - `.speccraft/` present, `--force`: overwrite the templated memory set exactly as
     plain init does, **except** `workspace.yml` is always preserved if present
     (never clobbers a curated member list), `conventions.md` is byte-preserved
     (spec 0034), `state.json` is the idempotent `speccraft-state init`, and an
     existing `ledger.md` is preserved.
   When an existing `workspace.yml` is preserved on a `--force` re-init, member
   detection/approval (AC3a/AC3b) is skipped entirely — the curated manifest wins.

7. **`speccraft.toml` idempotency and migration refusal.** On a root whose
   `speccraft.toml` already declares `kind = "workspace"`, `--workspace` keeps exactly
   one `kind = "workspace"` line (never duplicated) and preserves any other existing
   keys (e.g. `[tdd]`). On a root whose existing `speccraft.toml` declares (or coerces
   to) `kind = "repo"`, `--workspace` REFUSES with an explicit in-place-migration
   error rather than silently rewriting the kind — consistent with the Out-of-scope
   migration exclusion. This refusal takes precedence over AC6's `--force` matrix: a
   `--force` run against an existing `kind = "repo"` root still refuses (it never
   overwrites the repo config to workspace).

8. **Repo-kind bootstrap is a targeted regression fence.** `/speccraft:init` WITHOUT
   `--workspace` writes neither a `kind = "workspace"` line in `speccraft.toml` nor a
   `workspace.yml` at the repo root. The assertion is these two grep-able absences
   (not a byte-for-byte snapshot of the whole, date- and answer-dependent scaffold).

9. **Failure ordering — no orphan workspace kind.** The single invariant ordering
   guarantees (and the only one AC9 claims): `--workspace` writes `workspace.yml`
   first and switches `speccraft.toml` to `kind = "workspace"` only after the manifest
   is on disk, so a mid-run failure can never leave a `kind = "workspace"` root
   *without* a companion manifest. The reverse residue — a `workspace.yml` present
   while `speccraft.toml` is still repo-kind/absent — is inert (the readers treat such
   a root as a repo and ignore the stray manifest) and is reconciled on the next
   `--workspace` run. A helper-level test simulates a failure after the manifest write
   and asserts the toml was not flipped (no orphan workspace kind); full two-file
   transactional atomicity is explicitly NOT claimed.

## Out of scope

- **In-place migration** of an existing populated `repo`-kind root into a workspace
  (rewriting an already-present `repo` `speccraft.toml` to `workspace`) — AC7 refuses
  this explicitly rather than performing it.
- **Any change to the readers** (`config.go`, `workspace_topology.go`, `ledger.go`).
  They already accept `kind = "workspace"`, the `workspace.yml` grammar, and the
  ledger; this spec only writes what they read.
- **`arch:*` orchestration behavior** — unchanged; this spec only produces the root
  those commands operate on.
- **Creating member repos** — each member is `init`-ed independently as its own
  `repo`-kind root; `--workspace` only lists members, never scaffolds them. A manifest
  member whose directory is later deleted is `ParseWorkspaceMembers`' presence concern
  (a `Present:false` overlay), not this command's.
- **Recursive / nested-workspace discovery** — detection scans immediate children
  only; a `kind = workspace` child is excluded, and running `--workspace` inside an
  existing workspace still creates a local root (no nested-workspace refusal in v1).

## Open questions

_none_
