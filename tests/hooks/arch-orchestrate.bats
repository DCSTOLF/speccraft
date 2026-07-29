#!/usr/bin/env bats
# Tests for commands/arch/orchestrate.lib.sh — the deterministic conductor helpers
# backing /speccraft:arch:orchestrate (spec 0039). Pure functions; bats is the RED
# oracle (shell + markdown are not gated by the Go TDD guard). RED until the lib
# helpers exist.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  ORCH_LIB="$PLUGIN_DIR/commands/arch/orchestrate.lib.sh"
  TEST_REPO="$(mktemp -d)"
  export PLUGIN_DIR ORCH_LIB TEST_REPO
  # Behavioral tests (AC6) need the real speccraft-state (ledger-set/reconcile).
  if [ ! -x "$PLUGIN_DIR/bin/speccraft-state" ]; then
    ( cd "$PLUGIN_DIR/tools" && go build -o ../bin/speccraft-state ./cmd/speccraft-state )
  fi
  export PATH="$PLUGIN_DIR/bin:$PATH"
}

teardown() {
  rm -rf "$TEST_REPO"
}

# mk_ws — make TEST_REPO a kind=workspace root.
mk_ws() {
  mkdir -p "$TEST_REPO/.speccraft"
  printf 'kind = "workspace"\n' > "$TEST_REPO/.speccraft/speccraft.toml"
}

# ls_ <field...> — run speccraft-state ledger-set in the workspace.
ls_() {
  ( cd "$TEST_REPO" && speccraft-state ledger-set "$@" )
}

# --- AC1: phase machine ---

@test "orch_next_phase: maps every token to the next action" {
  source "$ORCH_LIB"
  run orch_next_phase ""; [ "$status" -eq 0 ]; [ "$output" = "new" ]
  run orch_next_phase new; [ "$output" = "review" ]
  run orch_next_phase reviewed; [ "$output" = "plan" ]
  run orch_next_phase planned; [ "$output" = "implement" ]   # mid-sequence resume
  run orch_next_phase implemented; [ "$output" = "validate" ]
  run orch_next_phase validated; [ "$output" = "done" ]
}

@test "orch_next_phase: unknown token errors to stderr + non-zero" {
  source "$ORCH_LIB"
  run orch_next_phase bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"orchestrate:"* ]]
}

@test "orch_completed_token: inverse of next_phase" {
  source "$ORCH_LIB"
  run orch_completed_token new; [ "$output" = "new" ]
  run orch_completed_token review; [ "$output" = "reviewed" ]
  run orch_completed_token plan; [ "$output" = "planned" ]
  run orch_completed_token implement; [ "$output" = "implemented" ]
  run orch_completed_token validate; [ "$output" = "validated" ]
}

@test "orch_completed_token: revise has no token (non-zero)" {
  source "$ORCH_LIB"
  run orch_completed_token revise
  [ "$status" -ne 0 ]
}

# --- AC2: checkpoint predicate ---

@test "orch_should_pause: pause iff next==implement and straight_through!=1" {
  source "$ORCH_LIB"
  run orch_should_pause implement 0;  [ "$output" = "pause" ]
  run orch_should_pause implement ""; [ "$output" = "pause" ]
  run orch_should_pause implement 1;  [ "$output" = "go" ]
  run orch_should_pause new 0;        [ "$output" = "go" ]
  run orch_should_pause plan 0;       [ "$output" = "go" ]
  run orch_should_pause validate 0;   [ "$output" = "go" ]
}

# --- AC3: review -> revise control ---

@test "orch_review_verdict: pass on pass regardless of iteration" {
  source "$ORCH_LIB"
  run orch_review_verdict 0 3 pass; [ "$output" = "pass" ]
  run orch_review_verdict 5 3 pass; [ "$output" = "pass" ]
}

@test "orch_review_verdict: revise when not-pass and iteration<max" {
  source "$ORCH_LIB"
  run orch_review_verdict 0 3 changes-requested; [ "$output" = "revise" ]
  run orch_review_verdict 2 3 changes-requested; [ "$output" = "revise" ]
}

