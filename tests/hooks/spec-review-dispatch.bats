#!/usr/bin/env bats
# Spec 0054 — review dispatch modes, the SHELL reader half.
#
# The Go loader (Phase A, tools/internal/delegate/toml.go) and this reader must
# agree entry-for-entry (AC4). This file covers the reader itself; the shared
# parity corpus that drives both arrives in step 10.
#
# Shape follows tests/hooks/spec-review-payload.bats (same lib under test):
# PLUGIN_DIR from BATS_TEST_FILENAME, ./bin FIRST on PATH so the repo's own
# speccraft-state answers find-root, and every derived path assigned in
# setup() — a top-level assignment would expand before setup() runs.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  CORPUS="$PLUGIN_DIR/tests/hooks/fixtures/review-dispatch/registries"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# Assert a helper failed for ITS OWN reason, not on a bare "command not found"
# that a typo would also satisfy. Used for every first-touch of a new helper.
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

# assert_line / refute_line — line-exact assertions over $output.
#
# NOT `printf '%s\n' "$output" | grep -qvx X`: grep -v inverts PER LINE, so it
# succeeds whenever ANY line differs from X — it never asserts X is absent.
# NOT a bare `! grep -qx X` either: POSIX set -e ignores a command whose failure
# is negated by `!`, so the line cannot abort the test (conventions.md, and
# spec 0049 shipped three of these). These return non-zero on the failing case,
# which bats does abort on.
assert_line() {
  printf '%s\n' "$output" | grep -qx -- "$1" || {
    echo "expected a line '$1'; got: $output" >&2
    return 1
  }
}

refute_line() {
  if printf '%s\n' "$output" | grep -qx -- "$1"; then
    echo "did not expect a line '$1'; got: $output" >&2
    return 1
  fi
}

# reg <body> — write a one-entry registry and echo its path.
reg() {
  local f="$TEST_DIR/agents-$RANDOM.toml"
  printf '[defaults]\nreview_quorum = 1\n\n[[agents]]\n%s' "$1" > "$f"
  printf '%s\n' "$f"
}

# ---- AC4: key PRESENCE, the mechanism the mode reader needs ----------------
#
# review_agent_field cannot answer "was this key written?": its awk prints a
# value only `if (val != "")`, so `mode = ""` and a missing `mode` are both the
# empty string. AC1 requires telling them apart — absent normalizes to cli, an
# explicit empty is a named error — so the reader needs presence, not value.
# review_agent_keys is the shell analogue of the Go loader's agentKeySets, and
# step 11's strict-key arms need it too (a forbidden or unknown KEY is about
# presence regardless of its value).

@test "review_agent_keys lists the keys an entry actually defines" {
  source "$LIB"
  local t
  t="$(reg 'name = "a"
mode = "subagent"
model = "opus"
')"
  run review_agent_keys "$t" a
  [ "$status" -eq 0 ]
  assert_line 'name'
  assert_line 'mode'
  assert_line 'model'
  # No refute_line here: this fixture has one entry, so any "key X did not leak"
  # assertion against it could not fail. Leakage is covered below, by the test
  # with a real second entry.
}

@test "review_agent_keys distinguishes an explicitly empty value from an absent key" {
  source "$LIB"
  local empty absent
  empty="$(reg 'name = "a"
mode = ""
cmd = ["x"]
')"
  absent="$(reg 'name = "a"
cmd = ["x"]
')"

  # This is the distinction review_agent_field CANNOT make, and the reason this
  # helper exists. If it ever stops biting, review_agent_mode silently accepts
  # `mode = ""` as cli.
  run review_agent_keys "$empty" a
  [ "$status" -eq 0 ]
  assert_line 'mode'

  run review_agent_keys "$absent" a
  [ "$status" -eq 0 ]
  refute_line 'mode'
}

@test "review_agent_keys scopes to the named entry, not the whole file" {
  source "$LIB"
  local t
  t="$(reg 'name = "first"
mode = "cli"
cmd = ["x"]

[[agents]]
name = "second"
mode = "subagent"
model = "haiku"
')"
  run review_agent_keys "$t" second
  [ "$status" -eq 0 ]
  assert_line 'model'
  # `cmd` belongs to `first`; seeing it here would make every strict-key check
  # in step 11 report another entry's fields.
  refute_line 'cmd'
}

# ---- AC1/AC4: the mode reader ----------------------------------------------

@test "review_agent_mode returns each of the four valid modes" {
  source "$LIB"
  local t
  for m in cli acp codex-plugin subagent; do
    t="$(reg "name = \"a\"
mode = \"$m\"
")"
    run review_agent_mode "$t" a
    [ "$status" -eq 0 ]
    [ "$output" = "$m" ]
  done
}

