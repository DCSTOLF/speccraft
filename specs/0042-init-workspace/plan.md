---
spec: "0042"
status: planned
strategy: tdd
---

# Plan — 0042 init --workspace: scaffold a workspace root

## Orientation

All deterministic mechanics are PURE SHELL helpers added to
`commands/init.lib.sh` (sourceable, no side effects at source time — the
spec-0015 colocation discipline). Pure `.sh` is NOT guard-gated (conventions.md
§Bash / spec 0021), so no `/speccraft:spec:override` is ever needed for the shell
work; RED is enforced by author discipline via a new bats suite
`tests/hooks/init-workspace.bats` that fails first.

Two thin `speccraft-state` subcommands are added so the shell helpers and the
bats oracles can consult the REAL Go readers without a second parser:

- `config-kind <dir>` — the strict per-child kind reader `ws_detect_members`
  needs (`ReadConfigStrict(dir).Kind`), doubling as the AC1 `ReadConfig.Kind`
  oracle. There is no existing CLI surfacing strict `Kind` (`detect-stack` uses
  non-strict `ReadConfig` and never emits `Kind`).
- `find-workspace-root` — surfaces `FindWorkspaceRoot(cwd)` so AC1's
  "`FindWorkspaceRoot(root) == root`" is bats-verifiable. `list-members` CANNOT
  serve as this oracle: `FindWorkspaceRoot` falls back to `FindRoot` on a
  repo-kind root, so `list-members` exits 0 for BOTH kinds and does not
  discriminate `workspace` from `repo`.

Both subcommands ride the compile-stable `run()` seam in
`tools/cmd/speccraft-state/main.go`: every pre-implementation RED is a RUNTIME
`unknown subcommand: …` (exit 1), never a build failure, so the override budget
stays **0** (conventions.md §"Place fault-injectable logic … `run()` seam").
They add no change to the readers (`config.go`, `workspace_topology.go`) — only
new CLI dispatch + a `topology_cmds.go` helper.

One new stack-agnostic template `templates/speccraft/index.workspace.md` carries
the literal marker `<!-- speccraft:kind = workspace -->` and a `## Members`
header (AC5). It is guarded by a new case in the existing
`tools/internal/speccraft/template_purity_test.go`.

The credit-gated leg — `commands/init.md`'s `--workspace` branch, the
per-candidate approval prompt (AC3b), the force-matrix orchestration (AC6), and
the run-order that writes `workspace.yml` before flipping the toml (AC9
orchestration) — is exercised by `tests/e2e/run.sh`, NOT bats. The deterministic
SEED (`ws_detect_members`, AC3a) and RENDER (`ws_manifest_body`, AC2) plus the
helper-level ordering fault-injection (`ws_write_root`, AC9) carry the
falsifiable coverage per the spec-0024/0022 deterministic-seed-at-the-cheap-layer
rule.

## Test-first sequence

### Step 1 — `config-kind` subcommand oracle (RED)
- Add `tools/cmd/speccraft-state/config_kind_cmd_test.go`:
  - `Test_StateCmd_ConfigKind_Workspace_PrintsWorkspace` — a `.speccraft/speccraft.toml`
    with `kind = "workspace"` → stdout `workspace`, exit 0.
  - `Test_StateCmd_ConfigKind_Repo_PrintsRepo` — `kind = "repo"` (and absent-kind
    default) → stdout `repo`, exit 0.
  - `Test_StateCmd_ConfigKind_StrictInvalid_NonZero` — `kind = "bogus"` → non-zero,
    stderr names the file/value (rides `ReadConfigStrict` → `ErrInvalidConfig`).
  - `Test_StateCmd_ConfigKind_NoSpeccraft_NonZero` — a dir with no `.speccraft/`
    → non-zero (must NOT coerce missing-file to `repo`, which `ReadConfigStrict`
    would otherwise do).
- Tests fail: `run()` returns `unknown subcommand: config-kind` (runtime RED).

### Step 2 — implement `config-kind` (GREEN)
- Add a `case "config-kind":` to `run()` in `tools/cmd/speccraft-state/main.go`
  (dispatch to a `configKind(dir, …)` helper in
  `tools/cmd/speccraft-state/topology_cmds.go`): require `<dir>/.speccraft/` to
  exist (else non-zero), then `speccraft.ReadConfigStrict(dir)`; on error print
  it and exit 1; else print `cfg.Kind`. Add a usage line.