@test "orch_review_verdict: escalate at iteration==max and beyond" {
  source "$ORCH_LIB"
  run orch_review_verdict 3 3 changes-requested; [ "$output" = "escalate" ]
  run orch_review_verdict 4 3 changes-requested; [ "$output" = "escalate" ]
}

# --- AC4: decomposition parse ---

@test "orch_parse_decomposition: valid lines normalize (comments/blanks ignored, first-tab split, trim)" {
  source "$ORCH_LIB"
  printf '# top\n\n  # spaced comment\n\t# tab-indented comment\n./api\t  build the api  \n./web\tbrief with\tinterior tab\n' > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$(printf './api\tbuild the api')" ]
  [ "${lines[1]}" = "$(printf './web\tbrief with\tinterior tab')" ]
}

@test "orch_parse_decomposition: tab-less line errors" {
  source "$ORCH_LIB"
  printf './api no-tab-here\n' > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -ne 0 ]; [[ "$output" == *"orchestrate:"* ]]
}

@test "orch_parse_decomposition: empty member-path errors" {
  source "$ORCH_LIB"
  printf '\tbrief only\n' > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -ne 0 ]
}

@test "orch_parse_decomposition: empty brief errors" {
  source "$ORCH_LIB"
  printf './api\t   \n' > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -ne 0 ]
}

@test "orch_parse_decomposition: duplicate member-path errors" {
  source "$ORCH_LIB"
  printf './api\tone\n./api\ttwo\n' > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -ne 0 ]
}

@test "orch_parse_decomposition: member-path with whitespace errors" {
  source "$ORCH_LIB"
  printf './a b\tbrief\n' > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -ne 0 ]
}

@test "orch_parse_decomposition: member-path with shell metachar errors" {
  source "$ORCH_LIB"
  printf './api;rm\tbrief\n' > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -ne 0 ]
}

@test "orch_parse_decomposition: member-path with a literal single-quote errors" {
  source "$ORCH_LIB"
  printf "./ap'i\tbrief\n" > "$TEST_REPO/d.tsv"
  run orch_parse_decomposition "$TEST_REPO/d.tsv"
  [ "$status" -ne 0 ]
}

# --- AC5: dispatch (cwd-scoped, quoted, never --root) + validate gate ---

@test "orch_dispatch: cwd-scoped '<m>', pinned command per action, never --root" {
  source "$ORCH_LIB"
  run orch_dispatch ./api new
  [ "$status" -eq 0 ]
  [[ "$output" == *"cd './api'"* ]]
  [[ "$output" == *"/speccraft:spec:new"* ]]
  [[ "$output" != *"--root"* ]]
  run orch_dispatch ./api review;    [[ "$output" == *"/speccraft:spec:review"* ]];    [[ "$output" != *"--root"* ]]
  run orch_dispatch ./api revise;    [[ "$output" == *"/speccraft:spec:revise"* ]]
  run orch_dispatch ./api plan;      [[ "$output" == *"/speccraft:spec:plan"* ]]
  run orch_dispatch ./api implement; [[ "$output" == *"/speccraft:spec:implement"* ]]
  run orch_dispatch ./api validate;  [[ "$output" == *"/speccraft:spec:close"* ]]
}

@test "orch_dispatch: unknown action errors" {
  source "$ORCH_LIB"
  run orch_dispatch ./api bogus
  [ "$status" -ne 0 ]
}

@test "orch_validate: pass from a zero-exit command" {
  source "$ORCH_LIB"
  run orch_validate true
  [ "$output" = "pass" ]
}

@test "orch_validate: fail from a non-zero command" {
  source "$ORCH_LIB"
  run orch_validate false
  [ "$output" = "fail" ]
}

# --- AC6: failure isolation, blocked-clear & phase-walk (behavioral) ---