@test "review_agent_mode normalizes an omitted mode to cli" {
  source "$LIB"
  local t
  t="$(reg 'name = "a"
cmd = ["codex"]
input = "stdin"
')"
  run review_agent_mode "$t" a
  [ "$status" -eq 0 ]
  [ "$output" = "cli" ]
}

@test "review_agent_mode names an error for an explicitly empty mode" {
  source "$LIB"
  local t
  t="$(reg 'name = "needle"
mode = ""
cmd = ["codex"]
')"
  run review_agent_mode "$t" needle
  assert_named_failure 'needle'
}

@test "review_agent_mode names an error for the case variants Subagent and CLI" {
  source "$LIB"
  local t
  # Case-sensitive on purpose: a permissive reader would accept "Subagent" and
  # then route on a mode no dispatcher knows.
  for m in Subagent CLI Codex-Plugin ACP; do
    t="$(reg "name = \"needle\"
mode = \"$m\"
")"
    run review_agent_mode "$t" needle
    assert_named_failure "$m"
  done
}

@test "the error names the agent and all four valid modes" {
  source "$LIB"
  local t
  t="$(reg 'name = "needle"
mode = "gpt"
')"
  run review_agent_mode "$t" needle
  [ "$status" -ne 0 ]
  # Diagnostic quality, same bar as the Go loader's assertNamesAgentAndModes:
  # an operator must be able to fix the registry without reading our source.
  for want in needle cli acp codex-plugin subagent; do
    printf '%s\n' "$output" | grep -qF -- "$want" || {
      echo "error must name '$want'; got: $output" >&2
      return 1
    }
  done
}

# ---- AC4: the shared parity corpus, driven by THIS reader ------------------
#
# tools/internal/delegate/parity_test.go drives the same corpus through the Go
# loader. Both read the same expected.txt, so a row added for one reader is
# automatically run by the other.

@test "review_agent_mode accepts every entry of the parity accept fixture" {
  source "$LIB"
  local f="$CORPUS/accept-all.toml" name
  [ -f "$f" ]
  # Every name the fixture declares must resolve to a mode, exit 0.
  for name in $(review_agent_names "$f"); do
    run review_agent_mode "$f" "$name"
    [ "$status" -eq 0 ] || {
      echo "entry '$name' of the accept fixture was rejected: $output" >&2
      return 1
    }
    case "$output" in
      cli|acp|codex-plugin|subagent) ;;
      *) echo "entry '$name' resolved to '$output', not a valid mode" >&2; return 1 ;;
    esac
  done
  # The fixture must actually carry entries, or the loop above proves nothing.
  run review_agent_names "$f"
  [ "$(printf '%s\n' "$output" | grep -c .)" -ge 4 ]
}

@test "review_agent_mode rejects every parity reject fixture with a named error" {
  source "$LIB"
  local rel verdict reason n=0
  while read -r rel verdict reason; do
    case "$rel" in ''|'#'*) continue ;; esac
    [ "$verdict" = reject ] || continue
    n=$((n + 1))
    [ -f "$CORPUS/$rel" ] || { echo "manifest names a missing fixture: $rel" >&2; return 1; }
    run review_agent_mode "$CORPUS/$rel" bad
    [ "$status" -ne 0 ] || {
      echo "$rel ($reason) must be rejected, got mode '$output'" >&2
      return 1
    }
    # Its OWN diagnostic, not a bare "command not found" or an awk crash.
    printf '%s\n' "$output" | grep -qF -- 'bad' || {
      echo "$rel: error must name the offending agent; got: $output" >&2
      return 1
    }
  done < "$CORPUS/expected.txt"
  [ "$n" -ge 11 ] || { echo "only $n reject rows were driven; expected >= 11" >&2; return 1; }
}

