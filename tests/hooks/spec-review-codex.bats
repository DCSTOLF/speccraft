#!/usr/bin/env bats
# Spec 0054 Phase C — the codex-plugin adapter.
#
# Shape follows tests/hooks/spec-review-dispatch.bats (same lib under test):
# PLUGIN_DIR from BATS_TEST_FILENAME, ./bin FIRST on PATH, every derived path
# assigned in setup().
#
# This file starts with review_with_deadline (AC10), which bounds every single
# companion invocation. The JOB deadline is a different thing — AC6a's cancel
# path — because killing the local caller does not stop a Codex turn.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  # The adapter moved to a sibling lib at step 28. Every static guard below
  # scans BOTH files: pointed at review.lib.sh alone they passed VACUOUSLY
  # after the extraction, because the code they forbid had moved out from
  # under them. A guard that cannot see its subject is worse than no guard.
  CODEX_LIB="$PLUGIN_DIR/commands/spec/review-codex.lib.sh"
  STUB_NODE="$PLUGIN_DIR/tests/hooks/stubs/stub-node.sh"
  CODEX_FIX="$PLUGIN_DIR/tests/hooks/fixtures/review-dispatch/codex"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Assert a helper failed for ITS OWN reason, not on a bare "command not found"
# that a typo would also satisfy.
assert_named_failure() {
  local pattern="$1"
  [ "$status" -ne 0 ] || {
    echo "expected non-zero exit, got 0; output: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF -- "$pattern" || {
    echo "expected output to name '$pattern'; got: $output" >&2
    return 1
  }
}

# assert_line / refute_line — LINE-EXACT assertions over $output.
#
# Both spelled with grep -qxF plus an explicit branch, never `grep -qvx`: -v
# inverts PER LINE, so `grep -qvx needle` succeeds whenever ANY line differs
# from the needle, which is true of essentially every multi-line output and
# makes the assertion inert. A bare `! grep -q ...` is no better as a
# non-final statement under `set -e`.
assert_line() {
  printf '%s\n' "$output" | grep -qxF -- "$1" || {
    echo "expected a line exactly '$1'; got:" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
}

refute_line() {
  if printf '%s\n' "$output" | grep -qxF -- "$1"; then
    echo "did not expect a line exactly '$1'; got:" >&2
    printf '%s\n' "$output" >&2
    return 1
  fi
  return 0
}

# count_procs — how many processes currently run EXACTLY this command line.
# Matched whole-line against `ps -eo args=` rather than with `pkill -f`, which
# would also match this very test's own argv and so could never be trusted.
count_procs() {
  ps -eo args= | awk -v want="$1" '$0 == want' | wc -l | awk '{print $1}'
}

# ---------------------------------------------------------------------------
# AC10 — review_with_deadline
# ---------------------------------------------------------------------------

@test "review_with_deadline returns 124 when the deadline expires" {
  source "$LIB"
  run review_with_deadline 1 sleep 30
  [ "$status" -eq 124 ]
}

@test "review_with_deadline returns 124 within 5 s on a 30 s sleeper" {
  source "$LIB"
  local t0 t1
  t0=$(date +%s)
  run review_with_deadline 1 sleep 30
  t1=$(date +%s)
  [ "$status" -eq 124 ]
  # Wall-clock bound on the HARNESS only. It must not outlive the deadline by
  # anything like the command's own 30 s, which is what a missing kill looks
  # like from outside.
  [ "$((t1 - t0))" -lt 5 ]
}

@test "review_with_deadline leaves no process from the killed tree alive" {
  source "$LIB"
  # A marker argv unique to this test, so the count cannot collide with any
  # other sleeper on a busy CI box.
  # The `exec` wrapper is not decoration, and a bare `sleep 2531` will not do.
  # bats captures output through a pipe and holds fd 3 for its TAP stream; a
  # surviving orphan inherits both and bats then blocks forever, so a
  # regression in the kill path HANGS the suite instead of failing it. A bare
  # sleep cannot redirect its own descriptors, hence the shell that closes them
  # and then `exec`s — which keeps this a single direct child of the subshell,
  # exactly what this row means to test. Verified: with the kill recursion
  # removed, this row now reports a clean failure instead of wedging.
  local marker="sleep 2531"
  [ "$(count_procs "$marker")" -eq 0 ]
  run review_with_deadline 1 sh -c 'exec 3>&- >/dev/null 2>&1; exec sleep 2531' 3>&-
  [ "$status" -eq 124 ]
  sleep 1
  [ "$(count_procs "$marker")" -eq 0 ]
}

@test "review_with_deadline kills the whole descendant tree, not just the job it launched" {
  source "$LIB"
  # The command is a shell that spawns GRANDCHILDREN. Killing only the direct
  # child leaves these behind, which is the defect this row exists for.
  #
  # `3>&-` plus the inner `exec` is what makes a regression FAIL rather than
  # HANG. bats holds fd 3 for its TAP stream and blocks until every inheritor
  # closes it, so an orphan that outlives the subshell wedges the whole suite.
  # Closing stdout/stderr alone is NOT enough — that was the first attempt, and
  # it still hung, because fd 3 was the handle being held.
  local marker="sleep 2532"
  [ "$(count_procs "$marker")" -eq 0 ]
  run review_with_deadline 1 sh -c 'exec 3>&- >/dev/null 2>&1; sleep 2532 & sleep 2532 & sleep 2532' 3>&-
  [ "$status" -eq 124 ]
  sleep 1
  [ "$(count_procs "$marker")" -eq 0 ]
}

@test "review_with_deadline returns the command's own status when it finishes first" {
  source "$LIB"
  run review_with_deadline 5 true
  [ "$status" -eq 0 ]
}

@test "review_with_deadline preserves a non-zero command status" {
  source "$LIB"
  # 7, not 1: a function that collapsed every failure to 1 would pass a
  # 1-valued assertion while losing the companion's real exit code, and this
  # spec classifies on that exact code.
  run review_with_deadline 5 sh -c 'exit 7'
  [ "$status" -eq 7 ]
}

@test "review_with_deadline preserves a non-zero status with errexit ACTIVE" {
  # bats's `run` turns errexit OFF, so the plain status rows above cannot see
  # this defect at all: they passed with the subshell's `set +e` deleted. But
  # the .md command bodies source this lib and inherit its `set -euo pipefail`,
  # and under errexit the subshell aborts the instant the command exits
  # non-zero — before the status can be recorded — so every failing reviewer
  # would be reported as a timeout. This row runs the function the way
  # production does.
  # No `|| ...` guard here, deliberately. Appending one suspends errexit for
  # the whole left-hand side — nested functions and subshells included — so a
  # `|| printf` version of this row ALSO passed with the guard deleted. With no
  # guard, errexit is genuinely live and the function's return becomes the
  # shell's exit status, which is precisely what the command body sees.
  #
  # Correct lib: the status file is written, so 7 propagates.
  # Guard deleted: the subshell dies before writing it, the poll waits out the
  # full deadline, and 7 silently becomes 124 — a failure reported as a timeout.
  run bash -c "source '$LIB'; review_with_deadline 5 sh -c 'exit 7'"
  [ "$status" -eq 7 ]

  command -v zsh >/dev/null 2>&1 || { echo "zsh required — never silent-skip (see ci.yml)"; false; }
  run zsh -c "source '$LIB'; review_with_deadline 5 sh -c 'exit 7'"
  [ "$status" -eq 7 ]
}

@test "review_with_deadline names an error for a non-positive deadline" {
  source "$LIB"
  # The pattern must be the helper's OWN diagnostic, not just its name: the
  # shell's "command not found: review_with_deadline" contains the name too, so
  # a bare-name needle passes while the function does not exist at all. That is
  # exactly how this row false-passed when first written.
  run review_with_deadline 0 true
  assert_named_failure 'deadline must be a positive integer'
  [ "$status" -ne 124 ]

  run review_with_deadline -3 true
  assert_named_failure 'deadline must be a positive integer'

  run review_with_deadline abc true
  assert_named_failure 'deadline must be a positive integer'
}

@test "review_with_deadline emits nothing on stdout for a silent command" {
  source "$LIB"
  # The caller parses the companion's stdout, so a job-control notice or a
  # stray diagnostic leaking into it would be read as reviewer output.
  run review_with_deadline 1 sleep 30
  [ "$status" -eq 124 ]
  [ -z "$output" ]
}

@test "review_with_deadline passes the command's own stdout through unaltered" {
  source "$LIB"
  run review_with_deadline 5 printf 'hello\n'
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "review_with_deadline passes the caller's stdin through to the command" {
  source "$LIB"
  printf 'payload bytes\n' > "$TEST_DIR/in.txt"

  # Backgrounding a job redirects its stdin to /dev/null when job control is
  # off, which is always here. So the wrapper must restore stdin explicitly or
  # the command silently reads NOTHING — and this lib's stdin transport
  # (`$cmd < artifact`) would hand a reviewer an empty payload while it still
  # answered. Found when the codex launch, piped through xargs, received no
  # argv and ran `env` bare.
  run review_with_deadline 5 cat < "$TEST_DIR/in.txt"
  [ "$status" -eq 0 ]
  assert_line 'payload bytes'
}

@test "review_with_deadline passes stdin through under real zsh too" {
  source "$LIB"
  printf 'zsh bytes\n' > "$TEST_DIR/zin.txt"
  command -v zsh >/dev/null 2>&1 || { echo "zsh required — never silent-skip (see ci.yml)"; false; }

  run zsh -c "source '$LIB'; set +e; review_with_deadline 5 cat < '$TEST_DIR/zin.txt'"
  [ "$status" -eq 0 ]
  assert_line 'zsh bytes'
}

@test "review_with_deadline uses no timeout(1)" {
  # macOS has no timeout(1), so reaching for it would work in CI and fail on
  # the platform this convention exists to protect.
  run sh -c "cat '$LIB' '$CODEX_LIB' | grep -nE '(^|[^[:alnum:]_-])timeout[[:space:]]+[0-9]'"
  [ "$status" -ne 0 ]
}

@test "review_with_deadline uses no wait -n, which zsh does not support" {
  # The regression floor for a real defect: the plan prescribed that form, and
  # zsh answers it with "job not found: -n" (rc 127). The libs are sourced into
  # the caller's shell, which on macOS is zsh, so this is not hypothetical.
  #
  # Comment lines are excluded, the same scope boundary tests-portability-sweep
  # draws: the lib must be free to DOCUMENT the form it refuses to use, and the
  # first version of this guard flagged its own explanatory comment. The
  # mutation test below proves the filter did not make the guard inert.
  run sh -c "cat '$LIB' '$CODEX_LIB' | grep -vE '^[[:space:]]*#' | grep -nE 'wait[[:space:]]+-n'"
  [ "$status" -ne 0 ]
}

@test "the wait -n guard bites on an executable line" {
  # Proves the comment filter above did not render the guard inert.
  local probe="$TEST_DIR/probe.lib.sh"
  {
    echo '# a comment mentioning wait -n must NOT trip the guard'
    echo 'f() { wait -n; }'
  } > "$probe"

  run sh -c "grep -vE '^[[:space:]]*#' '$probe' | grep -nE 'wait[[:space:]]+-n'"
  [ "$status" -eq 0 ]

  # ...and with the executable line removed, the surviving comment does not.
  echo '# a comment mentioning wait -n' > "$probe"
  run sh -c "grep -vE '^[[:space:]]*#' '$probe' | grep -nE 'wait[[:space:]]+-n'"
  [ "$status" -ne 0 ]
}

@test "review_with_deadline uses no job-control option, which zsh refuses in a script" {
  # `set -m` is the other obvious route to a killable process group. zsh rejects
  # it outright in a non-interactive script ("can't change option: -m"), and a
  # lib must not change the CALLER's shell options anyway.
  run sh -c "cat '$LIB' '$CODEX_LIB' | grep -nE '^[[:space:]]*set[[:space:]]+[-+]m([[:space:]]|\$)'"
  [ "$status" -ne 0 ]
}

@test "review_with_deadline works when EXECUTED under real zsh, not merely sourced" {
  # lib-zsh-safety.bats proves every lib SOURCES under zsh. That cannot catch a
  # function whose BODY is bash-only — `wait -n` sources fine and fails at call
  # time. This leg actually runs the function under zsh.
  command -v zsh >/dev/null 2>&1 || { echo "zsh required — never silent-skip (see ci.yml)"; false; }

  # `set +e` after sourcing is required, not a convenience: the lib turns on
  # `set -e` at source time, so a 124 return would abort the zsh shell before
  # the echo could report it — which is how this row first failed, with the
  # function working correctly.
  run zsh -c "source '$LIB'; set +e; review_with_deadline 1 sleep 2533; echo \"rc=\$?\""
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'rc=124' || {
    echo "expected rc=124 under zsh; got: $output" >&2
    return 1
  }

  run zsh -c "source '$LIB'; set +e; review_with_deadline 5 sh -c 'exit 7'; echo \"rc=\$?\""
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'rc=7' || {
    echo "expected the command's own status under zsh; got: $output" >&2
    return 1
  }

  # And the tree really is reaped under zsh too, not merely reported as 124.
  sleep 1
  [ "$(count_procs "sleep 2533")" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC5 / AC5a / AC5d — review_codex_plugin_root
#
# Every row runs under a FAKE HOME and a stub `node`, never the real plugin:
# the suite must pass on a machine with no Codex plugin and no auth. The repo
# root is controlled by cd-ing into a directory outside any speccraft repo, so
# `speccraft-state find-root` fails and the lib falls back to `pwd`.
# ---------------------------------------------------------------------------

# make_companion_root <dir> [manifest-version] — a plausible plugin root.
# Always writes scripts/codex-companion.mjs. A version argument also writes the
# companion-OWNED manifest at .claude-plugin/plugin.json, which is the only
# version source for a root that installed_plugins.json has never heard of.
make_companion_root() {
  local dir="$1" version="${2:-}"
  mkdir -p "$dir/scripts"
  printf '// stub companion\n' > "$dir/scripts/codex-companion.mjs"
  if [ -n "$version" ]; then
    mkdir -p "$dir/.claude-plugin"
    printf '{ "name": "codex", "version": "%s" }\n' "$version" \
      > "$dir/.claude-plugin/plugin.json"
  fi
}

# make_bare_root <dir> — a directory that LOOKS like a root but has no
# companion. This is the companion-missing case, not not-installed.
make_bare_root() {
  mkdir -p "$1"
}

# write_installed <json-array-for-the-codex-key>
write_installed() {
  mkdir -p "$FAKE_HOME/.claude/plugins"
  printf '{ "version": 2, "plugins": { "codex@openai-codex": %s } }\n' "$1" \
    > "$FAKE_HOME/.claude/plugins/installed_plugins.json"
}

# write_registry <toml-body>
write_registry() {
  printf '%s\n' "$1" > "$TEST_DIR/agents.toml"
}

# codex_env — fake HOME, a stub `node` first on PATH, an argv log, and a cwd
# that stands in for the repo root.
codex_env() {
  FAKE_HOME="$TEST_DIR/home"
  FAKE_REPO="$TEST_DIR/repo"
  ARGV_LOG="$TEST_DIR/argv.log"
  mkdir -p "$FAKE_HOME" "$FAKE_REPO" "$TEST_DIR/bin"
  ln -sf "$STUB_NODE" "$TEST_DIR/bin/node"
  : > "$ARGV_LOG"
  export HOME="$FAKE_HOME"
  export STUB_CODEX_ARGV_LOG="$ARGV_LOG"
  export STUB_CODEX_STATE_DIR="$TEST_DIR"
  export STUB_CODEX_FIXTURE_DIR="$CODEX_FIX"
  export PATH="$TEST_DIR/bin:$PATH"
  cd "$FAKE_REPO"
}

# assert_single_reason <expected-substring> — the diagnostic must carry EXACTLY
# one of the four reason tokens. AC5 requires the two version failures to stay
# siblings: a fixture satisfying several failure conditions must still name one
# token, never a concatenation like "companion-missing unknown-version".
assert_single_reason() {
  local want="$1" n
  n="$(printf '%s\n' "$output" \
    | grep -oE 'not-installed|companion-missing|unsupported-companion|unknown-version' \
    | grep -c .)" || n=0
  [ "$n" -eq 1 ] || {
    echo "expected exactly 1 reason token, found $n in: $output" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF -- "$want" || {
    echo "expected the diagnostic to name '$want'; got: $output" >&2
    return 1
  }
}

@test "review_codex_plugin_root: an explicit plugin_root wins over installed_plugins.json" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/explicit" 1.0.6
  make_companion_root "$TEST_DIR/installed"
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/installed\", \"version\": \"1.0.6\" }]"
  write_registry "[[agents]]
name = \"codex\"
mode = \"codex-plugin\"
plugin_root = \"$TEST_DIR/explicit\""

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/explicit" ]
}

@test "review_codex_plugin_root: the local-scope entry whose projectPath is the repo root wins" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/local-root"
  make_companion_root "$TEST_DIR/user-root"
  write_installed "[
    { \"scope\": \"user\",  \"installPath\": \"$TEST_DIR/user-root\",  \"version\": \"1.0.6\" },
    { \"scope\": \"local\", \"installPath\": \"$TEST_DIR/local-root\", \"version\": \"1.0.6\", \"projectPath\": \"$FAKE_REPO\" }
  ]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/local-root" ]
}

@test "review_codex_plugin_root: a local entry for a DIFFERENT project does not win" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/local-root"
  make_companion_root "$TEST_DIR/user-root"
  write_installed "[
    { \"scope\": \"user\",  \"installPath\": \"$TEST_DIR/user-root\",  \"version\": \"1.0.6\" },
    { \"scope\": \"local\", \"installPath\": \"$TEST_DIR/local-root\", \"version\": \"1.0.6\", \"projectPath\": \"$TEST_DIR/some-other-repo\" }
  ]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/user-root" ]
}

@test "review_codex_plugin_root: otherwise the user-scope entry's installPath is used" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/user-root"
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/user-root\", \"version\": \"1.0.6\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/user-root" ]
}

@test "review_codex_plugin_root: a root without scripts/codex-companion.mjs is companion-missing" {
  source "$LIB"
  codex_env
  make_bare_root "$TEST_DIR/empty-root"
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/empty-root\", \"version\": \"1.0.6\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'companion-missing'
}

@test "review_codex_plugin_root: no codex@openai-codex entry at all is not-installed" {
  source "$LIB"
  codex_env
  write_installed '[]'
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'not-installed'
}

@test "review_codex_plugin_root: a wholly absent installed_plugins.json is not-installed" {
  source "$LIB"
  codex_env
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'not-installed'
}

@test "review_codex_plugin_root: a version below the range is unsupported-companion <version>" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/old-root"
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/old-root\", \"version\": \"1.0.5\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  # The version must appear, so an operator can see WHICH version was rejected.
  assert_single_reason 'unsupported-companion 1.0.5'
}

@test "review_codex_plugin_root: an absent version is unknown-version" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/nover-root"
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/nover-root\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'unknown-version'
}