@test "orch_apply_result: A fails->blocked+in_flight cleared, B advances, siblings isolated" {
  source "$ORCH_LIB"
  mk_ws
  ls_ D ./a spec 0007-a
  ls_ D ./b spec 0012-b
  ls_ D ./a in_flight implement
  ls_ D ./b in_flight implement
  orch_apply_result "$TEST_REPO" D ./a implement 1   # A fails
  orch_apply_result "$TEST_REPO" D ./b implement 0   # B succeeds
  run cat "$TEST_REPO/.speccraft/ledger.md"
  [[ "$output" == *"blocked: implement failed"* ]]         # A blocked
  [[ "$output" == *"last_completed_phase: implemented"* ]] # B advanced
  [[ "$output" != *"in_flight: implement"* ]]              # in_flight cleared on both
}

@test "orch_apply_result: clean re-attempt of A clears blocked + advances" {
  source "$ORCH_LIB"
  mk_ws
  ls_ D ./a spec 0007-a
  orch_apply_result "$TEST_REPO" D ./a implement 1   # blocked
  orch_apply_result "$TEST_REPO" D ./a implement 0   # clean retry
  run cat "$TEST_REPO/.speccraft/ledger.md"
  [[ "$output" == *"last_completed_phase: implemented"* ]]
  [[ "$output" != *"implement failed"* ]]            # blocked cleared
}

@test "phase-walk: pointer walks new->reviewed->planned->implemented->validated, in_flight cleared" {
  source "$ORCH_LIB"
  mk_ws
  ls_ D ./m spec 0001-x
  local pointer="" action
  for _ in 1 2 3 4 5 6; do
    action="$(orch_next_phase "$pointer")"
    if [ "$action" = "done" ]; then break; fi
    ls_ D ./m in_flight "$action"                    # set in_flight before dispatch
    orch_apply_result "$TEST_REPO" D ./m "$action" 0 # success advances + clears in_flight
    pointer="$(orch_completed_token "$action")"
  done
  [ "$pointer" = "validated" ]
  run cat "$TEST_REPO/.speccraft/ledger.md"
  [[ "$output" == *"last_completed_phase: validated"* ]]
  [[ "$output" != *"in_flight: validate"* ]]         # cleared after the final step
}

# --- AC7: orchestrate.md runbook structure (grep) ---

@test "orchestrate.md: exists with frontmatter keys" {
  local md="$PLUGIN_DIR/commands/arch/orchestrate.md"
  [ -f "$md" ]
  grep -qE '^description:' "$md"
  grep -qE '^argument-hint:' "$md"
  grep -qE '^allowed-tools:' "$md"
}

@test "orchestrate.md: bootstraps plugin-root + workspace root + sources the lib" {
  local md="$PLUGIN_DIR/commands/arch/orchestrate.md"
  grep -q 'speccraft-state plugin-root' "$md"
  grep -q 'find-root' "$md"
  grep -q 'orchestrate.lib.sh' "$md"
}

@test "orchestrate.md: pins token order, both checkpoints, --straight-through" {
  local md="$PLUGIN_DIR/commands/arch/orchestrate.md"
  grep -q 'new → reviewed → planned → implemented → validated' "$md"
  grep -q -- '--straight-through' "$md"
  grep -qi 'before .*implement' "$md"     # checkpoint (a)
  grep -qi 'escalat' "$md"                # checkpoint (b)
}

@test "orchestrate.md: pins spec:close, resume, in_flight, blocked" {
  local md="$PLUGIN_DIR/commands/arch/orchestrate.md"
  grep -q 'spec:close' "$md"
  grep -qi 'resume' "$md"
  grep -q 'in_flight' "$md"
  grep -q 'blocked' "$md"
}

@test "orchestrate.md: drives list-members, ledger-set, reconcile" {
  local md="$PLUGIN_DIR/commands/arch/orchestrate.md"
  grep -q 'list-members' "$md"
  grep -q 'ledger-set' "$md"
  grep -q 'reconcile' "$md"
}
