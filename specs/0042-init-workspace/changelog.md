# Changelog — 0042 init --workspace: scaffold a workspace root

**Status:** closed · **Shipped in:** 1.13.0 · **Date:** 2026-07-29

## What shipped

A `--workspace` mode for `/speccraft:init` that scaffolds a workspace root — the
two artifacts the design-0001 conductor already *reads* but nothing *created*:
a `speccraft.toml` with `kind = "workspace"` and a parser-valid `workspace.yml`
member manifest, plus the standard `.speccraft/` set with a workspace-flavored
index. Closes the last gap in the conductor arc (0037–0041 could drive a
workspace; now you can bootstrap one).

### Surfaces

- **Two `speccraft-state` oracle subcommands** (`tools/cmd/speccraft-state/`):
  - `config-kind <dir>` — strict `ReadConfigStrict(dir).Kind`, gated on
    `.speccraft/` presence (a missing config must not coerce to `repo`).
  - `find-workspace-root` — `FindWorkspaceRoot(cwd)`; the AC1 oracle that
    discriminates a workspace root from a repo root (`list-members` cannot).
  Both ride the `run()` seam (runtime `unknown subcommand` REDs, not build
  failures) — **override budget 0**. Readers (`config.go`,
  `workspace_topology.go`, `ledger.go`) are untouched.
- **Five pure shell helpers** in `commands/init.lib.sh`: `ws_arg_parse`
  (order-independent flags, rejects unknown/positional), `ws_toml_body`
  (idempotent workspace toml; duplicate/malformed `kind` → one; explicit
  `kind = "repo"` → migration refusal), `ws_manifest_body` (canonical
  `workspace.yml`, sorted, quoted-name & `"`-skip rules), `ws_detect_members`
  (deterministic depth-1 child scan via `config-kind`), `ws_write_root`
  (manifest-before-toml ordering, preserve curated manifest, never touch ledger).
- **Workspace index template** `templates/speccraft/index.workspace.md` — carries
  the structural marker `<!-- speccraft:kind = workspace -->` + a `## Members`
  header (stack-agnostic, purity-tested).
- **`commands/init.md` wiring** — `argument-hint` → `[--workspace] [--force]`, a
  `--workspace` branch (mode parse, migration refusal, detection + per-candidate
  approval, `ws_write_root`), and the workspace index seed.

### Tests

- `tests/hooks/init-workspace.bats` — 26 bats (`ws_*` helpers + init.md
  source-scan wiring fence).
- Go: `config_kind_cmd_test.go`, `find_workspace_root_cmd_test.go`,
  workspace-index case in `template_purity_test.go`.
- `tests/e2e/workspace_init_cycle.sh` — hermetic writer→reader round-trip
  (AC1/AC2/AC3a/AC4/AC5/AC8), registered in `run.sh`.

## Spec vs shipped — deviations

- **Two new `speccraft-state` subcommands were added** beyond the spec's literal
  "changes none of those readers." They are new CLI dispatch + a `topology_cmds.go`
  helper — the readers themselves are unchanged — needed as bats/e2e oracles
  because `list-members` can't discriminate workspace from repo. Consistent with
  the spec's intent (writer-only; readers untouched).
- **Migration refusal lives at the init.md orchestration layer** (via `config-kind`
  before `.speccraft/` is created) rather than solely in `ws_toml_body`, because
  the coerces-to-repo case can't be judged from the toml body alone.
  `ws_toml_body` keeps a belt-and-braces explicit-`kind = "repo"` refusal (AC7 unit
  coverage).
- **AC3b's model-driven approval prompt** is exercised by the init.md source-scan
  fence + the deterministic e2e backing (detection/render/write); the interactive
  prompt itself is not unit-tested (credit-gated by nature).

## Follow-ups / not done

- Inline domain consolidation (close step 9) deferred: the spec stays a live silo
  under `specs/` for a later `/speccraft:sync` backfill (candidate domain:
  `state-and-config` or `plugin-foundations`).
- In-place `repo → workspace` migration remains out of scope (AC7 refuses it).
