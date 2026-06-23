# Installing speccraft

The [README quickstart](./README.md#quick-start) covers the happy path. This file
covers the full picture: helper binaries, requirements, configuration, and
troubleshooting.

## Install the plugin

In a Claude Code session:

```
/plugin marketplace add dcstolf/speccraft
/plugin install speccraft@dcstolf-tools
/reload-plugins
```

Then in your project root:

```
/speccraft:init
```

This creates `.speccraft/` and `specs/` in the repo and walks you through
personalizing the memory files.

## Helper binaries

speccraft's hooks and commands call three small Go binaries — `speccraft-state`,
`speccraft-guard`, and `speccraft-drift`. They are **downloaded automatically** the
first time speccraft runs in a session — about 5 MB, cached forever, version-stamped.
Pure Go, no C toolchain.

If the download fails (no network, corporate proxy blocking GitHub Releases, no
`curl`), you can build from source with Go ≥ 1.22:

```bash
cd "$CLAUDE_PLUGIN_ROOT" && go build ./tools/cmd/...
```

The doctor reports on the binary version stamp, network reachability, and every
dependency:

```bash
bash "$CLAUDE_PLUGIN_ROOT/scripts/doctor.sh"
```

## Requirements

**On your machine:**

- Claude Code (any recent version)
- `git`
- `jq` (for hook JSON parsing — install via your package manager)
- `curl` (for the first-run binary download)
- macOS (Apple Silicon or Intel) or Linux (x86_64 or ARM64). Windows users should
  run inside WSL.

**Optional:**

- `go` ≥ 1.22 — only needed to build helper binaries from source instead of
  downloading the release tarball.
- `acpx` — only needed if you opt into ACP-mode aux agents.
- `codex`, `opencode`, etc. — only needed if you actually call them via
  `/speccraft:spec:delegate` or `/speccraft:spec:review`.
- [CodeGraphContext](https://github.com/CodeGraphContext/CodeGraphContext) — for
  codebase-wide structural queries (see
  [Recommended companions](./docs/commands.md#recommended-companions)).
- [rtk](https://github.com/rtk-ai/rtk) — for tool-call token compression in heavy
  aux-agent workflows.

**Inside your repo:** the spec lifecycle, memory injection, and drift detection work
language-agnostically. Hook-enforced TDD supports Go, Python, TypeScript/JavaScript,
and Rust — see [Scope & limitations](./README.md#scope--limitations).

## Configuration

A few environment variables tune behavior:

| Variable | Default | Effect |
|---|---|---|
| `SPECCRAFT_TDD_MODE` | `hybrid` | `hard` (block all prod edits without spec), `hybrid` (block prod, allow tests/docs), `soft` (warn only). |
| `SPECCRAFT_REVIEW_TIMEOUT` | `600` | Seconds. Overrides the `agents.toml` default. |
| `SPECCRAFT_LOG_LEVEL` | `info` | `debug`, `info`, `warn`, `error`. |

Per-language test runners and Python `test_roots` are configured in
`.speccraft/speccraft.toml` — see [docs/architecture.md](./docs/architecture.md).

## Troubleshooting

**`speccraft-state: command not found`**
First-run binary download failed. Run `bash "$CLAUDE_PLUGIN_ROOT/scripts/doctor.sh"`
to diagnose. Common causes: no network, corporate proxy blocking GitHub Releases, no
`curl`. Fall back to building from source with Go ≥ 1.22.

**Edits to test files are being blocked**
Tests/docs/scratch should always be allowed. Check `SPECCRAFT_TDD_MODE`; if set to
`hard` it blocks all edits without an active spec. Default is `hybrid`. File a bug if
it reproduces with `hybrid`.

**`/speccraft:spec:review` reports "agent not found"**
The aux agent's CLI isn't on `PATH` in the Claude Code session's environment. Verify
with `which codex` / `which opencode`. If the binary is in a non-default location, add
it to `PATH` in your shell rc *and* restart Claude Code (it inherits the shell's
environment at launch).

**TDD invariant blocks an edit but I did write a test**
The rule depends on the language:
- **Go:** same-directory `pkg/foo/*_test.go` sibling required. Tests in a different
  package don't satisfy it.
- **Python:** same-directory siblings (`test_*.py`, `*_test.py`) first; falls back to
  walking the roots in `.speccraft/speccraft.toml`'s `[tdd] test_roots = [...]`.
- **TypeScript/JavaScript:** a sibling `*.test.<ext>` / `*.spec.<ext>` or a
  `__tests__/` file, plus an observed failing test in the session.
- **Rust:** delta-based. The guard checks whether the edit adds a new canonical test
  ID; if it does, the runner is invoked to confirm the test fails. Run
  `speccraft-state rust-baseline recapture` to reset the baseline if you started
  speccraft on a crate that already had failing tests.

For one-off bypasses use `/speccraft:spec:override "<reason>"`; for unsupported
languages set `SPECCRAFT_TDD_MODE=soft` to convert blocks to warnings.

**`/speccraft:init` doesn't update `.gitignore`**
Likely the `.gitignore` already had a conflicting `.speccraft/` line. Check and
reconcile manually; speccraft is conservative about overwriting existing patterns.

**Hooks don't seem to fire**
Run `/plugin` to verify speccraft is Enabled. Check that `hooks/hooks.json` exists in
the plugin install. Hooks may be globally disabled by your Claude Code config — check
`~/.claude/settings.json` for `"hooks": false` or matcher overrides.

**The doctor**
When in doubt, `bash "$CLAUDE_PLUGIN_ROOT/scripts/doctor.sh"` reports on every
dependency, the binary version stamp, network reachability, and configured aux agents.