- All step-1 tests pass.

### Step 3 — `find-workspace-root` subcommand oracle (RED)
- Add `tools/cmd/speccraft-state/find_workspace_root_cmd_test.go`:
  - `Test_StateCmd_FindWorkspaceRoot_ReturnsSelfForWorkspaceRoot` — run in a
    `kind = "workspace"` root → stdout is that root, exit 0.
  - `Test_StateCmd_FindWorkspaceRoot_FromChildDir_ReturnsWorkspaceAncestor` — run
    from a childless plain subdir of the workspace root → stdout is the ancestor
    workspace root. Assert asymmetrically: normalize only the EXPECTED
    (`filepath.EvalSymlinks(root)`), compare the raw `got` to it (conventions.md
    §"Assert asymmetrically").
- Tests fail: `unknown subcommand: find-workspace-root` (runtime RED).

### Step 4 — implement `find-workspace-root` (GREEN)
- Add a `case "find-workspace-root":` to `run()` calling
  `speccraft.FindWorkspaceRoot("")`; print the path or the error. Add a usage
  line (peer of `find-root`).
- All step-3 tests pass.

### Step 5 — `ws_arg_parse` (RED)
- Add `tests/hooks/init-workspace.bats` (mirror `init-seed-conventions.bats`:
  `setup()` computes `PLUGIN_DIR`, puts `$PLUGIN_DIR/bin` on `PATH`, `source`s
  `commands/init.lib.sh`):
  - `@test "ws_arg_parse: --workspace alone selects workspace mode"` — stdout
    contains token `workspace`, not `force`; exit 0.
  - `@test "ws_arg_parse: --force --workspace is order-independent"` — same
    normalized tokens as `--workspace --force`.
  - `@test "ws_arg_parse: a repeated flag is idempotent"` — `--workspace
    --workspace` → single `workspace` token, exit 0.
  - `@test "ws_arg_parse: an unknown flag is rejected with a usage error"` —
    `--nope` → non-zero, stderr matches `usage`.
  - `@test "ws_arg_parse: a stray positional is rejected"` — `foo` → non-zero,
    stderr matches `usage`.
- Tests fail: `ws_arg_parse` is undefined.

### Step 6 — implement `ws_arg_parse` (GREEN)
- Add pure `ws_arg_parse` to `commands/init.lib.sh`: iterate `"$@"`, recognize
  `--workspace`/`--force` order-independently and idempotently, reject any other
  token via a central `ws_error()` usage envelope (stderr, non-zero); on success
  print the normalized flag set (e.g. `workspace` and/or `force`) to stdout.
- All step-5 tests pass. (Discharges AC6 order-independence.)

### Step 7 — `ws_toml_body` + migration refusal + AC1 round-trip (RED)
- Extend `tests/hooks/init-workspace.bats`:
  - `@test "ws_toml_body: fresh emit declares exactly one top-level kind = workspace"`
    — `ws_toml_body` (no input) stdout has exactly one `^kind = "workspace"$`
    line (`grep -c`).
  - `@test "ws_toml_body: existing single kind=workspace is returned unchanged, other keys preserved"`
    — input carrying `[tdd]` + `test_roots = [...]` and one `kind = "workspace"`
    round-trips byte-identical (the `[tdd]` block survives).
  - `@test "ws_toml_body: duplicate/malformed kind lines normalize to one kind=workspace"`
    — input with two `kind` lines (or a malformed one) → exactly one
    `kind = "workspace"`, never duplicated. (AC7 idempotency.)
  - `@test "ws_toml_body: an existing kind=repo refuses migration (non-zero, no rewrite)"`
    — input `kind = "repo"` → non-zero, stderr names in-place migration, stdout
    emits NO rewritten body. (AC7 refusal.)
  - `@test "ws_toml_body: emitted toml reads back as workspace via config-kind and find-workspace-root"`
    — write `ws_toml_body` output to `<root>/.speccraft/speccraft.toml`, then
    `speccraft-state config-kind <root>` == `workspace` AND, `cd <root> &&
    speccraft-state find-workspace-root` == `<root>`. (AC1 writer→reader
    round-trip through the REAL readers.)
