#!/usr/bin/env bats
# Spec 0049 T13 (AC10, carried review item 8) — the sweep behind the claim that
# "exactly one file in tests/hooks EXECUTES a GNU-only form, in seven places".
#
# That claim drove a real decision: PORT the offending file rather than add it
# to a macOS exclusion list. A decision that load-bearing must be reproducible
# by a reviewer, not taken on the author's word — so the sweep is mechanised
# here rather than described in prose.
#
# The discriminator is EXECUTES vs MENTIONS, and it matters: a naive grep for
# `sed -i` across tests/hooks hits several files, but almost every hit is a
# fixture STRING written to disk for a meta-guard to scan, or a comment. Those
# are inert on any platform. Only a line that actually runs the command breaks
# on BSD userland.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  HOOKS="$PLUGIN_DIR/tests/hooks"
  TEST_DIR="$(mktemp -d)"
  export PLUGIN_DIR HOOKS
}

teardown() {
  [ -z "${TEST_DIR:-}" ] || rm -rf "$TEST_DIR"
}

# The enumerated GNU-only forms, same set as the shipped-surface guard.
gnu_form_pattern() {
  # `realpath -m` and `sha256sum` added by spec 0050 AC12: the macOS bats job ran
  # for the first time and both forms broke it, one in a shipped hook and one
  # right here in tests/hooks — which this sweep walked straight past.
  printf '%s' "sed[[:space:]]+-i[[:space:]]+([^'\"[:space:]]|'[^']|\"[^\"])|sed[^|;]*[[:space:]]['\"]?0,/|(^|[|;&(]|[[:space:]])tac([[:space:]]|\$|[|;&)])|readlink[[:space:]]+-f|grep[[:space:]]+-[A-Za-z]*P|stat[[:space:]]+-c|date[[:space:]]+-d[[:space:]]|base64[[:space:]]+-w|realpath[[:space:]]+-[A-Za-z]*m([[:space:]]|\$)|sha256sum"
  # NOTE: this sweep scans tests/hooks, which is all bats — no *.go exclusion is
  # needed here, unlike the shipped-surface guard's clause (e).
}

# Lines that MENTION a form without running it:
#   - comments
#   - printf/echo/cat writing a fixture string to disk
#   - shell function management: `tac() {`, `unset -f tac`, `export -f tac`
#   - a grep/scanner PATTERN (the meta-guards' own regexes)
#   - a @test TITLE that merely names a form (e.g. "...with tac absent...")
#   - a fixture-BUILDER call that takes a tool name as an argument
#     (`make_gnu_tool "$dir" tac`) — it creates a stub, it does not run GNU
mention_only_filter() {
  grep -vE "^[^:]+:[0-9]+:[[:space:]]*#" \
    | grep -vE "(printf|echo|cat >)" \
    | grep -vE "(unset -f|export -f|\(\)[[:space:]]*\{)" \
    | grep -vE "grep -rnE|grep -qE|grep -nE|grep -vE|gnu_form_pattern" \
    | grep -vE "^[^:]+:[0-9]+:@test " \
    | grep -vE "make_gnu_tool|make_bsd_path|make_versioned_tool|make_digest_tool|for t in " \
    | grep -vE "command[[:space:]]+-v[[:space:]]+sha256sum" \
    | grep -vE "Bash\(sha256sum:" \
    | grep -vE "^[^:]+/fixtures/[^:]+:[0-9]+:"
}

# Why the fixtures/ exclusion is a scope boundary and not a hole: everything
# under tests/hooks/fixtures/ is inert DATA, read by a test and never sourced or
# executed as shell. The distinction this sweep draws is "does a file in the
# suite RUN a GNU-only form on the macOS runner", and a fixture cannot, by
# construction — the suites open these paths with grep/cat, never with `.` or
# `bash`. Spec 0052's captured reviewer corpus is the case that forced this:
# those files are verbatim transcripts in which a reviewer ARGUES about
# `sha256sum` portability, and rewording them to appease a scanner would destroy
# the only property that makes them useful as fixtures.
#
# The boundary is auditable: a fixture that ever needs to be executed must be
# moved out of fixtures/, at which point the sweep sees it again.

# executing_files — the files in tests/hooks that actually RUN a GNU-only form.
executing_files() {
  grep -rnE "$(gnu_form_pattern)" "$HOOKS" 2>/dev/null \
    | mention_only_filter \
    | sed 's|:.*||' | sort -u | sed "s|^$HOOKS/||" || true
}

