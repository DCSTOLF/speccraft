#!/usr/bin/env bats
# The e2e mock reviewer (.devcontainer/mock-agents/aux-review-mock.sh).
#
# WHY THIS SUITE EXISTS. The mocks used to be heredocs inside
# install-mock-agents.sh, so nothing could exercise them but the devcontainer
# E2E job. When spec 0052 made an unattested verdict count toward neither round
# predicate, the mocks — which discarded their input entirely — started being
# refused as `attestation-failed`, the round went inert, `review.md` was never
# written, and step 4 of the e2e failed. On `main`, after release, because the
# job is gated to push-on-main and had never run against 1.18.0's rules.
#
# The product was correct throughout: a reviewer that cannot prove it read the
# reference files is exactly what the attestation exists to surface. It was the
# harness that was stale. The loop below closes locally in under a second:
# compose a real payload -> dispatch it to the mock -> validate what comes back
# with the shipped validator.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  MOCK="$PLUGIN_DIR/.devcontainer/mock-agents/aux-review-mock.sh"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$TEST_DIR"
}

# A synthetic repo whose root find-root resolves, so the reference paths in the
# composed payload are the repo-relative ones the mock must open.
make_repo() {
  mkdir -p "$TEST_DIR/.speccraft" "$TEST_DIR/round" "$TEST_DIR/bin"
  printf '# Guardrails\n\nBe careful.\n'              > "$TEST_DIR/.speccraft/guardrails.md"
  printf '# Index\n\nindex body\n'                    > "$TEST_DIR/.speccraft/index.md"
  printf '# Arch\n\n## One\n\nbody\n\n### Two\n\nmore\n' > "$TEST_DIR/.speccraft/architecture.md"
  printf '# Conv\n\n## Conv One\n\nbody\n'            > "$TEST_DIR/.speccraft/conventions.md"
  printf '# Spec\n\nspec body\n'                      > "$TEST_DIR/round/spec-frozen.md"
  printf 'REVIEW THIS SPEC.\n'                        > "$TEST_DIR/template.md"
  # Installed under BOTH names, as the devcontainer does — the mock branches on
  # its own basename, so testing only one would miss a per-agent defect.
  install -m 0755 "$MOCK" "$TEST_DIR/bin/codex"
  install -m 0755 "$MOCK" "$TEST_DIR/bin/opencode"
  cd "$TEST_DIR"
}

compose() {
  review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
    --inline .speccraft/guardrails.md .speccraft/index.md \
    --reference .speccraft/architecture.md .speccraft/conventions.md \
    --digest-out "$TEST_DIR/digests.txt"
}

@test "the installer places the mock under both agent names" {
  run bash -c "grep -c 'for name in codex opencode' '$PLUGIN_DIR/.devcontainer/install-mock-agents.sh'"
  [ "$output" = "1" ]
  [ -x "$MOCK" ]
}

@test "the mock attests every reference path with a digest the shipped validator accepts" {
  source "$LIB"; make_repo
  local agent
  # The whole loop, end to end, for each agent name: compose -> dispatch ->
  # validate. This is the assertion whose absence let the regression ship.
  for agent in codex opencode; do
    review_round_tmpdir
    local art="$REVIEW_ROUND_TMPDIR/$agent.payload"
    review_materialize_payload "$art" compose > /dev/null
    PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload "$agent" stdin "$art" > "$TEST_DIR/$agent.out"
    run review_validate_reference_access "$TEST_DIR/$agent.out" "$TEST_DIR/digests.txt"
    [ "$status" -eq 0 ] || {
      echo "$agent was not accepted: $output"; cat "$TEST_DIR/$agent.out"; return 1; }
    [ "$(printf '%s\n' "$output" | tail -1)" = "ok" ]
  done
}

@test "the mock still returns a countable verdict for each agent" {
  source "$LIB"; make_repo
  review_round_tmpdir
  local art="$REVIEW_ROUND_TMPDIR/p.payload"
  review_materialize_payload "$art" compose > /dev/null
  PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload codex stdin "$art" > "$TEST_DIR/codex.out"
  PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload opencode stdin "$art" > "$TEST_DIR/opencode.out"
  # Attesting must not have cost the verdict — the e2e's step 4 needs a real one.
  grep -qE '^verdict: approve-with-comments$' "$TEST_DIR/codex.out"
  grep -qE '^verdict: approve$' "$TEST_DIR/opencode.out"
  # …and the two agents must not return identical bytes, or a round against them
  # would be the false quorum this repo already paid for once.
  ! cmp -s "$TEST_DIR/codex.out" "$TEST_DIR/opencode.out"
}