- Tests fail: `ws_toml_body` is undefined.

### Step 8 — implement `ws_toml_body` (GREEN)
- Add pure `ws_toml_body` to `commands/init.lib.sh`: with no input, emit the
  canonical one-line `kind = "workspace"` body; with input, detect existing
  top-level `kind` — a single well-formed `kind = "workspace"` returns the
  content unchanged (other keys preserved); duplicate/malformed `kind` lines
  collapse to a single `kind = "workspace"`; a well-formed `kind = "repo"` exits
  non-zero via `ws_error()` (migration refusal) emitting nothing on stdout.
- All step-7 tests pass. (Discharges AC1, AC7.)

### Step 9 — `ws_manifest_body` + parser oracle (RED)
- Extend `tests/hooks/init-workspace.bats`:
  - `@test "ws_manifest_body: empty members yields an empty members: set"` —
    stdout equals the canonical header + `members:` + commented example, single
    trailing newline; zero uncommented `- path:` lines.
  - `@test "ws_manifest_body: a single member is emitted as a sorted path line"`.
  - `@test "ws_manifest_body: multiple members are emitted lexicographically sorted"`
    — pass `web api core`, assert emitted order `api core web`.
  - `@test "ws_manifest_body: a member with whitespace/# is emitted double-quoted"`
    — `my repo` → `  - path: "my repo"`.
  - `@test "ws_manifest_body: a member containing a double-quote is skipped with a reason"`
    — the bad segment is absent from stdout; stderr states the skip reason.
  - `@test "ws_manifest_body: the emitted manifest parses via speccraft-state list-members"`
    — the AC2 black-box oracle: seed `<root>/.speccraft/speccraft.toml` =
    `kind = "workspace"`, write `ws_manifest_body api "my repo"` to
    `<root>/workspace.yml`, `mkdir` those member dirs, then
    `cd <root> && speccraft-state list-members` exits 0 and prints
    `present\tapi` and `present\tmy repo` (real `ParseWorkspaceMembers`, no
    parse error). Also assert the empty-members manifest yields exit 0 with empty
    stdout.
- Tests fail: `ws_manifest_body` is undefined.

### Step 10 — implement `ws_manifest_body` (GREEN)
- Add pure `ws_manifest_body <member>...` emitting the exact canonical shape from
  spec §"Canonical `workspace.yml` shape" (LF, single trailing newline): the
  comment header, `members:`, sorted `  - path: <value>` lines inserted before
  the commented example, bare-vs-double-quoted per the parser grammar
  (`parsePathValue`), a `"`-bearing segment skipped with a stderr reason.
- All step-9 tests pass. (Discharges AC2.)

### Step 11 — `ws_detect_members` (RED)
- Extend `tests/hooks/init-workspace.bats` (build a fixture root with several
  immediate children):
  - `@test "ws_detect_members: emits repo-kind children with .speccraft, lexicographically sorted"`
    — children `api`, `core` each with `.speccraft/speccraft.toml`
    `kind = "repo"` → stdout `api\ncore` (sorted).
  - `@test "ws_detect_members: excludes a kind=workspace child with a reason"`.
  - `@test "ws_detect_members: excludes a hidden dot-directory and a symlinked child"`.
  - `@test "ws_detect_members: a strict-invalid child config is skipped with a reason, not coerced"`
    — child with `kind = "bogus"` → absent from stdout, reason on stderr
    (proves `config-kind` strict path is used, not a coerce-to-repo read).
  - `@test "ws_detect_members: a child basename containing a double-quote is skipped with a reason"`.
  - `@test "ws_detect_members: an unreadable child is skipped and the scan continues"`.
- Tests fail: `ws_detect_members` is undefined.

### Step 12 — implement `ws_detect_members` (GREEN)
- Add pure `ws_detect_members <root>`: `for` each immediate child (depth 1,
  non-recursive), skip symlinks / dot-dirs / basenames containing `"` (reason on
  stderr); require `child/.speccraft/`; call `speccraft-state config-kind
  <child>` — non-zero (strict-invalid / unreadable) → skip with reason;
  `workspace` → exclude with reason; `repo` → collect. Print the collected
  basenames lexicographically sorted (`LC_ALL=C sort`), one per line.
- All step-11 tests pass. (Discharges AC3a.)