@test "review_codex_plugin_root: an unparseable version is unknown-version" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/badver-root"
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/badver-root\", \"version\": \"not-a-version\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'unknown-version'
}

@test "review_codex_plugin_root: the reason token is exactly one of the four, never concatenated" {
  source "$LIB"
  codex_env
  # Two failure conditions at once: no companion AND an unparseable version.
  make_bare_root "$TEST_DIR/doubly-bad"
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/doubly-bad\", \"version\": \"nope\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  # assert_single_reason counts the tokens, so a concatenated
  # "companion-missing unknown-version" fails here even though it contains the
  # expected substring.
  assert_single_reason 'companion-missing'
}

@test "review_codex_plugin_root: an explicit root absent from installed_plugins.json reads its own manifest" {
  source "$LIB"
  codex_env
  # AC5d's load-bearing row. Sourcing the version only from
  # installed_plugins.json would leave this valid root permanently
  # unknown-version, with no configuration that could ever satisfy it.
  make_companion_root "$TEST_DIR/byo-root" 1.0.6
  write_installed '[]'
  write_registry "[[agents]]
name = \"codex\"
mode = \"codex-plugin\"
plugin_root = \"$TEST_DIR/byo-root\""

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/byo-root" ]
}

@test "review_codex_plugin_root: a root present in BOTH sources reads installed_plugins.json" {
  source "$LIB"
  codex_env
  # The manifest says 1.0.6; installed_plugins.json says 1.0.5. One resolution
  # path yields one version, and for a root it knows about that path is
  # installed_plugins.json — so this must be REJECTED as unsupported, not
  # accepted off the manifest.
  make_companion_root "$TEST_DIR/both-root" 1.0.6
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/both-root\", \"version\": \"1.0.5\" }]"
  write_registry "[[agents]]
name = \"codex\"
mode = \"codex-plugin\"
plugin_root = \"$TEST_DIR/both-root\""

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'unsupported-companion 1.0.5'
}

@test "review_codex_plugin_root: a root in NEITHER source is unknown-version" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/orphan-root"
  write_installed '[]'
  write_registry "[[agents]]
name = \"codex\"
mode = \"codex-plugin\"
plugin_root = \"$TEST_DIR/orphan-root\""

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'unknown-version'
}

@test "review_codex_plugin_root: a manifest present but unparseable is unknown-version" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/badmanifest-root"
  mkdir -p "$TEST_DIR/badmanifest-root/.claude-plugin"
  printf '{ this is not json\n' > "$TEST_DIR/badmanifest-root/.claude-plugin/plugin.json"
  write_installed '[]'
  write_registry "[[agents]]
name = \"codex\"
mode = \"codex-plugin\"
plugin_root = \"$TEST_DIR/badmanifest-root\""

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  assert_single_reason 'unknown-version'
}