@test "sweep: no file in tests/hooks EXECUTES a GNU-only form" {
  out="$(executing_files)"
  [ -z "$out" ] || {
    echo "these files execute a GNU-only form and would fail on the macOS runner:"
    echo "$out"
    echo "--- offending lines ---"
    grep -rnE "$(gnu_form_pattern)" "$HOOKS" 2>/dev/null | mention_only_filter
    return 1
  }
}

# The auditable half: the files whose matches are ALL mentions. Pinned as an
# exact set so that silently reclassifying a real execution as "just a mention"
# is impossible — adding a file here is a visible, reviewable decision.
@test "sweep: the mention-only exclusion list is exactly the known set" {
  local expected actual
  # Why each one only MENTIONS a form:
  #   frontmatter-writer-guard, portability-guard — write forbidden forms as
  #     fixture strings for a scanner to find; never executed.
  #   tests-portability-sweep (this file) — holds the detection patterns.
  #   spec-consolidate — a `tac` function shadow plus a @test title naming it.
  #   spec-revise-preflight, init-workspace — the two files PORTED by AC10;
  #     what remains is the comment explaining why the GNU form was removed.
  #   no-gnu-userland — builds synthetic GNU/BSD tool stubs by name (tac, gsed,
  #     …) to exercise the assertion script; it never runs a real GNU tool.
  #   sync-workspace — added by spec 0050 AC13. It names the GNU checksum tool
  #     inside a single-line `command -v … ; then … ; else shasum -a 256; fi`
  #     probe, which RUNS the tool only where it exists. That is the portable
  #     fallback idiom, not an unguarded execution, and the `executing_files`
  #     filter exempts the probe spelling specifically. Before this spec the file
  #     piped straight into the GNU tool and failed on every BSD runner.
  #   fixtures/spec-review-payload/responses/historical/r4-claudep.out — added by
  #     spec 0052. It is a CAPTURED reviewer response from this spec's own round-4
  #     review, in which the reviewer argued that `sha256sum` is GNU-only and that
  #     the digest primitive needed the same guard as the awk-interval trap. The
  #     file is inert test DATA: it is read by the attestation validator's
  #     tolerance test and never executed as shell. It is pinned here rather than
  #     reworded because the corpus's value is that it is verbatim — editing a
  #     captured response to appease a scanner would destroy the property that
  #     makes it a useful fixture.
  #   spec-review-payload — added by spec 0052 AC9. It names the GNU checksum
  #     tool ONCE, as the argument to `make_digest_tool`, which writes a /bin/sh
  #     STUB of that name into a synthetic PATH. That stub is how the digest
  #     primitive is pinned on its GNU polarity: the test sets PATH to the stub
  #     dir ALONE, so the real tool is unreachable by construction. The builder
  #     spelling is exempted alongside the other fixture builders above, for the
  #     same reason — it takes a tool name as DATA and never executes one.
  #   spec-review-round-runbook — added by spec 0054 AC20. It asserts that each
  #     of the four review command files lists `Bash(sha256sum:*)` in its
  #     `allowed-tools`, so the tool name appears as the NEEDLE of a `grep -qF`
  #     and never as a command. The grant is a capability, not an invocation:
  #     review.lib.sh probes `shasum -a 256` first and reaches the GNU tool only
  #     where shasum is absent, so both grants must be listed or attestation
  #     breaks on whichever host lacks the preferred primitive. Rewording is not
  #     available here — the string IS the permission.
  #   review-subagent-agent — added by spec 0054 AC18, for the same reason one
  #     step further in. It pins `agents/reviewer.md`'s `tools:` list EXACTLY,
  #     including `Bash(sha256sum:*)`, because that list is the subagent's only
  #     confinement: it shares the orchestrating session rather than running in
  #     a sandbox, so a widened entry must red. An exact-match assertion cannot
  #     spell the grant any other way, and a membership check would defeat the
  #     purpose of pinning it.
  expected="$(printf '%s\n' \
    fixtures/spec-review-payload/responses/historical/r4-claudep.out \
    review-subagent-agent.bats \
    spec-review-round-runbook.bats \
    frontmatter-writer-guard.bats \
    spec-review-payload.bats \
    init-workspace.bats \
    no-gnu-userland.bats \
    portability-guard.bats \
    spec-consolidate.bats \
    spec-revise-preflight.bats \
    sync-workspace.bats \
    tests-portability-sweep.bats | sort -u)"
  actual="$(grep -rlE "$(gnu_form_pattern)" "$HOOKS" 2>/dev/null \
    | sed "s|^$HOOKS/||" | sort -u)"
  [ "$expected" = "$actual" ] || {
    echo "the set of files mentioning a GNU-only form changed."
    echo "If a NEW file legitimately only mentions one, add it here deliberately."
    diff <(echo "$expected") <(echo "$actual") || true
    return 1
  }
}