### Step 13 — `ws_write_root` ordered writer: laziness, force-preserve, failure-ordering (RED)
- Extend `tests/hooks/init-workspace.bats`:
  - `@test "ws_write_root: writes workspace.yml BEFORE flipping the toml (a toml-write fault leaves the manifest present and the kind un-flipped)"`
    — AC9. Fault injection WITHOUT a seam: pre-create
    `<root>/.speccraft/speccraft.toml` as a DIRECTORY so the toml write fails;
    call `ws_write_root <root> api`; assert it exits non-zero, `<root>/workspace.yml`
    EXISTS (step-1 completed), and `speccraft.toml` is still a directory (never
    flipped to a `kind = "workspace"` file). If the order were reversed the toml
    write would fail first and `workspace.yml` would be absent — the assertion
    catches that.
  - `@test "ws_write_root: an existing workspace.yml is preserved byte-for-byte"`
    — AC6. Pre-write a curated `workspace.yml`, snapshot it, call `ws_write_root`;
    `cmp -s` the file is unchanged (curated member list never clobbered).
  - `@test "ws_write_root: does not eagerly create .speccraft/ledger.md"` — AC4.
    After a clean `ws_write_root`, `[ ! -e <root>/.speccraft/ledger.md ]`.
  - `@test "ws_write_root: an existing ledger.md is preserved unchanged"` — AC4.
- Tests fail: `ws_write_root` is undefined.

### Step 14 — implement `ws_write_root` (GREEN)
- Add pure `ws_write_root <root> [member...]` composing the earlier helpers in
  the AC9-mandated order: (1) if `<root>/workspace.yml` is ABSENT, render via
  `ws_manifest_body "$@"` and write it (atomic tmp+`mv`); if PRESENT, leave it
  untouched; (2) ONLY after (1) succeeds, flip `<root>/.speccraft/speccraft.toml`
  via `ws_toml_body` (reading existing content, honoring its migration refusal).
  Never touch `ledger.md`.
- All step-13 tests pass. (Discharges AC4, AC6-preserve, AC9 helper-level.)

### Step 15 — workspace index template purity + marker (RED)
- Add `Test_ShippedTemplate_WorkspaceIndex_HasMarkerMembersHeaderAndStackAgnostic`
  to `tools/internal/speccraft/template_purity_test.go`: read
  `templates/speccraft/index.workspace.md`; assert it CONTAINS the literal
  `<!-- speccraft:kind = workspace -->` and a `## Members` header; assert it
  contains NONE of the stack-specific tokens (reuse the existing `forbidden`
  list plus the repo-index leakage `internal/domain/`, `HTTP handlers`,
  `internal/store/`).
- Test fails: `templates/speccraft/index.workspace.md` does not exist yet
  (`readFile` → `t.Fatal`).

### Step 16 — create the workspace index template (GREEN)
- Create `templates/speccraft/index.workspace.md`: stack-agnostic workspace
  framing, the literal `<!-- speccraft:kind = workspace -->` marker, a
  `## Members` section, and no language/HTTP/DB idioms (guardrails §Template
  purity).
- Step-15 test passes. (Discharges AC5.)

### Step 17 — init.md wiring signals: argument-hint + AC8 branch containment (RED)
- Extend `tests/hooks/init-workspace.bats` with source-scan meta-tests over
  `commands/init.md` (spec-0032 discipline — anchor before matching):
  - `@test "init.md argument-hint advertises [--workspace] [--force]"` — the
    frontmatter `argument-hint` equals `[--workspace] [--force]` (spec 0015 hint
    accuracy).
  - `@test "init.md emits kind=workspace / workspace.yml only under the --workspace branch"`
    — AC8 containment complement: the literals `kind = "workspace"` and
    `workspace.yml` appear only within a section gated on `--workspace`, never in
    the default repo-kind file list (steps 5/12). (Light structural fence; the
    behavioral AC8 grep-absence is the e2e backstop.)
- Tests fail: `argument-hint` is still `[--force]`; the `--workspace` branch does
  not yet exist.