@test "review_codex_plugin_root: 1.0.6 and above resolve, forward-compatibly" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/newer-root"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  # Each of these must be accepted; the range is open-ended above 1.0.6.
  local v
  for v in 1.0.6 1.0.7 1.0.10 1.7.0 2.0.0 10.0.0; do
    write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/newer-root\", \"version\": \"$v\" }]"
    run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
    [ "$status" -eq 0 ] || {
      echo "version $v must resolve, got: $output" >&2
      return 1
    }
  done

  # And 1.0.10 must not be read as "below 1.0.6" by a string comparison, which
  # is the classic dotted-version bug.
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/newer-root\", \"version\": \"1.0.10\" }]"
  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
}

@test "review_codex_plugin_root: versions below the range are rejected across components" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/low-root"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  local v
  for v in 0.9.9 1.0.0 1.0.5; do
    write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/low-root\", \"version\": \"$v\" }]"
    run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
    [ "$status" -ne 0 ] || {
      echo "version $v must be rejected, got exit 0" >&2
      return 1
    }
    printf '%s\n' "$output" | grep -qF "unsupported-companion $v" || {
      echo "expected 'unsupported-companion $v'; got: $output" >&2
      return 1
    }
  done
}

@test "review_codex_plugin_root: a companion whose help omits the flags still resolves" {
  source "$LIB"
  codex_env
  # AC5a. The stub's `help` prints the VERBATIM 1.0.6 usage text, which omits
  # --prompt-file, --cwd and --json even though handleTask accepts all three.
  # A help-text capability probe would therefore fail closed against the one
  # install this spec targets. This row is the regression guard.
  make_companion_root "$TEST_DIR/real-ish" 1.0.6
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/real-ish\", \"version\": \"1.0.6\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  # Sanity: the fixture really does omit the flags, or this row proves nothing.
  run grep -c -- '--prompt-file' "$CODEX_FIX/printusage-1.0.6.txt"
  [ "$output" = "0" ]

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/real-ish" ]
}

@test "review_codex_plugin_root: resolution invokes no help or --help subcommand" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/quiet-root" 1.0.6
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/quiet-root\", \"version\": \"1.0.6\" }]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]

  # The stub logs every argv it is handed. Resolution reads JSON and the
  # filesystem only, so it must not have run the companion at all.
  run grep -cE 'help' "$ARGV_LOG"
  [ "$output" = "0" ]
}

@test "review_codex_plugin_root: an unknown agent and a missing registry are named distinctly" {
  source "$LIB"
  codex_env
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" nosuchagent
  assert_named_failure 'nosuchagent'

  run review_codex_plugin_root "$TEST_DIR/nosuch.toml" codex
  assert_named_failure "$TEST_DIR/nosuch.toml"
}

# ---------------------------------------------------------------------------
# AC5b / AC5c — review_codex_preflight and its per-root memoization
# ---------------------------------------------------------------------------

# count_setup_calls — how many times the stub companion was asked to `setup`.
# The stub logs one space-joined argv per invocation, so this counts calls
# rather than inferring them.
count_setup_calls() {
  grep -c 'codex-companion.mjs setup' "$ARGV_LOG" 2>/dev/null || true
}

@test "review_codex_preflight: ready true returns zero" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/ok-root" 1.0.6

  run review_codex_preflight "$TEST_DIR/ok-root"
  [ "$status" -eq 0 ]
}

@test "review_codex_preflight: ready false is non-zero and names not-ready with the reason" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/unready-root" 1.0.6
  export STUB_CODEX_READY=0
  export STUB_CODEX_NOT_READY_WHY='Run `!codex login`.'

  run review_codex_preflight "$TEST_DIR/unready-root"
  [ "$status" -ne 0 ]
  assert_named_failure 'not-ready'
  # The reason must come FROM setup, not be invented here: it is the only
  # structured signal distinguishing "no node" from "not logged in".
  assert_named_failure 'codex login'
}

@test "review_codex_preflight: an unready companion is codex-plugin-unavailable, never codex-output-unparseable" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/unready2" 1.0.6
  export STUB_CODEX_READY=0

  run review_codex_preflight "$TEST_DIR/unready2"
  [ "$status" -ne 0 ]
  assert_named_failure 'codex-plugin-unavailable'
  # AC5b pins this explicitly. An availability problem reported as an
  # output-parse problem sends an operator looking at the reviewer's response
  # when the reviewer never ran.
  printf '%s\n' "$output" | grep -qF 'codex-output-unparseable' && {
    echo "preflight must never report codex-output-unparseable; got: $output" >&2
    return 1
  }
  return 0
}

@test "review_codex_preflight: unparseable setup output is still codex-plugin-unavailable" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/raw-root" 1.0.6
  export STUB_CODEX_SETUP_RAW='Codex is not installed. Run npm install -g @openai/codex'

  run review_codex_preflight "$TEST_DIR/raw-root"
  [ "$status" -ne 0 ]
  assert_named_failure 'codex-plugin-unavailable'
  printf '%s\n' "$output" | grep -qF 'codex-output-unparseable' && {
    echo "preflight must never report codex-output-unparseable; got: $output" >&2
    return 1
  }
  return 0
}

@test "review_codex_preflight: two calls on the same root run setup ONCE" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/memo-root" 1.0.6

  # Called DIRECTLY, not through `run`. The memo is process state, and `run`
  # evaluates its command in a subshell whose variable assignments are
  # discarded — so a `run`-based version of this row sees a fresh memo on every
  # call and reports two setup calls no matter how correct the memoization is.
  # That is how this row first failed, against a working implementation.
  local rc1=0 rc2=0
  review_codex_preflight "$TEST_DIR/memo-root" || rc1=$?
  review_codex_preflight "$TEST_DIR/memo-root" || rc2=$?
  [ "$rc1" -eq 0 ]
  [ "$rc2" -eq 0 ]

  [ "$(count_setup_calls)" -eq 1 ] || {
    echo "expected 1 setup call, got $(count_setup_calls):" >&2
    cat "$ARGV_LOG" >&2
    return 1
  }
}

@test "review_codex_preflight: two DIFFERENT roots run setup once each" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root-a" 1.0.6
  make_companion_root "$TEST_DIR/root-b" 1.0.6

  # Direct calls, so the memo is actually live across the two. Through `run`
  # this row is VACUOUS — each fork starts with an empty memo, so two setup
  # calls appear whether or not any memoization exists, and a memo that
  # collapsed all roots to one entry would still pass.
  local rc1=0 rc2=0
  review_codex_preflight "$TEST_DIR/root-a" || rc1=$?
  review_codex_preflight "$TEST_DIR/root-b" || rc2=$?
  [ "$rc1" -eq 0 ]
  [ "$rc2" -eq 0 ]

  # Per-ROUND memoization would establish readiness for one root and assume it
  # for the other. plugin_root is a per-agent field, so two agents in one round
  # can resolve to different installs, versions and auth states.
  [ "$(count_setup_calls)" -eq 2 ] || {
    echo "expected 2 setup calls (one per root), got $(count_setup_calls):" >&2
    cat "$ARGV_LOG" >&2
    return 1
  }
}

@test "review_codex_preflight: two spellings of one root via a symlink run setup ONCE" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/real-root" 1.0.6
  ln -s "$TEST_DIR/real-root" "$TEST_DIR/link-root"

  # Direct calls: see the note on the same-root row — `run` forks, so the memo
  # cannot be observed through it.
  local rc1=0 rc2=0
  review_codex_preflight "$TEST_DIR/real-root" || rc1=$?
  review_codex_preflight "$TEST_DIR/link-root" || rc2=$?
  [ "$rc1" -eq 0 ]
  [ "$rc2" -eq 0 ]

  # The memo key is formed AFTER canonicalization, so the same installation
  # reached by two names preflights once. A key on the raw string would
  # preflight twice and call it two installs.
  [ "$(count_setup_calls)" -eq 1 ] || {
    echo "expected 1 setup call across the symlinked spellings, got $(count_setup_calls):" >&2
    cat "$ARGV_LOG" >&2
    return 1
  }
}

@test "review_codex_preflight: readiness is never assumed across roots" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/ready-one" 1.0.6
  make_companion_root "$TEST_DIR/unready-one" 1.0.6
  # One root ready, the other not, in the SAME round.
  export STUB_CODEX_NOT_READY_ROOTS="$TEST_DIR/unready-one"

  # Direct calls so one memo spans both roots — this is the row that catches a
  # memo keyed loosely enough to answer for the wrong root. Through `run` the
  # memo never spans the two and the row degenerates into a test of the stub.
  local rc_ready=0 rc_unready=0 err_unready
  review_codex_preflight "$TEST_DIR/ready-one" || rc_ready=$?
  err_unready="$(review_codex_preflight "$TEST_DIR/unready-one" 2>&1 >/dev/null)" || rc_unready=$?

  [ "$rc_ready" -eq 0 ]
  [ "$rc_unready" -ne 0 ] || {
    echo "the unready root must NOT inherit the ready root's result" >&2
    return 1
  }
  printf '%s\n' "$err_unready" | grep -qF 'not-ready' || {
    echo "expected not-ready for the unready root; got: $err_unready" >&2
    return 1
  }

  # One setup per root: neither result may poison the other's memo entry.
  [ "$(count_setup_calls)" -eq 2 ] || {
    echo "expected 2 setup calls, got $(count_setup_calls):" >&2
    cat "$ARGV_LOG" >&2
    return 1
  }
}

@test "review_codex_preflight: a failed preflight is memoized too, not retried" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/sticky-bad" 1.0.6
  export STUB_CODEX_READY=0

  # Direct calls again, for the memo. Both must fail, and the second must do so
  # from the memo rather than by re-running setup.
  local rc1=0 rc2=0 err2
  review_codex_preflight "$TEST_DIR/sticky-bad" 2>/dev/null || rc1=$?
  err2="$(review_codex_preflight "$TEST_DIR/sticky-bad" 2>&1 >/dev/null)" || rc2=$?
  [ "$rc1" -ne 0 ]
  [ "$rc2" -ne 0 ]
  printf '%s\n' "$err2" | grep -qF 'not-ready' || {
    echo "the memoized failure must still name not-ready; got: $err2" >&2
    return 1
  }

  # Caching only the successes would re-run setup for every agent on a broken
  # install — the case where the companion is slowest to answer.
  [ "$(count_setup_calls)" -eq 1 ]
}

@test "review_codex_preflight: setup is invoked with --json, not the rendered form" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/json-root" 1.0.6

  run review_codex_preflight "$TEST_DIR/json-root"
  [ "$status" -eq 0 ]

  # Without --json the companion prints human text, and `ready` would have to
  # be scraped out of prose.
  run grep -qF -- 'codex-companion.mjs setup --json' "$ARGV_LOG"
  [ "$status" -eq 0 ]
}

@test "review_codex_preflight: the companion is addressed by its path under the given root" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/pathy-root" 1.0.6

  run review_codex_preflight "$TEST_DIR/pathy-root"
  [ "$status" -eq 0 ]
  run grep -qF -- "$TEST_DIR/pathy-root/scripts/codex-companion.mjs setup" "$ARGV_LOG"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# AC6 / AC7 — review_codex_task_argv
# ---------------------------------------------------------------------------

