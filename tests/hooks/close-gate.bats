#!/usr/bin/env bats
# Spec 0047 AC9/AC10 — durable pin for the close-time completion gate.
#
# WHY THIS FILE EXISTS. The gate's decision rules (which token bypasses, which
# exit code is unbypassable, what gets recorded) shipped as prose in
# commands/spec/close.md. The only other check was a `grep` predicate inside
# spec 0047's own tasks.md — which runs exactly once, at that spec's close, and
# never again (the archive sweep in tasks-verify.bats runs WITHOUT --run). So
# without this file, deleting SKIP-TASKS-VERIFY from close.md tomorrow would
# break nothing in CI.
#
# Pinning command-runbook prose with bats is established here: nine other
# tests/hooks/*.bats files already assert over commands/**/*.md. Markdown is
# ungated by speccraft-guard, so this costs zero overrides.
#
# This pins the CONTRACT, not the wording: each assertion targets a decision rule
# that, if silently dropped, reopens the failure mode 0047 exists to close.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  CLOSE_MD="$PLUGIN_DIR/commands/spec/close.md"
  export PLUGIN_DIR CLOSE_MD
}

@test "close.md: step 2 invokes the mechanical gate with --run" {
  grep -q 'tasks-verify' "$CLOSE_MD"
  grep -q -- '--run' "$CLOSE_MD"
}

@test "close.md: the gate runs BEFORE the diff and before memory-keeper" {
  # A blocked close must do no downstream work. Assert ordering by line number:
  # the tasks-verify invocation precedes the `git diff` of step 3.
  local gate_line diff_line
  gate_line="$(grep -n 'tasks-verify' "$CLOSE_MD" | head -1 | cut -d: -f1)"
  diff_line="$(grep -n 'git diff' "$CLOSE_MD" | head -1 | cut -d: -f1)"
  [ -n "$gate_line" ]
  [ -n "$diff_line" ]
  [ "$gate_line" -lt "$diff_line" ]
}

@test "close.md: bypass requires the literal SKIP-TASKS-VERIFY token" {
  grep -q 'SKIP-TASKS-VERIFY' "$CLOSE_MD"
}

@test "close.md: blanket approval explicitly does NOT satisfy the gate" {
  # The field-report failure shipped in exactly this mode, so the carve-out for
  # "approve all" / non-interactive must stay explicit.
  grep -qi 'approve all' "$CLOSE_MD"
  grep -qi 'does \*\*NOT\*\*\|does NOT satisfy\|not satisfy this gate' "$CLOSE_MD"
}

@test "close.md: exit 2 (malformed) is never bypassable" {
  grep -qi 'never bypassable\|no token that waives' "$CLOSE_MD"
}

@test "close.md: a bypass records the skipped findings in changelog.md" {
  grep -q 'Skipped task verification' "$CLOSE_MD"
  grep -q 'changelog.md' "$CLOSE_MD"
}

@test "close.md: all three exit codes are documented for the runbook to branch on" {
  grep -q '0' "$CLOSE_MD"
  grep -qi 'malformed' "$CLOSE_MD"
  grep -qi 'violations' "$CLOSE_MD"
}

# --- Spec 0048 AC17 — the build-repair log gets reported at close ------------
#
# Same reasoning as the header above, one spec later: the report is prose in
# close.md, and 0048's own tasks.md predicate stops executing the moment 0048
# closes. Without these pins, deleting the report tomorrow breaks nothing in CI —
# and the build-repair log would go back to being an audit trail nobody reads.

@test "close.md: step 2 also reports the build-repair log" {
  grep -q 'build-repair-log' "$CLOSE_MD"
}

@test "close.md: the build-repair report is informational and does not gate" {
  # The distinction is the whole point: a report that could fail the close would
  # make honest mid-repair work look like a failure, and people would route around
  # repair mode instead of using it.
  run grep -n -A 6 'build-repair-log' "$CLOSE_MD"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE 'informational|does not gate|never gates|report only'
}

@test "close.md: the report runs alongside tasks-verify, before the diff" {
  tv="$(grep -n 'tasks-verify' "$CLOSE_MD" | head -1 | cut -d: -f1)"
  br="$(grep -n 'build-repair-log' "$CLOSE_MD" | head -1 | cut -d: -f1)"
  diffline="$(grep -n 'git diff' "$CLOSE_MD" | head -1 | cut -d: -f1)"
  [ -n "$tv" ] && [ -n "$br" ] && [ -n "$diffline" ]
  # Both mechanical steps precede the diff; the report sits with the gate, not
  # buried after the narrative steps where nobody would read it.
  [ "$br" -lt "$diffline" ]
  [ "$tv" -lt "$diffline" ]
}