### Step 18 — wire `commands/init.md` (GREEN)
- Update `commands/init.md`: frontmatter `argument-hint` → `[--workspace]
  [--force]`; add the `--workspace` branch that sources `init.lib.sh`, runs
  `ws_arg_parse`, applies the AC6 per-file force matrix, runs `ws_detect_members`
  + the per-candidate approval prompt (AC3b) unless an existing `workspace.yml`
  is preserved, and calls `ws_write_root` (manifest before toml flip, AC9). The
  workspace `index.md` is seeded from `templates/speccraft/index.workspace.md`
  (AC5); `guardrails.md`/`history.md`/`agents.toml` reuse the shared templates;
  `conventions.md` continues through `seed_conventions` (spec 0034). Ledger stays
  lazy (AC4).
- Step-17 tests pass.

### Step 19 — Refactor (optional)
- Fold the shared `ws_error()` stderr/usage envelope, and any duplicated
  segment-quoting logic between `ws_manifest_body` and `ws_detect_members`, into
  a single private helper. Keep every helper pure (no source-time side effects).
- All bats + `go test ./...` stay green.

## Credit-gated e2e (NOT bats — do not unit-test the interactive prompt)

- AC3b per-candidate approval, AC6 force-matrix orchestration (workspace.yml
  preserved ⇒ detection/approval skipped), AC1 full-flow, and AC8 grep-absences
  after a PLAIN `/speccraft:init` are covered by a new sourced leg in
  `tests/e2e/run.sh` (conventions.md §"Credit-gated e2e fixtures are SOURCED").
  Assertions are STRUCTURAL only: `config-kind <root> == workspace`,
  `find-workspace-root == root`, `workspace.yml` parses via `list-members`, the
  `<!-- speccraft:kind = workspace -->` marker present, `ledger.md` absent, and —
  for the plain-init fence — `kind = "workspace"` and `workspace.yml` ABSENT. The
  approval prompt is phrased as an APPLY imperative, not propose-and-wait
  (conventions.md §"APPLY, not propose-and-wait").

## Delegation

- Steps 1–4 (Go `speccraft-state` subcommands) → the Go-focused implementer:
  they ride the `run()` seam, need a usage-line + `topology_cmds.go` helper, and
  must honor `ReadConfigStrict`'s missing-file-coerces-to-repo edge (config-kind
  must gate on `.speccraft/` presence).
- Steps 5–14, 17 (pure shell helpers + bats) → the shell/bats implementer: pure
  `.sh` is ungated, so the discipline is author-enforced RED-first; the parser
  and grammar must match `ParseWorkspaceMembers` byte-for-byte.
- Step 18 (`init.md` orchestration) + the e2e leg → the command/e2e author:
  model-driven prompt wording and the sourced-fixture host contract.

## Risk

- **`config-kind` false-positive on a `.speccraft`-less child** →
  `ReadConfigStrict` treats a MISSING file as defaults (`kind = "repo"`, no
  error), so config-kind would wrongly mark any bare dir a candidate. Mitigation:
  gate config-kind on `<dir>/.speccraft/` existence (exit non-zero if absent);
  `ws_detect_members` also stats `child/.speccraft/` before calling it (belt and
  braces). Pinned by `Test_StateCmd_ConfigKind_NoSpeccraft_NonZero`.
- **`FindWorkspaceRoot` symlink normalization on macOS** → `t.TempDir()` under
  `/var`→`/private/var`. Mitigation: assert asymmetrically (normalize only the
  expected via `EvalSymlinks`, compare raw `got`), per conventions.md.
- **Manifest grammar drift from the reader** → any mismatch between
  `ws_manifest_body`'s quoting and `parsePathValue` re-introduces the hand-authoring
  hazard the spec removes. Mitigation: the AC2 oracle runs the REAL
  `ParseWorkspaceMembers` via `list-members` over the emitted bytes (bare,
  quoted, and empty cases), not a hand-rolled shell check.
- **AC9 ordering fault-injection portability** → making `speccraft.toml` a
  directory to force the toml write to fail must fail on the toml step only, not
  the manifest step. Mitigation: `<root>` stays writable so
  `workspace.yml` succeeds; the assertion `workspace.yml present AND
  speccraft.toml still a directory` is a true order discriminator (reversed order
  ⇒ manifest absent).
- **AC8 source-scan brittleness** → the branch-containment meta-test can
  false-positive on prose edits. Mitigation: keep it a light complement; the
  authoritative AC8 signal is the e2e grep-absence after a real plain init.