# argv_lines <toml> <agent> <root> <payload> <cwd> — run the builder and render
# its NUL-separated argv one word per line.
#
# Written through a FILE, not captured in `$(...)`: command substitution
# discards NUL bytes, so capturing the argv that way would silently merge
# adjacent words and an empty argument would vanish entirely.
argv_lines() {
  review_codex_task_argv "$1" "$2" "$3" "$4" "$5" > "$TEST_DIR/argv.nul" || return $?
  tr '\0' '\n' < "$TEST_DIR/argv.nul"
}

codex_argv_fixture() {
  make_companion_root "$TEST_DIR/root" 1.0.6
  printf 'payload bytes\n' > "$TEST_DIR/payload.md"
  write_registry "$1"
}

@test "review_codex_task_argv emits exactly the background launch argv" {
  source "$LIB"
  codex_env
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  [ "$status" -eq 0 ]

  local expected
  expected="$(printf '%s\n' \
    node \
    "$TEST_DIR/root/scripts/codex-companion.mjs" \
    task --background --fresh --json \
    --prompt-file "$TEST_DIR/payload.md" \
    --cwd "$FAKE_REPO")"

  [ "$output" = "$expected" ] || {
    echo "argv mismatch." >&2
    echo "--- want ---" >&2; printf '%s\n' "$expected" >&2
    echo "--- got ----" >&2; printf '%s\n' "$output" >&2
    return 1
  }
}

@test "review_codex_task_argv: --model appears only when the registry sets it" {
  source "$LIB"
  codex_env
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"'
  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  refute_line '--model'

  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"
model = "gpt-5.3-codex"'
  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  assert_line '--model'
  assert_line 'gpt-5.3-codex'
}

@test "review_codex_task_argv: --effort appears only when the registry sets it" {
  source "$LIB"
  codex_env
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"'
  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  refute_line '--effort'

  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"
effort = "high"'
  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  assert_line '--effort'
  assert_line 'high'
}

@test "review_codex_task_argv: --write never appears in the argv" {
  source "$LIB"
  codex_env
  # Asserted against an entry that sets every optional field, so the flag
  # cannot be absent merely because the argv is short.
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"
model = "gpt-5.3-codex"
effort = "high"'
  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  [ "$status" -eq 0 ]
  refute_line '--write'
}

@test "review_codex_task_argv: --resume never appears in the argv" {
  source "$LIB"
  codex_env
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"
model = "gpt-5.3-codex"
effort = "high"'
  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  [ "$status" -eq 0 ]
  refute_line '--resume'
}

@test "review_codex_task_argv: --resume-last never appears in the argv" {
  source "$LIB"
  codex_env
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"
model = "gpt-5.3-codex"
effort = "high"'
  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  [ "$status" -eq 0 ]
  refute_line '--resume-last'
  # --fresh is the positive counterpart: a reviewer must never inherit the
  # prior thread's context, so its ABSENCE would be the same defect.
  assert_line '--fresh'
}

@test "review_codex_task_argv: the argv is NUL-separated, so a path with spaces survives" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  mkdir -p "$TEST_DIR/a dir"
  printf 'payload\n' > "$TEST_DIR/a dir/pay load.md"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run argv_lines "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/a dir/pay load.md" "$FAKE_REPO"
  [ "$status" -eq 0 ]
  # One line, intact — not split into "pay" and "load.md", which is exactly
  # what a space-separated argv would do to the round artifact's path.
  assert_line "$TEST_DIR/a dir/pay load.md"
}

@test "review_codex_task_argv: the dispatched --prompt-file is the round artifact itself, not a copy" {
  source "$LIB"
  codex_env
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"'

  # The stub compares with `test -ef` (device+inode), never by shelling out to
  # stat with its GNU-only format flag, which the portability sweep flags.
  # A byte-identical copy therefore fails this check.
  export STUB_CODEX_EXPECT_PROMPT_FILE="$TEST_DIR/payload.md"

  review_codex_task_argv "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" \
    "$TEST_DIR/payload.md" "$FAKE_REPO" > "$TEST_DIR/argv.nul"
  # `xargs -0 env`, not a bare `xargs -0`: with no utility given, xargs
  # defaults to `echo`, so the argv would merely be printed and BOTH halves of
  # this row would pass without the companion ever running. `env` executes the
  # argv's own first word, which is what a real dispatch does.
  run xargs -0 env < "$TEST_DIR/argv.nul"
  [ "$status" -eq 0 ] || {
    echo "dispatching the built argv must hand over the artifact itself; got: $output" >&2
    return 1
  }

  # And the proof bites: pointing the builder at a COPY must be rejected.
  cp "$TEST_DIR/payload.md" "$TEST_DIR/payload-copy.md"
  review_codex_task_argv "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" \
    "$TEST_DIR/payload-copy.md" "$FAKE_REPO" > "$TEST_DIR/argv2.nul"
  run xargs -0 env < "$TEST_DIR/argv2.nul"
  [ "$status" -ne 0 ] || {
    echo "a byte-identical copy must NOT satisfy the inode proof" >&2
    return 1
  }
}

@test "review_codex_task_argv: a missing payload or an unknown agent is a named error" {
  source "$LIB"
  codex_env
  codex_argv_fixture '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_task_argv "$TEST_DIR/agents.toml" nosuchagent "$TEST_DIR/root" "$TEST_DIR/payload.md" "$FAKE_REPO"
  assert_named_failure 'nosuchagent'

  run review_codex_task_argv "$TEST_DIR/agents.toml" codex "$TEST_DIR/root" "$TEST_DIR/nope.md" "$FAKE_REPO"
  assert_named_failure "$TEST_DIR/nope.md"
}

# ---------------------------------------------------------------------------
# AC9 / AC9a — review_parse_codex_task_output
#
# Every fixture carries the NESTED background shape, .storedJob.result.*, which
# is what `result <job-id> --json` actually emits (handleResult, 1.0.6
# codex-companion.mjs:910-925; tracked-jobs.mjs:166 stores the payload one
# level down). The flat shape is the FOREGROUND payload and is rejected.
# ---------------------------------------------------------------------------

# nested_result <json-for-.storedJob.result> [outer-job-status] — a faithful
# `result --json` envelope wrapped around the given result object.
nested_result() {
  local inner="$1" outer_status="${2:-completed}"
  printf '{ "job": { "id": "task-x", "status": "%s" },\n' "$outer_status"
  printf '  "storedJob": { "id": "task-x", "status": "%s", "result": %s } }\n' \
    "$outer_status" "$inner"
}

@test "review_parse_codex_task_output: the pinned 1.0.6 success fixture yields the response" {
  source "$LIB"
  codex_env

  run review_parse_codex_task_output "$CODEX_FIX/task-success-1.0.6.json" 0
  [ "$status" -eq 0 ]
  # The response is the reviewer's own text, taken from
  # .storedJob.result.rawOutput and nothing else.
  printf '%s\n' "$output" | grep -qxF 'verdict: changes-requested' || {
    echo "expected the reviewer's verdict line; got: $output" >&2
    return 1
  }
}

@test "review_parse_codex_task_output: the response is emitted byte-for-byte, multi-line intact" {
  source "$LIB"
  codex_env
  nested_result '{ "status": 0, "rawOutput": "line one\nline two\nline three\n", "touchedFiles": [] }' \
    > "$TEST_DIR/multi.json"

  run review_parse_codex_task_output "$TEST_DIR/multi.json" 0
  [ "$status" -eq 0 ]
  assert_line 'line one'
  assert_line 'line two'
  assert_line 'line three'
}

@test "review_parse_codex_task_output: a non-zero result.status is codex-output-unparseable" {
  source "$LIB"
  codex_env
  nested_result '{ "status": 1, "rawOutput": "some text", "touchedFiles": [] }' \
    > "$TEST_DIR/rc1.json"

  run review_parse_codex_task_output "$TEST_DIR/rc1.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
}

@test "review_parse_codex_task_output: an empty rawOutput is codex-output-unparseable" {
  source "$LIB"
  codex_env
  nested_result '{ "status": 0, "rawOutput": "", "touchedFiles": [] }' \
    > "$TEST_DIR/empty.json"

  run review_parse_codex_task_output "$TEST_DIR/empty.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
}

@test "review_parse_codex_task_output: an absent rawOutput is codex-output-unparseable" {
  source "$LIB"
  codex_env
  nested_result '{ "status": 0, "touchedFiles": [] }' > "$TEST_DIR/norawout.json"

  run review_parse_codex_task_output "$TEST_DIR/norawout.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
}

@test "review_parse_codex_task_output: invalid JSON with a zero exit is codex-output-unparseable" {
  source "$LIB"
  codex_env
  printf 'this is not json\n' > "$TEST_DIR/notjson.json"

  run review_parse_codex_task_output "$TEST_DIR/notjson.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
}

@test "review_parse_codex_task_output: a non-zero exit with non-JSON stdout is codex-task-error" {
  source "$LIB"
  codex_env
  printf 'Error: codex is not authenticated\n' > "$TEST_DIR/err.txt"

  run review_parse_codex_task_output "$TEST_DIR/err.txt" 1
  [ "$status" -ne 0 ]
  assert_line 'failed codex-task-error'
}

@test "review_parse_codex_task_output: a non-zero exit with success-shaped JSON is codex-task-error" {
  source "$LIB"
  codex_env
  # THE quadrant, and the one easiest to get wrong. A companion that printed a
  # well-formed result and THEN exited non-zero had a transport failure, and a
  # transport failure never becomes a verdict. Accepting the response because
  # it "looks fine" is wrong, and so is filing it as codex-output-unparseable
  # when the output parsed perfectly well.
  nested_result '{ "status": 0, "rawOutput": "verdict: approve", "touchedFiles": [] }' \
    > "$TEST_DIR/goodjson-badexit.json"

  run review_parse_codex_task_output "$TEST_DIR/goodjson-badexit.json" 1
  [ "$status" -ne 0 ]
  assert_line 'failed codex-task-error'
  refute_line 'failed codex-output-unparseable'
  refute_line 'verdict: approve'
}

@test "review_parse_codex_task_output: non-empty touchedFiles is codex-wrote-files even with a valid verdict" {
  source "$LIB"
  codex_env
  nested_result '{ "status": 0, "rawOutput": "verdict: approve", "touchedFiles": ["src/main.go"] }' \
    > "$TEST_DIR/wrote.json"

  run review_parse_codex_task_output "$TEST_DIR/wrote.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-wrote-files'
  # A read-only reviewer that wrote is a defect, never a verdict — so the
  # verdict must not be emitted alongside it.
  refute_line 'verdict: approve'
}

@test "review_parse_codex_task_output: touchedFiles wins over a non-zero exit too" {
  source "$LIB"
  codex_env
  # The spec is explicit that touchedFiles wins over EVERY other row, so this
  # must not be reported as the transport error.
  nested_result '{ "status": 1, "rawOutput": "x", "touchedFiles": ["a.txt"] }' \
    > "$TEST_DIR/wrote2.json"

  run review_parse_codex_task_output "$TEST_DIR/wrote2.json" 1
  [ "$status" -ne 0 ]
  assert_line 'failed codex-wrote-files'
}