@test "the parity corpus covers the same reject-reason set the Go loader pins" {
  # One list, two readers. The Go half hardcodes corpusReasons so its coverage
  # check cannot be circular; this extracts THAT list and compares it to the
  # manifest, so the two halves cannot drift apart silently.
  local go_list manifest_list
  go_list="$(LC_ALL=C awk '
    /^var corpusReasons = \[\]string\{/ { inblk = 1; next }
    inblk && /^\}/                      { exit }
    inblk {
      gsub(/[",\t ]/, "")
      if (length($0)) print
    }' "$PLUGIN_DIR/tools/internal/delegate/parity_test.go" | sort)"

  manifest_list="$(LC_ALL=C awk '
    /^#/ || /^[ \t]*$/ { next }
    $2 == "reject"     { print $3 }' "$CORPUS/expected.txt" | sort)"

  [ -n "$go_list" ] || { echo "could not extract corpusReasons from parity_test.go" >&2; return 1; }
  [ "$go_list" = "$manifest_list" ] || {
    echo "the Go reason list and the manifest disagree:" >&2
    diff <(printf '%s\n' "$go_list") <(printf '%s\n' "$manifest_list") >&2 || true
    return 1
  }
}

# ---- AC12: transport selection -------------------------------------------
#
# review_agent_transport answers ONE question: which input-mode token does
# review_budget_check take for this entry? It must not change
# review_budget_check or review_dispatch_payload — spec 0052's suites for both
# stay byte-unedited, which the signature test below pins.

@test "review_agent_transport returns file for codex-plugin" {
  source "$LIB"
  local t
  t="$(reg 'name = "a"
mode = "codex-plugin"
effort = "high"
')"
  run review_agent_transport "$t" a
  [ "$status" -eq 0 ]
  [ "$output" = "file" ]
}

@test "review_agent_transport returns file for subagent" {
  source "$LIB"
  local t
  t="$(reg 'name = "a"
mode = "subagent"
model = "opus"
')"
  run review_agent_transport "$t" a
  [ "$status" -eq 0 ]
  [ "$output" = "file" ]
}

@test "review_agent_transport returns the registry input for cli and acp" {
  source "$LIB"
  local t
  t="$(reg 'name = "a"
mode = "cli"
cmd = ["codex"]
input = "stdin"
')"
  run review_agent_transport "$t" a
  [ "$status" -eq 0 ]
  [ "$output" = "stdin" ]

  t="$(reg 'name = "a"
mode = "cli"
cmd = ["codex"]
input = "argv"
')"
  run review_agent_transport "$t" a
  [ "$status" -eq 0 ]
  [ "$output" = "argv" ]

  # An acp entry carries no `input`, and must NOT fall through to stdin:
  # review_budget_check treats `acp` as argv transport precisely because
  # aux-delegator invokes it as `acpx <agent> <prompt>`, and normalizing it to
  # stdin would exempt the mode most likely to overflow.
  t="$(reg 'name = "a"
mode = "acp"
acp_agent = "codex"
')"
  run review_agent_transport "$t" a
  [ "$status" -eq 0 ]
  [ "$output" = "acp" ]
}

@test "an 80 KB payload is ok for codex-plugin and for subagent" {
  source "$LIB"
  local t
  # 81920 is over the 65536 argv limit and under the 262144 payload limit, so
  # this row is only `ok` because the transport is a file.
  for m in 'mode = "codex-plugin"' 'mode = "subagent"'; do
    t="$(reg "name = \"a\"
$m
")"
    run review_agent_transport "$t" a
    [ "$status" -eq 0 ]
    run review_budget_check 81920 "$output"
    [ "$status" -eq 0 ]
    [ "$output" = "ok" ]
  done
}

@test "the same 80 KB payload is refuse:argv-limit for cli plus argv" {
  source "$LIB"
  local t
  t="$(reg 'name = "a"
mode = "cli"
cmd = ["codex"]
input = "argv"
')"
  run review_agent_transport "$t" a
  [ "$status" -eq 0 ]
  [ "$output" = "argv" ]
  run review_budget_check 81920 "$output"
  [ "$status" -eq 0 ]
  [ "$output" = "refuse:argv-limit" ]
}

@test "review_budget_check and review_dispatch_payload keep their 0052 signatures" {
  source "$LIB"
  # Two args, unchanged: a transport helper that had to widen review_budget_check
  # would have broken every 0052 call site.
  run review_budget_check 1 stdin
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
  # An unrecognised mode is still an error, so a new argv transport cannot slip
  # in exempt.
  run review_budget_check 1 bogus
  [ "$status" -ne 0 ]

  # review_dispatch_payload still takes exactly <cmd> <mode> <artifact>.
  run grep -nE '^review_dispatch_payload\(\) \{' "$LIB"
  [ "$status" -eq 0 ]
  LC_ALL=C awk '
    /^review_dispatch_payload\(\) \{/ { inblk = 1 }
    inblk && /^  local /             { print; exit }' "$LIB" | grep -qF 'cmd' || {
    echo "review_dispatch_payload's first local no longer names cmd" >&2
    return 1
  }
}

@test "review_agent_mode reports a missing registry and an unknown agent distinctly" {
  source "$LIB"
  run review_agent_mode "$TEST_DIR/nope.toml" a
  assert_named_failure 'review_agent_mode'

  local t
  t="$(reg 'name = "a"
mode = "cli"
cmd = ["x"]
')"
  run review_agent_mode "$t" ghost
  assert_named_failure 'ghost'
}