@test "a digest that does not match the composed value is rejected" {
  source "$LIB"; make_repo
  review_round_tmpdir
  local art="$REVIEW_ROUND_TMPDIR/p.payload"
  review_materialize_payload "$art" compose > /dev/null
  PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload codex stdin "$art" > "$TEST_DIR/codex.out"
  # The bite proof: the mock passes because it really opened the files, not
  # because the validator is lenient. Change one file after composition and the
  # attestation must fail.
  printf '# Conv\n\n## Conv One\n\nDIFFERENT\n' > "$TEST_DIR/.speccraft/conventions.md"
  PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload codex stdin "$art" > "$TEST_DIR/codex2.out"
  run review_validate_reference_access "$TEST_DIR/codex2.out" "$TEST_DIR/digests.txt"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "invalid:digest-mismatch" ]
}

@test "an unreadable reference is reported as a failure, not silently omitted" {
  source "$LIB"; make_repo
  review_round_tmpdir
  local art="$REVIEW_ROUND_TMPDIR/p.payload"
  review_materialize_payload "$art" compose > /dev/null
  # REMOVED rather than chmod 000: the CI job may run as root, for whom mode 000
  # is not a barrier, and the arm would then invert instead of failing honestly.
  # A missing file is unreadable for every uid.
  rm "$TEST_DIR/.speccraft/conventions.md"
  PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload codex stdin "$art" > "$TEST_DIR/codex.out"
  grep -qF 'reference_access_failures:' "$TEST_DIR/codex.out"
  grep -qF 'not readable from the dispatched cwd' "$TEST_DIR/codex.out"
  run review_validate_reference_access "$TEST_DIR/codex.out" "$TEST_DIR/digests.txt"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "invalid:read-failure" ]
}

@test "the mock emits the key even when the round sent no reference files" {
  source "$LIB"; make_repo
  review_round_tmpdir
  local art="$REVIEW_ROUND_TMPDIR/p.payload"
  review_materialize_payload "$art" \
    review_compose_payload "$TEST_DIR/template.md" round/spec-frozen.md \
      --inline .speccraft/guardrails.md \
      --digest-out "$TEST_DIR/empty-digests.txt" > /dev/null
  PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload codex stdin "$art" > "$TEST_DIR/codex.out"
  # An ABSENT block is `invalid:absent`, which is a different finding from "no
  # reference files were sent". The empty-inline form must validate.
  grep -qF 'reference_access: []' "$TEST_DIR/codex.out"
  run review_validate_reference_access "$TEST_DIR/codex.out" "$TEST_DIR/empty-digests.txt"
  [ "$status" -eq 0 ]
}

@test "the mock does not read stdin when it is a pipe rather than a regular file" {
  make_repo
  # The hazard the original `exec </dev/null` was guarding: a mock invoked with
  # stdin inherited from a `claude -p` session blocks forever on `cat`. The guard
  # is `[ -f /dev/stdin ]`, and a pipe takes the same branch whether or not it
  # ever EOFs — so an EOF-ing pipe exercises the no-read path with ZERO risk of
  # hanging the suite.
  #
  # An earlier version of this test held a FIFO open with no writer to model the
  # never-EOF case literally. It ran in 2s locally and then hung the Linux CI job
  # past five minutes, which is a worse failure than the one it was testing for:
  # a test that can hang is a test that can stop the suite from reporting at all.
  run bash -c "printf '' | '$TEST_DIR/bin/codex'"
  [ "$status" -eq 0 ]
  printf '%s\n' "$output" | grep -qF 'verdict: approve-with-comments'
  printf '%s\n' "$output" | grep -qF 'reference_access: []'
}

@test "a RESPONSE_FILE override is emitted verbatim, so the inert-round path stays reachable" {
  make_repo
  printf 'verdict: approve\nconcerns: []\n\n(no attestation here)\n' > "$TEST_DIR/canned.out"
  SPECCRAFT_MOCK_CODEX_RESPONSE_FILE="$TEST_DIR/canned.out" run "$TEST_DIR/bin/codex"
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$TEST_DIR/canned.out")" ]
}

@test "a non-attesting override is refused by the validator, reproducing the regression" {
  source "$LIB"; make_repo
  review_round_tmpdir
  local art="$REVIEW_ROUND_TMPDIR/p.payload"
  review_materialize_payload "$art" compose > /dev/null
  # This is the pre-fix mock, verbatim in shape: a canned verdict with no
  # reference_access. Pinned so the behavior that failed CI is understood as
  # correct and stays reachable for testing the inert round, rather than being
  # quietly designed away.
  printf 'verdict: approve-with-comments\nconcerns: []\nsuggestions: []\nguardrail_violations: []\nconvention_violations: []\n\n(mock codex response)\n' \
    > "$TEST_DIR/old-style.out"
  SPECCRAFT_MOCK_CODEX_RESPONSE_FILE="$TEST_DIR/old-style.out" \
    PATH="$TEST_DIR/bin:$PATH" review_dispatch_payload codex stdin "$art" > "$TEST_DIR/codex.out"
  run review_validate_reference_access "$TEST_DIR/codex.out" "$TEST_DIR/digests.txt"
  [ "$status" -ne 0 ]
  [ "$(printf '%s\n' "$output" | tail -1)" = "invalid:absent" ]
}