@test "review_parse_codex_task_output: the FLAT foreground shape is codex-output-unparseable" {
  source "$LIB"
  codex_env
  # This is the shape an earlier draft of the spec documented. It is what
  # foreground `task --json` emits, and accepting it would mean a caller that
  # forgot --background silently produced a verdict. There is no fallback, so
  # this row fails the moment one is added.
  printf '{ "status": 0, "threadId": "t", "rawOutput": "verdict: approve", "touchedFiles": [] }\n' \
    > "$TEST_DIR/flat.json"

  run review_parse_codex_task_output "$TEST_DIR/flat.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
  refute_line 'verdict: approve'
}

@test "review_parse_codex_task_output: a string result.status is never success" {
  source "$LIB"
  codex_env
  # AC9a. 1.0.6's buildResultStatus is numeric (codex.mjs:754), so this value
  # is never emitted there; the row exists so that reintroducing string-status
  # matching fails loudly instead of misrecording every review.
  nested_result '{ "status": "completed", "rawOutput": "verdict: approve", "touchedFiles": [] }' \
    > "$TEST_DIR/strstatus.json"

  run review_parse_codex_task_output "$TEST_DIR/strstatus.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
}

@test "review_parse_codex_task_output: a string-typed zero result.status is never success" {
  source "$LIB"
  codex_env
  # The sibling of the "completed" row, and the one that actually pins the TYPE
  # check. A type-blind comparison that merely stringifies .status still
  # rejects "completed" — so the "completed" row alone passes even against a
  # parser with no type check at all. Only a string that stringifies to "0"
  # separates the two, which a mutation run exposed.
  nested_result '{ "status": "0", "rawOutput": "verdict: approve", "touchedFiles": [] }' \
    > "$TEST_DIR/strzero.json"

  run review_parse_codex_task_output "$TEST_DIR/strzero.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
  refute_line 'verdict: approve'
}

@test "review_parse_codex_task_output: the right value at the wrong DEPTH is never success" {
  source "$LIB"
  codex_env
  # The depth trap. The OUTER job status is the string "completed" and that is
  # genuinely its success value, while the inner numeric status says 1. A
  # parser reading the right value at the wrong depth passes every other row
  # in this file and fails only this one.
  nested_result '{ "status": 1, "rawOutput": "verdict: approve", "touchedFiles": [] }' completed \
    > "$TEST_DIR/depth.json"

  run review_parse_codex_task_output "$TEST_DIR/depth.json" 0
  [ "$status" -ne 0 ]
  assert_line 'failed codex-output-unparseable'
  refute_line 'verdict: approve'
}

@test "review_parse_codex_task_output: a one-argument call is a named error" {
  source "$LIB"
  codex_env
  nested_result '{ "status": 0, "rawOutput": "ok", "touchedFiles": [] }' > "$TEST_DIR/one.json"

  # The classification is total over (exit status x JSON validity x fields), so
  # it cannot be computed without the status. Defaulting the second argument
  # would silently turn every transport failure into a verdict.
  run review_parse_codex_task_output "$TEST_DIR/one.json"
  assert_named_failure 'exit status'
}

@test "review_parse_codex_task_output: a missing stdout file is a named error, not a verdict" {
  source "$LIB"
  codex_env
  run review_parse_codex_task_output "$TEST_DIR/nosuch-output.json" 0
  [ "$status" -ne 0 ]
  assert_named_failure "$TEST_DIR/nosuch-output.json"
}

# ---------------------------------------------------------------------------
# AC6a / AC6b — the job lifecycle: launch, poll, result, cancel-and-confirm
#
# The job deadline is NOT review_with_deadline. The broker is spawned detached
# and unref'd, so killing the local caller proves only that the caller stopped;
# only `companion cancel <job-id>` reaches the running turn. review_with_deadline
# bounds each individual companion invocation, which is a different job.
# ---------------------------------------------------------------------------

# fn_body <file> <name> — the text of one shell function, used by the negative
# rows that must assert something about a SPECIFIC function rather than about
# the whole lib (which legitimately contains a kill, in review_with_deadline).
fn_body() {
  awk -v want="$2() {" '
    $0 == want { inside = 1; next }
    inside && /^}$/ { exit }
    inside { print }
  ' "$1"
}

# status_calls_after_cancel — how many `status` invocations the log records
# AFTER the first `cancel`. Ordering matters here, not totals: the polling
# statuses come before the cancel and the confirming one comes after.
status_calls_after_cancel() {
  awk '
    /codex-companion.mjs cancel/ { seen_cancel = 1; next }
    seen_cancel && /codex-companion.mjs status/ { n++ }
    END { print n + 0 }
  ' "$ARGV_LOG"
}

count_calls() {
  grep -c "codex-companion.mjs $1" "$ARGV_LOG" 2>/dev/null || true
}

@test "review_codex_job_id extracts the job id from the launch output" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_JOB_ID='task-abc123-xyz'

  node "$TEST_DIR/root/scripts/codex-companion.mjs" task --background --json \
    > "$TEST_DIR/launch.json"

  run review_codex_job_id "$TEST_DIR/launch.json"
  [ "$status" -eq 0 ]
  [ "$output" = "task-abc123-xyz" ]
}

@test "review_codex_job_id rejects a launch payload carrying no job id" {
  source "$LIB"
  codex_env
  # The launch payload's own `status` is the STRING "queued", which is neither
  # terminal nor a job id; a parser that reached for it would find something
  # plausible and wrong.
  printf '{ "status": "queued", "title": "x" }\n' > "$TEST_DIR/nojob.json"

  run review_codex_job_id "$TEST_DIR/nojob.json"
  [ "$status" -ne 0 ]
  assert_named_failure 'job id'
}

@test "review_codex_job_status reports the job status string" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_STATUS_SEQUENCE='running'

  run review_codex_job_status "$TEST_DIR/root" task-1 "$FAKE_REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "running" ]
}

@test "review_codex_job_result writes the companion result for the parser" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6

  run review_codex_job_result "$TEST_DIR/root" task-1 "$TEST_DIR/result.json" "$FAKE_REPO"
  [ "$status" -eq 0 ]

  # The file must be exactly what the parser expects to be handed, nested shape
  # and all — the two helpers meet here.
  run review_parse_codex_task_output "$TEST_DIR/result.json" 0
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qxF 'verdict: changes-requested'
}

@test "the poll returns as soon as the job reports terminal" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_STATUS_SEQUENCE='running running completed'
  REVIEW_CODEX_POLL_INTERVAL_S=1

  run _review_codex_poll "$TEST_DIR/root" task-1 20 "$FAKE_REPO"
  [ "$status" -eq 0 ]
  [ "$output" = "completed" ]
}

@test "the poll interval defaults to 5 seconds" {
  # Pinned statically so the tests above may shorten it without the default
  # silently drifting. AC6a fixes the interval at 5 s.
  run grep -qxF 'REVIEW_CODEX_POLL_INTERVAL_S="${REVIEW_CODEX_POLL_INTERVAL_S:-5}"' "$CODEX_LIB"
  [ "$status" -eq 0 ]
}

@test "a never-terminating job returns the deadline signal from the poll" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_STATUS_SEQUENCE='running'
  REVIEW_CODEX_POLL_INTERVAL_S=1

  run _review_codex_poll "$TEST_DIR/root" task-1 2 "$FAKE_REPO"
  [ "$status" -eq 124 ]
}

@test "the poll does not overshoot a short budget with the DEFAULT 5 s interval" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_STATUS_SEQUENCE='running'

  # AC6a's literal scenario: review_timeout_s = 2 against the real 5 s
  # interval. The last sleep must be CLAMPED to the remaining budget, or a 2 s
  # deadline takes 5 s to notice — and every reviewer's timeout is late by the
  # better part of an interval. The rows above all shorten the interval, so
  # none of them exercises the clamp; a mutation removing it passed them all.
  local t0 t1
  t0=$(date +%s)
  run _review_codex_poll "$TEST_DIR/root" task-1 2 "$FAKE_REPO"
  t1=$(date +%s)

  [ "$status" -eq 124 ]
  [ "$((t1 - t0))" -lt 4 ] || {
    echo "the poll took $((t1 - t0))s for a 2s budget; the interval was not clamped" >&2
    return 1
  }
}

@test "a never-terminating job at review_timeout_s=2 calls cancel exactly once" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_STATUS_SEQUENCE='running'
  REVIEW_CODEX_POLL_INTERVAL_S=1

  _review_codex_poll "$TEST_DIR/root" task-1 2 "$FAKE_REPO" || true
  review_codex_job_cancel "$TEST_DIR/root" task-1 "$FAKE_REPO" || true

  [ "$(count_calls cancel)" -eq 1 ] || {
    echo "expected exactly 1 cancel, got $(count_calls cancel):" >&2
    cat "$ARGV_LOG" >&2
    return 1
  }
}

@test "the deadline path makes exactly one confirming status call after cancel" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_STATUS_SEQUENCE='running'
  REVIEW_CODEX_POLL_INTERVAL_S=1

  _review_codex_poll "$TEST_DIR/root" task-1 2 "$FAKE_REPO" || true
  review_codex_job_cancel "$TEST_DIR/root" task-1 "$FAKE_REPO" || true

  # Exactly one: cancellation must be CONFIRMED, and confirming it twice would
  # mean the first answer was not trusted.
  [ "$(status_calls_after_cancel)" -eq 1 ] || {
    echo "expected 1 confirming status after cancel, got $(status_calls_after_cancel):" >&2
    cat "$ARGV_LOG" >&2
    return 1
  }
}

@test "a confirmed cancellation succeeds, so the caller can record a plain timeout" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  # The stub's default cancel is honest: the confirming status reports terminal.
  export STUB_CODEX_STATUS_SEQUENCE='cancelled'

  run review_codex_job_cancel "$TEST_DIR/root" task-1 "$FAKE_REPO"
  [ "$status" -eq 0 ]
}

@test "a cancel whose following status still reports the job active is codex-cancel-unconfirmed" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  # AC6b, and round 2's confirmed broker defect: cancel reports success while
  # the turn keeps running. A reviewer that may still be running is never
  # reported as merely timed out.
  export STUB_CODEX_CANCEL_CONFIRMS=0
  export STUB_CODEX_STATUS_SEQUENCE='running'

  run review_codex_job_cancel "$TEST_DIR/root" task-99 "$FAKE_REPO"
  [ "$status" -ne 0 ]
  assert_line 'failed codex-cancel-unconfirmed task-99'
}

@test "the job id appears in the codex-cancel-unconfirmed message" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  export STUB_CODEX_CANCEL_CONFIRMS=0
  export STUB_CODEX_STATUS_SEQUENCE='running'

  run review_codex_job_cancel "$TEST_DIR/root" task-needle-4242 "$FAKE_REPO"
  [ "$status" -ne 0 ]
  # Named so an operator can finish the job off by hand. A bare
  # "cancel unconfirmed" would leave them nothing to act on.
  printf '%s\n' "$output" | grep -qF 'task-needle-4242' || {
    echo "the message must name the job id; got: $output" >&2
    return 1
  }
}