# ---------------------------------------------------------------------------
# An awk RANGE whose END pattern is an interval expression. Two portability
# bugs that compose into a silent one, and CI caught it in a test of this
# repo's own — the first CI run spec 0054's branch ever had.
#
#   awk RANGE, end pattern an interval: /start/,/^#<N,M> /
#   (written with <N,M> rather than the real braces, because this file is
#   itself under the sweep and the literal form would flag it)
#
# mawk (this devcontainer's awk, and Debian's default) does not implement
# intervals: the end pattern matches NOTHING, so the range runs to EOF and the
# extraction silently covers the whole file. An awk that DOES implement them
# ends the range on its own start line, because a `## …` heading matches
# `^#{2,3} ` too — awk closes a range when the start line also matches the end.
# So the same line yields "the whole file" on one platform and "one line" on
# the other, and NEITHER is the section the author meant.
#
# `sed` is the portable spelling: its range never ends on the start line, and
# an alternation (`/^## [0-9]/`) needs no interval.
#
# Scoped to the lethal COMBINATION rather than to intervals generally, because
# `portability-guard.bats` legitimately writes forbidden fixtures containing
# them, and `spec-review-payload.bats` legitimately proves mawk's behaviour.
# Narrowing the pattern is what keeps this guard free of an exemption list.
# ---------------------------------------------------------------------------

awk_range_interval_pattern() {
  printf '%s\n' "awk[^|;]*'/[^/]*/,/[^/]*\{[0-9]+(,[0-9]*)?\}[^/]*/'"
}

@test "sweep: no test uses an awk range with an interval end pattern" {
  local hits
  hits="$(grep -rnE "$(awk_range_interval_pattern)" "$HOOKS" 2>/dev/null || true)"
  [ -z "$hits" ] || {
    echo "awk range with an interval end pattern (whole file under mawk, one line elsewhere):" >&2
    printf '%s\n' "$hits" >&2
    echo "Use sed: its range never closes on the start line, and an" >&2
    echo "alternation such as /^## [0-9]/ needs no interval." >&2
    return 1
  }
}

@test "sweep: the awk-range guard matches the form it forbids" {
  # Premise. The exact line CI failed on, reconstructed, plus the portable
  # replacement which must NOT match.
  local bad good
  bad="$TEST_DIR/bad.bats"
  mkdir -p "$TEST_DIR"
  # Assembled from pieces so the literal does not appear in this file's own
  # source: the sweep scans tests/hooks, which includes this file.
  local lo=2 hi=3 ivl
  ivl="{$lo,$hi}"
  printf '%s\n' "  n=\"\$(awk '/[Tt]imeout .*protocol/,/^#$ivl /' \"\$RUNBOOK\" | grep -c x)\"" > "$bad"
  grep -qE "$(awk_range_interval_pattern)" "$bad" || {
    echo "the guard does not match the line CI actually failed on:" >&2
    cat "$bad" >&2
    return 1
  }
  good="$TEST_DIR/good.bats"
  printf '%s\n' "  section=\"\$(sed -n '/[Tt]imeout and cancellation protocol/,/^## [0-9]/p' \"\$RUNBOOK\")\"" > "$good"
  grep -qE "$(awk_range_interval_pattern)" "$good" && {
    echo "the guard false-positives on the portable sed replacement" >&2
    return 1
  }
  # And it must NOT fire on the deliberate non-range uses that exist today:
  # the guard's own forbidden fixtures, and 0052's proof of mawk's behaviour.
  printf '%s\n' "awk '/^#$ivl /{print}' \"\$f\"" > "$TEST_DIR/action.sh"
  grep -qE "$(awk_range_interval_pattern)" "$TEST_DIR/action.sh" && {
    echo "the guard fires on a non-range interval use, which would need an" >&2
    echo "exemption list for the fixtures that legitimately carry one" >&2
    return 1
  }
  return 0
}