@test "the codex-plugin job timeout path never kills a process group" {
  source "$LIB"
  # AC10's second half. The broker is detached and unref'd, so a process-group
  # kill would stop the local caller and leave the reviewer running — the exact
  # false "timeout" AC6b exists to prevent. Scoped to these two functions
  # because the lib legitimately contains a kill in review_with_deadline, which
  # bounds a single invocation rather than the job.
  local body
  body="$(fn_body "$CODEX_LIB" _review_codex_poll)$(fn_body "$CODEX_LIB" review_codex_job_cancel)"
  [ -n "$body" ] || { echo "could not extract the function bodies" >&2; return 1; }

  if printf '%s\n' "$body" | grep -qE '(^|[^[:alnum:]_])kill([[:space:]]|$)'; then
    echo "the job lifecycle must cancel, never kill:" >&2
    printf '%s\n' "$body" | grep -nE '(^|[^[:alnum:]_])kill([[:space:]]|$)' >&2
    return 1
  fi
  # And it must positively reach for cancel.
  printf '%s\n' "$body" | grep -qF 'cancel' || {
    echo "the cancel path must invoke the companion's cancel" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Spec 0055 AC3 — ONE cwd owns a job for its whole lifecycle.
#
# `review_codex_task_argv` emits `--cwd`; `review_codex_job_status`,
# `review_codex_job_result` and `review_codex_job_cancel` emitted none. The
# companion keys its job store by GIT WORKSPACE ROOT, resolved per invocation
# from `--cwd` when present and from its OWN process cwd otherwise
# (codex-companion.mjs 1.0.6, `resolveCommandCwd`: `options.cwd ?
# path.resolve(process.cwd(), options.cwd) : process.cwd()`; `status`, `result`
# and `cancel` each declare `cwd` in their valueOptions). So the launch side and
# the query side agreed only by the accident of the dispatcher being run from
# inside the repo — `_review_codex_dispatch` never cd's, and the shipped caller
# defaults its cwd to `speccraft-state find-root`, which is the repo root.
#
# Hand the dispatcher an explicit cwd anywhere else and the job becomes
# invisible to its own lifecycle: `No job found` is indistinguishable from "not
# terminal yet" to a polling adapter, so the round reports a 300 s timeout.
# ---------------------------------------------------------------------------

# codex_dispatch_registry — a one-agent codex-plugin registry plus a payload.
codex_dispatch_registry() {
  write_registry "[[agents]]
name = \"codex\"
mode = \"codex-plugin\"
plugin_root = \"$TEST_DIR/root\""
  printf 'Reply with a verdict.\n' > "$TEST_DIR/payload"
  # `_review_codex_dispatch` redirects a helper's stderr to this path and then
  # lifts the reason token out of it; the production caller
  # (`review_dispatch_agent`) mktemps it before dispatching, so a test driving
  # the dispatcher directly has to do the same or every round fails as
  # `codex-plugin-unavailable unknown` on a redirect to the empty string.
  # Exported because the mutation rows dispatch in a child shell.
  REVIEW_CODEX_LAST_ERR="$TEST_DIR/codex-last-err"
  : > "$REVIEW_CODEX_LAST_ERR"
  export REVIEW_CODEX_LAST_ERR
}

# plant_cwd_keyed_node — a `node` stub that keys its job store by `--cwd`, the
# way the real companion does.
#
# The shared stub-node.sh is cwd-BLIND: it answers `status` for any job from
# any directory, so it cannot fail the way the companion failed and cannot
# distinguish the fix from the defect. This stub resolves a store from the
# `--cwd` value, or — when the flag is ABSENT — from its own $PWD, which is
# exactly the companion's rule. A job written under one store and queried under
# another answers `No job found` on stderr with a non-zero status.
#
# Knobs: STUB_CWD_STORE (store parent), STUB_CWD_STATUS (`completed` or
# `running`), STUB_CWD_RESULT_FILE, STUB_CWD_ARGV_LOG.
plant_cwd_keyed_node() {
  # rm FIRST: codex_env left a SYMLINK here pointing at the repo's shared
  # stub-node.sh, and writing through a symlink would overwrite that file in
  # the working tree.
  rm -f "$TEST_DIR/bin/node"
  cat > "$TEST_DIR/bin/node" <<'SH'
#!/usr/bin/env sh
set -u
[ -z "${STUB_CWD_ARGV_LOG:-}" ] || printf '%s\n' "$*" >>"$STUB_CWD_ARGV_LOG"
case ${1:-} in
--version | -v)
	printf 'v20.20.2\n'
	exit 0
	;;
esac
sub=${2:-help}

# The store key: --cwd when given, else this process's own directory.
cwd=$PWD
prev=
for a in "$@"; do
	[ "$prev" = "--cwd" ] && cwd=$a
	prev=$a
done
# The cwd is absolute, so nesting it under the parent yields a unique store
# with no hashing and no non-POSIX tooling.
store="${STUB_CWD_STORE:-/tmp/stub-cwd-store}$cwd"
job=task-cwdkeyed-1

no_job() {
	printf 'No job found with id %s\n' "$job" >&2
	exit 1
}

case $sub in
setup)
	printf '{ "ready": true, "nextSteps": [] }\n'
	;;
task)
	mkdir -p "$store"
	: >"$store/job"
	printf '{ "jobId": "%s", "status": "queued" }\n' "$job"
	;;
status)
	[ -f "$store/job" ] || no_job
	st=${STUB_CWD_STATUS:-completed}
	# A cancel that reached THIS store is what makes the job cancelled; a
	# cancel that landed in another store leaves this one running, which is
	# the codex-cancel-unconfirmed path.
	[ -f "$store/cancelled" ] && st=cancelled
	printf '{ "job": { "id": "%s", "status": "%s" } }\n' "$job" "$st"
	;;
result)
	[ -f "$store/job" ] || no_job
	cat -- "$STUB_CWD_RESULT_FILE"
	;;
cancel)
	[ -f "$store/job" ] || no_job
	: >"$store/cancelled"
	printf '{ "job": { "id": "%s", "status": "cancelled" }, "cancelled": true }\n' "$job"
	;;
*)
	printf 'cwd-keyed stub: unhandled subcommand %s\n' "$sub" >&2
	exit 64
	;;
esac
exit 0
SH
  chmod +x "$TEST_DIR/bin/node"
}

# cwd_keyed_env <status> — the cwd-keyed stub wired up, with the job store and
# the result fixture in place.
cwd_keyed_env() {
  export STUB_CWD_STORE="$TEST_DIR/stores"
  export STUB_CWD_STATUS="${1:-completed}"
  export STUB_CWD_RESULT_FILE="$CODEX_FIX/task-success-1.0.6.json"
  export STUB_CWD_ARGV_LOG="$ARGV_LOG"
  plant_cwd_keyed_node
}

# argv_cwd_values <subcommand> — the `--cwd` value from every logged invocation
# of that subcommand, one per line.
argv_cwd_values() {
  grep -E "codex-companion\.mjs $1( |\$)" "$ARGV_LOG" 2>/dev/null \
    | awk '{ for (i = 1; i < NF; i++) if ($i == "--cwd") print $(i + 1) }'
}

@test "task status result and cancel all carry the dispatcher's cwd" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  codex_dispatch_registry
  cwd_keyed_env completed

  local cwd="$TEST_DIR/job-store-root"
  mkdir -p "$cwd"
  REVIEW_CODEX_POLL_INTERVAL_S=1

  # TWO dispatches, because `result` and `cancel` are mutually exclusive
  # branches of one lifecycle: a job that terminates is collected, a job that
  # outlives its budget is cancelled. Both append to the same argv log.
  _review_codex_dispatch "$TEST_DIR/agents.toml" codex "$TEST_DIR/payload" "$cwd" 10 \
    >/dev/null 2>&1 || true
  STUB_CWD_STATUS=running \
    _review_codex_dispatch "$TEST_DIR/agents.toml" codex "$TEST_DIR/payload" "$cwd" 2 \
    >/dev/null 2>&1 || true

  # `setup` is excluded deliberately: it is a readiness probe with no job store
  # behind it, so a cwd there would be noise rather than a requirement.
  local sub matched total with
  for sub in task status result cancel; do
    matched="$(grep -E "codex-companion\.mjs $sub( |\$)" "$ARGV_LOG" || true)"
    [ -n "$matched" ] || {
      echo "the two dispatches never invoked '$sub'; argv log:" >&2
      cat "$ARGV_LOG" >&2
      return 1
    }
    # Counted rather than written as a negated grep: `grep -qv` inverts PER
    # LINE and so succeeds whenever ANY line differs, which would pass here
    # for free.
    total="$(printf '%s\n' "$matched" | grep -c . || true)"
    with="$(printf '%s\n' "$matched" | grep -cF -- "--cwd $cwd" || true)"
    [ "$total" = "$with" ] || {
      echo "'$sub' ran $total times but only $with carried --cwd $cwd:" >&2
      printf '%s\n' "$matched" >&2
      return 1
    }
  done

  # …and it is the SAME cwd across all four, not merely present in each.
  local distinct
  distinct="$({ argv_cwd_values task; argv_cwd_values status
                argv_cwd_values result; argv_cwd_values cancel; } | sort -u)"
  [ "$(printf '%s\n' "$distinct" | grep -c . || true)" = "1" ] || {
    echo "the lifecycle spanned more than one cwd:" >&2
    printf '%s\n' "$distinct" >&2
    return 1
  }
  [ "$distinct" = "$cwd" ] || {
    echo "the lifecycle cwd is '$distinct', not the dispatcher's '$cwd'" >&2
    return 1
  }
}

@test "a dispatch given a cwd outside the repo still resolves its own job" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  codex_dispatch_registry
  cwd_keyed_env completed

  # A cwd outside the directory the dispatcher is running in. This is defect
  # 1's scenario, and the only configuration in which a missing `--cwd` on the
  # query side is distinguishable from a present one.
  local outside="$TEST_DIR/outside-the-repo"
  mkdir -p "$outside"
  REVIEW_CODEX_POLL_INTERVAL_S=1

  # The premise, asserted rather than assumed: if the test's own cwd were the
  # dispatch cwd, an ambient-cwd query would reach the right store by accident
  # and this row could not discriminate.
  [ "$PWD" != "$outside" ] || {
    echo "the test's cwd equals the dispatch cwd — the row is vacuous" >&2
    return 1
  }

  run _review_codex_dispatch "$TEST_DIR/agents.toml" codex "$TEST_DIR/payload" "$outside" 10
  [ "$status" -eq 0 ] || {
    echo "the dispatch could not resolve its own job from an outside cwd:" >&2
    printf '%s\n' "$output" >&2
    echo "--- argv log ---" >&2
    cat "$ARGV_LOG" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qxF 'verdict: changes-requested' || {
    echo "the round returned no verdict; got: $output" >&2
    return 1
  }
}

# codex_dispatch_in <lib-dir> <cwd> <timeout-s> — one dispatch in a CHILD shell
# sourcing the lib from <lib-dir>. Echoes the combined output, never fails.
#
# A child `bash -c` rather than a second `source` in this shell: re-sourcing a
# mutated lib over the real one leaves whichever definition ran last in place,
# so the result would depend on ordering rather than on the mutation. Each run
# starts from an empty job store, or a job left by the previous run would be
# found by the next one for the wrong reason.
codex_dispatch_in() {
  rm -rf "$TEST_DIR/stores"
  bash -c '
    . "$1/review.lib.sh"
    REVIEW_CODEX_POLL_INTERVAL_S=1
    _review_codex_dispatch "$2" codex "$3" "$4" "$5"
  ' _ "$1" "$TEST_DIR/agents.toml" "$TEST_DIR/payload" "$2" "$3" 2>&1 || true
}

# mutant_lib_dir <sed-expr> — a COPY of commands/spec/ whose
# review-codex.lib.sh has been mutated. Echoes the directory; returns 1 when
# the mutation changed nothing, which would otherwise make every negative below
# pass against the unmodified lib.
mutant_lib_dir() {
  local src="$PLUGIN_DIR/commands/spec" dir="$TEST_DIR/mutant/spec"
  rm -rf "$TEST_DIR/mutant"
  mkdir -p "$dir"
  cp "$src"/*.sh "$dir/"
  sed "$1" "$src/review-codex.lib.sh" > "$dir/review-codex.lib.sh"
  if cmp -s "$src/review-codex.lib.sh" "$dir/review-codex.lib.sh"; then
    return 1
  fi
  printf '%s\n' "$dir"
}

@test "dropping the cwd from any one post-launch codex helper fails the lifecycle row" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  codex_dispatch_registry
  cwd_keyed_env completed

  local outside="$TEST_DIR/outside-the-repo"
  mkdir -p "$outside"
  local real="$PLUGIN_DIR/commands/spec"

  # POSITIVE CONTROLS first. Three negatives that all pass because the scenario
  # itself is broken are indistinguishable from three that bite.
  local fixed_ok fixed_timeout
  fixed_ok="$(codex_dispatch_in "$real" "$outside" 10)"
  if ! printf '%s\n' "$fixed_ok" | grep -qF 'verdict:'; then
    echo "the unmutated lib produced no verdict, so the negatives prove nothing:" >&2
    printf '%s\n' "$fixed_ok" >&2
    return 1
  fi
  fixed_timeout="$(STUB_CWD_STATUS=running codex_dispatch_in "$real" "$outside" 2)"
  if ! printf '%s\n' "$fixed_timeout" | grep -qxF 'timeout'; then
    echo "the unmutated lib did not report a clean timeout plus confirmed cancel:" >&2
    printf '%s\n' "$fixed_timeout" >&2
    return 1
  fi

  # PER HELPER, so fixing two of three cannot pass.
  local dir out
  for helper in status result; do
    dir="$(mutant_lib_dir "/mjs\" $helper /s/ --cwd \"\$cwd\"//")" || {
      echo "the $helper mutation changed nothing — it emits no --cwd to remove" >&2
      return 1
    }
    out="$(codex_dispatch_in "$dir" "$outside" 10)"
    if printf '%s\n' "$out" | grep -qF 'verdict:'; then
      echo "a $helper helper with no --cwd still produced a verdict:" >&2
      printf '%s\n' "$out" >&2
      return 1
    fi
  done

  # The cancel helper only runs on a timeout, so its mutant needs the running
  # scenario. Its symptom is specific rather than merely non-zero: the cancel
  # lands in another store, so the confirming status still reports the job
  # active and the round is codex-cancel-unconfirmed rather than a timeout.
  dir="$(mutant_lib_dir '/mjs" cancel /s/ --cwd "$cwd"//')" || {
    echo "the cancel mutation changed nothing — it emits no --cwd to remove" >&2
    return 1
  }
  out="$(STUB_CWD_STATUS=running codex_dispatch_in "$dir" "$outside" 2)"
  if ! printf '%s\n' "$out" | grep -qF 'codex-cancel-unconfirmed'; then
    echo "a cancel helper with no --cwd was still recorded as a confirmed cancel:" >&2
    printf '%s\n' "$out" >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC11 — the unavailable round
# ---------------------------------------------------------------------------

# plant_codex_binary — a stub `codex` first on PATH that records being run.
# The adapter talks to the companion through `node` and must never reach for
# the codex CLI itself, so this marker must stay absent.
plant_codex_binary() {
  CODEX_MARKER="$TEST_DIR/codex-was-run"
  cat > "$TEST_DIR/bin/codex" <<SH
#!/usr/bin/env sh
printf 'ran\n' >> "$CODEX_MARKER"
exit 0
SH
  chmod +x "$TEST_DIR/bin/codex"
}

@test "an unavailable codex-plugin agent records failed codex-plugin-unavailable not-installed" {
  source "$LIB"
  codex_env
  plant_codex_binary
  write_installed '[]'
  printf 'payload\n' > "$TEST_DIR/art.md"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_dispatch_agent "$TEST_DIR/agents.toml" codex "$TEST_DIR/art.md"
  [ "$status" -ne 0 ]
  assert_line 'failed codex-plugin-unavailable not-installed'
}

@test "the other agent in an unavailable round still dispatches" {
  source "$LIB"
  codex_env
  plant_codex_binary
  write_installed '[]'
  printf 'payload bytes\n' > "$TEST_DIR/art.md"
  # Both agents in ONE registry, as a real round would have them.
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"

[[agents]]
name = "stubcli"
mode = "cli"
cmd = "cat"
input = "stdin"'

  run review_dispatch_agent "$TEST_DIR/agents.toml" codex "$TEST_DIR/art.md"
  [ "$status" -ne 0 ]

  # One unavailable reviewer must not take the round down: quorum is computed
  # from the responses that DID arrive.
  run review_dispatch_agent "$TEST_DIR/agents.toml" stubcli "$TEST_DIR/art.md"
  [ "$status" -eq 0 ]
  assert_line 'payload bytes'
}

@test "the unavailable message names /codex:setup" {
  source "$LIB"
  codex_env
  write_installed '[]'
  printf 'payload\n' > "$TEST_DIR/art.md"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_unavailable_message not-installed
  [ "$status" -eq 0 ]
  # The actionable next step, not just a diagnosis.
  printf '%s\n' "$output" | grep -qF '/codex:setup' || {
    echo "the message must name /codex:setup; got: $output" >&2
    return 1
  }
}

@test "no codex binary is executed anywhere in the codex-plugin path" {
  source "$LIB"
  codex_env
  plant_codex_binary
  make_companion_root "$TEST_DIR/root" 1.0.6
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/root\", \"version\": \"1.0.6\" }]"
  printf 'payload\n' > "$TEST_DIR/art.md"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  # Without this, the row passes while review_dispatch_agent does not exist:
  # nothing ran, so of course no codex binary ran.
  command -v review_dispatch_agent >/dev/null 2>&1 || {
    echo "review_dispatch_agent is not defined; this row would pass vacuously" >&2
    return 1
  }

  run review_dispatch_agent "$TEST_DIR/agents.toml" codex "$TEST_DIR/art.md"
  # The dispatch must actually have succeeded, or "no codex binary ran" is
  # again vacuous — a failure before launch runs nothing either.
  [ "$status" -eq 0 ] || {
    echo "the agent should dispatch successfully here; got ($status): $output" >&2
    return 1
  }

  # The adapter drives the COMPANION via node. Reaching for the codex CLI
  # directly would bypass the plugin's own auth and job bookkeeping.
  [ ! -f "$CODEX_MARKER" ] || {
    echo "a codex binary was executed:" >&2
    cat "$CODEX_MARKER" >&2
    return 1
  }
}

@test "the planted codex stub really would be caught if it ran" {
  source "$LIB"
  codex_env
  plant_codex_binary
  # Proves the row above is not passing because the stub is unreachable or
  # non-executable: invoked directly, it must leave the marker.
  codex --version >/dev/null 2>&1 || true
  [ -f "$CODEX_MARKER" ] || {
    echo "the planted stub did not record being run; the negative row is inert" >&2
    return 1
  }
}

@test "no codex exec fallback appears in the adapter" {
  # A `codex exec` fallback would review with a DIFFERENT tool under the same
  # agent name, so a round could report a codex-plugin verdict that no
  # companion ever produced. Comment lines are excluded so the lib may explain
  # the prohibition, and the row below proves the filter still bites.
  run sh -c "cat '$LIB' '$CODEX_LIB' | grep -vE '^[[:space:]]*#' | grep -nE 'codex[[:space:]]+exec'"
  [ "$status" -ne 0 ]
}

@test "the codex exec guard bites on an executable line" {
  local probe="$TEST_DIR/probe.lib.sh"
  printf '%s\n' '# a comment mentioning codex exec must not trip it' > "$probe"
  run sh -c "grep -vE '^[[:space:]]*#' '$probe' | grep -nE 'codex[[:space:]]+exec'"
  [ "$status" -ne 0 ]

  printf '%s\n' 'f() { codex exec "$1"; }' >> "$probe"
  run sh -c "grep -vE '^[[:space:]]*#' '$probe' | grep -nE 'codex[[:space:]]+exec'"
  [ "$status" -eq 0 ]
}

@test "a ready codex-plugin agent dispatches end to end and yields the response" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/root\", \"version\": \"1.0.6\" }]"
  printf 'payload\n' > "$TEST_DIR/art.md"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'
  REVIEW_CODEX_POLL_INTERVAL_S=1

  run review_dispatch_agent "$TEST_DIR/agents.toml" codex "$TEST_DIR/art.md"
  [ "$status" -eq 0 ] || {
    echo "a ready agent must dispatch; got ($status): $output" >&2
    return 1
  }
  # The response comes from .storedJob.result.rawOutput, through the whole
  # launch -> poll -> result -> parse chain.
  printf '%s\n' "$output" | grep -qxF 'verdict: changes-requested' || {
    echo "expected the reviewer's verdict; got: $output" >&2
    return 1
  }
}

@test "an unready codex-plugin agent records not-ready, not a verdict" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  write_installed "[{ \"scope\": \"user\", \"installPath\": \"$TEST_DIR/root\", \"version\": \"1.0.6\" }]"
  printf 'payload\n' > "$TEST_DIR/art.md"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'
  export STUB_CODEX_READY=0

  run review_dispatch_agent "$TEST_DIR/agents.toml" codex "$TEST_DIR/art.md"
  [ "$status" -ne 0 ]
  printf '%s\n' "$output" | grep -qF 'codex-plugin-unavailable' || {
    echo "expected codex-plugin-unavailable; got: $output" >&2
    return 1
  }
  refute_line 'verdict: changes-requested'
}

# ---------------------------------------------------------------------------
# Phase H.5 — remediation from cross-model code-review round 9.
#
# The quarantine record holds one blank-line-separated block per unresolved
# reviewer (spec 0054 T65). The resolver read only the FIRST block and then
# removed the WHOLE file on success, so a round with one finished job and one
# still running was reclaimed under the live one — exactly the failure the
# multi-block record was added to prevent, reintroduced by the function that
# consumes it. Both round-9 reviewers found it independently.
# ---------------------------------------------------------------------------

@test "the resolver removes only the blocks it resolved" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  local r="$TEST_DIR/round"
  mkdir -p "$r"
  review_round_quarantine "$r" job_first  codex-cancel-unconfirmed codex-plugin "$TEST_DIR/root"
  review_round_quarantine "$r" job_second codex-cancel-unconfirmed codex-plugin "$TEST_DIR/root"
  [ "$(grep -c '^id ' "$r/quarantine")" -eq 2 ]

  # Probed in block order, so the sequence gives block 1 a terminal status and
  # block 2 a live one.
  export STUB_CODEX_STATUS_SEQUENCE='completed running'
  run review_round_quarantine_resolve "$r"
  # Still quarantined, because one reviewer is still running.
  [ "$status" -eq 1 ]
  [ -f "$r/quarantine" ] || {
    echo "the whole record was deleted while a reviewer was still running" >&2
    return 1
  }
  grep -qF 'job_second' "$r/quarantine" || {
    echo "the LIVE job's block was lost:" >&2
    cat "$r/quarantine" >&2
    return 1
  }
  grep -qF 'job_first' "$r/quarantine" && {
    echo "the resolved job's block was retained:" >&2
    cat "$r/quarantine" >&2
    return 1
  }
  [ "$(grep -c '^id ' "$r/quarantine")" -eq 1 ]
}

@test "the resolver clears the record only when every block resolves" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  local r="$TEST_DIR/round"
  mkdir -p "$r"
  review_round_quarantine "$r" job_a codex-cancel-unconfirmed codex-plugin "$TEST_DIR/root"
  review_round_quarantine "$r" job_b codex-cancel-unconfirmed codex-plugin "$TEST_DIR/root"
  export STUB_CODEX_STATUS_SEQUENCE='completed completed'
  run review_round_quarantine_resolve "$r"
  [ "$status" -eq 0 ]
  [ ! -f "$r/quarantine" ] || {
    echo "the record survived with every block resolved:" >&2
    cat "$r/quarantine" >&2
    return 1
  }
}

@test "a subagent block is never resolved by a probe, even beside a codex one" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  local r="$TEST_DIR/round"
  mkdir -p "$r"
  review_round_quarantine "$r" job_a codex-cancel-unconfirmed codex-plugin "$TEST_DIR/root"
  review_round_quarantine "$r" agent_x subagent-stop-failed subagent
  # Even with the companion reporting terminal for the codex job, the subagent
  # block must survive: no shell-reachable API can say whether a subagent is
  # still running, so only an operator resolves it. Before the per-block
  # rewrite, resolving the codex block deleted this one too.
  export STUB_CODEX_STATUS_SEQUENCE='completed'
  run review_round_quarantine_resolve "$r"
  [ "$status" -eq 1 ]
  grep -qF 'agent_x' "$r/quarantine" || {
    echo "the subagent block was wiped by the codex probe:" >&2
    cat "$r/quarantine" >&2
    return 1
  }
  grep -qF 'job_a' "$r/quarantine" && {
    echo "the resolved codex block was retained" >&2
    return 1
  }
  return 0
}

@test "a block whose own root is missing is retained, not resolved" {
  source "$LIB"
  codex_env
  local r="$TEST_DIR/round"
  mkdir -p "$r"
  # Hand-written: review_round_quarantine refuses a codex-plugin block with no
  # root, so this is the shape a corrupted or older record would have. Probing
  # an arbitrary install is worse than refusing, so it must be kept.
  {
    printf 'id job_rootless\n'
    printf 'outcome codex-cancel-unconfirmed\n'
    printf 'mode codex-plugin\n'
    printf 'at 2026-01-01T00:00:00Z\n'
  } > "$r/quarantine"
  run review_round_quarantine_resolve "$r"
  [ "$status" -eq 1 ]
  grep -qF 'job_rootless' "$r/quarantine" || {
    echo "a block with no probe root was dropped" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'no companion root'
}

@test "the root is read PER BLOCK, not once for the whole record" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/root" 1.0.6
  # Block 1 carries a root; block 2 carries none. If the resolver read `root`
  # once — the way it read `id` and `mode` once before the per-block rewrite —
  # block 2 would be probed with block 1's root, get the companion's terminal
  # status, and resolve. Per block, it is retained with a named reason instead.
  #
  # This is the decisive shape here because the companion stub is deliberately
  # root-AGNOSTIC: it answers whatever path it is handed, so two different
  # valid roots cannot be told apart by behaviour. A MISSING field can.
  local r="$TEST_DIR/round"
  mkdir -p "$r"
  review_round_quarantine "$r" job_a codex-cancel-unconfirmed codex-plugin "$TEST_DIR/root"
  {
    printf '\n'
    printf 'id job_rootless\n'
    printf 'outcome codex-cancel-unconfirmed\n'
    printf 'mode codex-plugin\n'
    printf 'at 2026-01-01T00:00:00Z\n'
  } >> "$r/quarantine"
  export STUB_CODEX_STATUS_SEQUENCE='completed completed'
  run review_round_quarantine_resolve "$r"
  [ "$status" -eq 1 ] || {
    echo "the rootless block resolved, so it inherited block 1's root" >&2
    printf '%s\n' "$output" >&2
    return 1
  }
  grep -qF 'job_rootless' "$r/quarantine" || {
    echo "the rootless block was dropped:" >&2
    cat "$r/quarantine" >&2
    return 1
  }
  grep -qF 'job_a' "$r/quarantine" && {
    echo "block 1 was not resolved although its own root reports terminal" >&2
    cat "$r/quarantine" >&2
    return 1
  }
  printf '%s\n' "$output" | grep -qF 'no companion root'
}

# ---------------------------------------------------------------------------
# The symlinked-repo-path class, reproduced on Linux.
#
# This branch's first macOS CI run failed exactly one test:
# "the local-scope entry whose projectPath is the repo root wins". On macOS
# `$TMPDIR` lives under `/var/folders/…` and `/var` is a symlink to
# `/private/var`, so the canonicalized repo root never string-equals the
# `projectPath` Claude Code recorded — and `_review_codex_root_from_registry`
# compared a CANONICALIZED repo against a RAW projectPath inside jq, which
# cannot resolve a symlink.
#
# The consequence was not a cosmetic mismatch: a local-scope entry could never
# be selected on macOS, so resolution fell through to the USER-scope install
# and the job went to a different companion than the operator configured for
# this project — silently, which is the hazard the spec's own quarantine prose
# warns about.
#
# Reproduced here by reaching the fixture repo through a symlink, which is the
# recorded technique for this class in this repo. It bites on Linux, so the fix
# is pinned on every platform rather than only on the one CI runner that has a
# symlinked temp dir.
# ---------------------------------------------------------------------------

@test "review_codex_plugin_root: a local entry wins when the repo is reached through a symlink" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/local-root"
  make_companion_root "$TEST_DIR/user-root"

  # A second spelling of the SAME repo directory, via a symlink.
  local linked="$TEST_DIR/linked-repo"
  ln -s "$FAKE_REPO" "$linked"
  [ "$(cd "$linked" && pwd -P)" = "$(cd "$FAKE_REPO" && pwd -P)" ] || {
    echo "the symlink does not reach the same directory; row would be vacuous" >&2
    return 1
  }
  [ "$linked" != "$FAKE_REPO" ] || {
    echo "the two spellings are identical; row would be vacuous" >&2
    return 1
  }

  # projectPath recorded as the SYMLINKED spelling, which is what a user who
  # cd'd through the link would have had.
  write_installed "[
    { \"scope\": \"user\",  \"installPath\": \"$TEST_DIR/user-root\",  \"version\": \"1.0.6\" },
    { \"scope\": \"local\", \"installPath\": \"$TEST_DIR/local-root\", \"version\": \"1.0.6\", \"projectPath\": \"$linked\" }
  ]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'

  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/local-root" ] || {
    echo "the local entry lost to the user entry because the two spellings of" >&2
    echo "the repo path were compared without canonicalizing both:" >&2
    echo "  projectPath: $linked" >&2
    echo "  got:         $output" >&2
    echo "  want:        $TEST_DIR/local-root" >&2
    return 1
  }
}

@test "review_codex_plugin_root: a symlinked local entry for a DIFFERENT project still loses" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/local-root"
  make_companion_root "$TEST_DIR/user-root"
  # The converse, so canonicalizing both sides cannot have turned the match
  # into "any local entry wins".
  local other="$TEST_DIR/other-project"
  mkdir -p "$other"
  local linked="$TEST_DIR/linked-other"
  ln -s "$other" "$linked"
  write_installed "[
    { \"scope\": \"user\",  \"installPath\": \"$TEST_DIR/user-root\",  \"version\": \"1.0.6\" },
    { \"scope\": \"local\", \"installPath\": \"$TEST_DIR/local-root\", \"version\": \"1.0.6\", \"projectPath\": \"$linked\" }
  ]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'
  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/user-root" ] || {
    echo "a local entry for another project was selected: $output" >&2
    return 1
  }
}

@test "review_codex_plugin_root: the FIRST matching local entry wins, in array order" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/first-root"
  make_companion_root "$TEST_DIR/second-root"
  make_companion_root "$TEST_DIR/user-root"
  # The rewrite replaced jq's `[...][0]` with a shell loop, so array order has
  # to be preserved explicitly rather than by jq's indexing.
  write_installed "[
    { \"scope\": \"local\", \"installPath\": \"$TEST_DIR/first-root\",  \"version\": \"1.0.6\", \"projectPath\": \"$FAKE_REPO\" },
    { \"scope\": \"local\", \"installPath\": \"$TEST_DIR/second-root\", \"version\": \"1.0.6\", \"projectPath\": \"$FAKE_REPO\" },
    { \"scope\": \"user\",  \"installPath\": \"$TEST_DIR/user-root\",   \"version\": \"1.0.6\" }
  ]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'
  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/first-root" ] || {
    echo "array order was not preserved by the shell loop: got $output" >&2
    return 1
  }
}

@test "review_codex_plugin_root: a local entry with no projectPath is skipped, not matched" {
  source "$LIB"
  codex_env
  make_companion_root "$TEST_DIR/local-root"
  make_companion_root "$TEST_DIR/user-root"
  # `_review_canonical_dir ""` must not resolve to the cwd and accidentally
  # match the repo root.
  write_installed "[
    { \"scope\": \"local\", \"installPath\": \"$TEST_DIR/local-root\", \"version\": \"1.0.6\" },
    { \"scope\": \"user\",  \"installPath\": \"$TEST_DIR/user-root\",  \"version\": \"1.0.6\" }
  ]"
  write_registry '[[agents]]
name = "codex"
mode = "codex-plugin"'
  run review_codex_plugin_root "$TEST_DIR/agents.toml" codex
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_DIR/user-root" ] || {
    echo "a local entry with no projectPath was selected: $output" >&2
    return 1
  }
}
