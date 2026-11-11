#!/usr/bin/env bats
# Spec 0054 Phase E — the persistent round directory (ACs 14, 14a, 14b, 14c, 14e).
#
# The round dir holds the composed payload and the digest sidecar for the life
# of a round. It must outlive the creating shell (reviewers run concurrently and
# the orchestrator does not block on them), be invisible to git in an
# already-initialized repo with NO migration, and be reclaimable after a crash
# without ever deleting a round that is still running.
#
# Reclamation is LEASE-based, never age-based. An age rule cannot tell a round
# that has been running for an hour from one abandoned an hour ago, and this
# spec's rounds legitimately run long.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="$PLUGIN_DIR/commands/spec/review.lib.sh"
  LEGACY="$PLUGIN_DIR/tests/hooks/fixtures/review-dispatch/legacy-repo"
  export PATH="$PLUGIN_DIR/bin:$PATH"
  TEST_DIR="$(mktemp -d)"
  REPO="$TEST_DIR/repo"
  ROUNDS="$REPO/.speccraft/.review-rounds"
  mkdir -p "$REPO/.speccraft"
  cd "$REPO"
}

teardown() {
  cd /
  rm -rf "$TEST_DIR"
}

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

# dir_mode <dir> — permission bits, portably. `stat` differs between GNU and
# BSD and its GNU format flag is barred by the portability sweep, so the mode
# comes from `ls -ld` instead.
dir_mode() {
  ls -ld "$1" | awk '{print substr($1, 1, 10)}'
}

# ---------------------------------------------------------------------------
# AC14 — create, survive, clean up
# ---------------------------------------------------------------------------

@test "review_round_dir_create makes a 0700 dir under .speccraft/.review-rounds/" {
  source "$LIB"
  run review_round_dir_create spec 0054 600
  [ "$status" -eq 0 ]

  local dir="$output"
  [ -d "$dir" ]
  # Inside the parent, not merely named like it.
  case "$dir" in
    "$ROUNDS"/*) : ;;
    *) echo "round dir is not under $ROUNDS: $dir" >&2; return 1 ;;
  esac
  # 0700: the payload can carry a spec not yet published, so other users on a
  # shared box must not be able to read it.
  [ "$(dir_mode "$dir")" = "drwx------" ] || {
    echo "expected drwx------, got $(dir_mode "$dir")" >&2
    return 1
  }
}

@test "the round dir survives the creating shell" {
  source "$LIB"
  # Created in a SEPARATE shell that then exits. A dir held open only by the
  # creating process would vanish here, and reviewers outlive the shell that
  # launched them.
  local dir
  dir="$(bash -c "cd '$REPO'; source '$LIB'; review_round_dir_create spec 0054 600")"
  [ -n "$dir" ]
  [ -d "$dir" ]
  [ -f "$dir/lease" ]
}

@test "review_round_cleanup removes a round dir" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  printf 'payload\n' > "$dir/payload.md"

  run review_round_cleanup "$dir"
  [ "$status" -eq 0 ]
  [ ! -d "$dir" ]
}

@test "review_round_cleanup refuses a path outside .review-rounds/" {
  source "$LIB"
  mkdir -p "$TEST_DIR/elsewhere"
  printf 'keep\n' > "$TEST_DIR/elsewhere/keep.txt"

  run review_round_cleanup "$TEST_DIR/elsewhere"
  assert_named_failure 'review-rounds'
  # Asserted per row, not once at the end: a refusal that deleted first and
  # complained afterwards would still "refuse".
  [ -d "$TEST_DIR/elsewhere" ]
  [ -f "$TEST_DIR/elsewhere/keep.txt" ]
}

@test "review_round_cleanup refuses a symlink" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  printf 'payload\n' > "$dir/payload.md"
  ln -s "$dir" "$ROUNDS/link-to-round"

  run review_round_cleanup "$ROUNDS/link-to-round"
  [ "$status" -ne 0 ]
  # Nothing deleted: neither the link nor, crucially, its target.
  [ -L "$ROUNDS/link-to-round" ]
  [ -d "$dir" ]
  [ -f "$dir/payload.md" ]
}

@test "review_round_cleanup refuses /" {
  source "$LIB"
  # An absent function also "refuses" and deletes nothing, so this row would
  # pass before the function existed. Assert the premise first.
  command -v review_round_cleanup >/dev/null 2>&1 || {
    echo "review_round_cleanup is not defined; this row would pass vacuously" >&2
    return 1
  }
  run review_round_cleanup /
  [ "$status" -ne 0 ]
  [ -d / ]
  [ -d "$REPO" ]
}

@test "review_round_cleanup refuses an escaping .." {
  source "$LIB"
  # An absent function also "refuses" and deletes nothing, so this row would
  # pass before the function existed. Assert the premise first.
  command -v review_round_cleanup >/dev/null 2>&1 || {
    echo "review_round_cleanup is not defined; this row would pass vacuously" >&2
    return 1
  }
  mkdir -p "$TEST_DIR/sibling"
  printf 'keep\n' > "$TEST_DIR/sibling/keep.txt"

  # Lexically under .review-rounds/, but resolves outside it. Comparing the
  # strings instead of the resolved paths is what makes this pass.
  run review_round_cleanup "$ROUNDS/../../../sibling"
  [ "$status" -ne 0 ]
  [ -d "$TEST_DIR/sibling" ]
  [ -f "$TEST_DIR/sibling/keep.txt" ]
}

@test "review_round_cleanup refuses the .review-rounds parent itself" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0054 600)"

  # "Inside the parent" must mean strictly inside: wiping the parent would take
  # every concurrent round with it.
  run review_round_cleanup "$ROUNDS"
  [ "$status" -ne 0 ]
  [ -d "$ROUNDS" ]
  [ -d "$dir" ]
}

@test "cleanup resolves symlinks on both sides under a symlinked TMPDIR" {
  source "$LIB"
  # The macOS shape: TMPDIR itself is a symlink, so the repo root resolves to a
  # different prefix than the path the caller holds. Comparing one resolved
  # side against one unresolved side refuses a legitimate round dir (spec 0050
  # defect A).
  local real link
  real="$TEST_DIR/real-tmp"
  link="$TEST_DIR/link-tmp"
  mkdir -p "$real/repo/.speccraft"
  ln -s "$real" "$link"

  cd "$link/repo"
  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  [ -d "$dir" ]

  run review_round_cleanup "$dir"
  [ "$status" -eq 0 ] || {
    echo "a legitimate round dir reached through a symlinked TMPDIR must be removable; got: $output" >&2
    return 1
  }
  [ ! -d "$dir" ]
}

@test "cleanup resolves a symlinked ancestor of the repo root" {
  source "$LIB"
  local real link
  real="$TEST_DIR/real-parent"
  link="$TEST_DIR/link-parent"
  mkdir -p "$real/nested/repo/.speccraft"
  ln -s "$real" "$link"

  cd "$link/nested/repo"
  local dir
  dir="$(review_round_dir_create spec 0054 600)"

  run review_round_cleanup "$dir"
  [ "$status" -eq 0 ] || {
    echo "a symlinked ANCESTOR must not make the round dir unremovable; got: $output" >&2
    return 1
  }
  [ ! -d "$dir" ]
}

# ---------------------------------------------------------------------------
# AC14a — ignored with no migration
# ---------------------------------------------------------------------------

@test "review_round_dir_create writes .speccraft/.review-rounds/.gitignore containing *" {
  source "$LIB"
  review_round_dir_create spec 0054 600 >/dev/null
  [ -f "$ROUNDS/.gitignore" ]
  grep -qxF '*' "$ROUNDS/.gitignore"
}

@test "the .gitignore write is idempotent across two rounds" {
  source "$LIB"
  review_round_dir_create spec 0054 600 >/dev/null
  local before
  before="$(cat "$ROUNDS/.gitignore")"
  review_round_dir_create spec 0055 600 >/dev/null

  # Byte-identical, not merely "still contains *": an append-per-round would
  # grow the file without ever being noticed.
  [ "$(cat "$ROUNDS/.gitignore")" = "$before" ]
  [ "$(grep -c . "$ROUNDS/.gitignore")" -eq 1 ]
}

@test "git check-ignore reports the round dir and its payload ignored in a fresh repo" {
  source "$LIB"
  git -C "$REPO" init -q
  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  printf 'payload\n' > "$dir/payload.md"

  git -C "$REPO" check-ignore -q "$dir" || {
    echo "the round dir is not ignored" >&2
    return 1
  }
  git -C "$REPO" check-ignore -q "$dir/payload.md" || {
    echo "the round payload is not ignored" >&2
    return 1
  }
}

@test "a pre-0054 installed-base repo ignores the round dir with no re-init" {
  source "$LIB"
  # THE case that matters. The host's .gitignore is the checked-in fixture — a
  # byte-copy of what /speccraft:init wrote before this spec — and it is never
  # touched: no re-init, no template update, no edit. The round dir can only be
  # ignored by the .gitignore written INSIDE .review-rounds/.
  git -C "$REPO" init -q
  cp "$LEGACY/gitignore.pre0054" "$REPO/.gitignore"

  # The fixture must say nothing about the round dir, or this row proves
  # nothing about the mechanism.
  if grep -q 'review-rounds' "$REPO/.gitignore"; then
    echo "the legacy fixture already mentions review-rounds; the row is vacuous" >&2
    return 1
  fi

  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  printf 'payload\n' > "$dir/payload.md"

  git -C "$REPO" check-ignore -q "$dir" || {
    echo "a pre-0054 repo does not ignore the round dir" >&2
    return 1
  }
  git -C "$REPO" check-ignore -q "$dir/payload.md" || {
    echo "a pre-0054 repo does not ignore the round payload" >&2
    return 1
  }

  # And the host's own file is unchanged — "no migration" means exactly that.
  cmp -s "$LEGACY/gitignore.pre0054" "$REPO/.gitignore" || {
    echo "the host's .gitignore was modified; this must need no migration" >&2
    return 1
  }
}

@test "git add -A in a pre-0054 repo stages nothing from the round dir" {
  source "$LIB"
  git -C "$REPO" init -q
  git -C "$REPO" config user.email t@example.com
  git -C "$REPO" config user.name T
  cp "$LEGACY/gitignore.pre0054" "$REPO/.gitignore"

  local dir
  dir="$(review_round_dir_create spec 0054 600)"
  printf 'payload\n' > "$dir/payload.md"
  printf 'digest\n' > "$dir/digests.txt"

  git -C "$REPO" add -A
  # check-ignore proves the rule; this proves the OUTCOME an operator would
  # actually hit. A round payload can quote an unpublished spec.
  if git -C "$REPO" diff --cached --name-only | grep -q 'review-rounds'; then
    echo "git add -A staged something from the round dir:" >&2
    git -C "$REPO" diff --cached --name-only >&2
    return 1
  fi
}

# ---------------------------------------------------------------------------
# AC14e — the timeout parameter is wired, proven by test not signature
# ---------------------------------------------------------------------------

# lease_expiry <dir> — the absolute unix expiry recorded in the lease.
lease_expiry() {
  awk '$1 == "expires_at" { print $2; exit }' "$1/lease"
}

@test "two different timeouts yield two different lease expiries, each timeout plus 300" {
  source "$LIB"
  local now a b ea eb
  now="$(date +%s)"
  a="$(review_round_dir_create spec 0054 600)"
  b="$(review_round_dir_create spec 0055 1800)"
  ea="$(lease_expiry "$a")"
  eb="$(lease_expiry "$b")"

  [ -n "$ea" ] && [ -n "$eb" ] || {
    echo "a lease carried no parseable expires_at (a=$ea b=$eb)" >&2
    return 1
  }
  [ "$ea" != "$eb" ] || {
    echo "both timeouts produced the same expiry ($ea); the parameter is not wired" >&2
    return 1
  }

  # timeout + 300, allowing a couple of seconds for the clock to move between
  # the two creates. Asserted as a window rather than an equality so the row is
  # not flaky, but tight enough that a wrong grace or a dropped timeout fails.
  local want_a=$((now + 600 + 300)) want_b=$((now + 1800 + 300))
  [ "$ea" -ge "$want_a" ] && [ "$ea" -le $((want_a + 5)) ] || {
    echo "expiry a=$ea outside [$want_a, $((want_a + 5))]" >&2
    return 1
  }
  [ "$eb" -ge "$want_b" ] && [ "$eb" -le $((want_b + 5)) ] || {
    echo "expiry b=$eb outside [$want_b, $((want_b + 5))]" >&2
    return 1
  }
}

@test "the .building name the helper chose is recorded by its instrumentation" {
  source "$LIB"
  # AC14e permits interleaving OR instrumentation and this uses the latter: a
  # successful create mv's the .building name away, so listing the directory
  # afterwards cannot observe it. An AC that asserts a state the test cannot
  # reach is the defect round 5 found in AC14d.
  local dir build_name
  dir="$(review_round_dir_create spec 0054 600)"

  # Read from the DURABLE record, not from REVIEW_ROUND_BUILD_NAME: taking the
  # round path by command substitution runs the helper in a subshell, so the
  # variable is discarded before this shell could see it. That is true of every
  # real caller too, which is why the helper writes the name down.
  [ -f "$dir/build-name" ] || {
    echo "the helper recorded no build name" >&2
    return 1
  }
  build_name="$(cat "$dir/build-name")"
  case "$build_name" in
    .building-*) : ;;
    *) echo "unexpected build name: $build_name" >&2; return 1 ;;
  esac

  # The name must carry the SAME absolute expiry as the lease, because the
  # sweep reclaims an abandoned .building dir by reading its name.
  local name_expiry
  # Field 2: the name is `.building-<expiry>-<pid>-<rand>`, so splitting on
  # "-" puts the expiry in $2 and the PID in $3 — reading $3 compares a pid
  # against a timestamp and looks like a mismatch.
  name_expiry="$(printf '%s\n' "$build_name" | awk -F- '{print $2}')"
  [ "$name_expiry" = "$(lease_expiry "$dir")" ] || {
    echo "name expiry $name_expiry != lease expiry $(lease_expiry "$dir")" >&2
    return 1
  }

  # And it is gone: the publish is a rename, not a copy.
  [ ! -d "$ROUNDS/$build_name" ]
}

@test "review_round_lease_expired distinguishes active, expired and unparseable" {
  source "$LIB"
  local dir
  dir="$(review_round_dir_create spec 0054 600)"

  # Captured, never called bare: this lib turns on errexit at source time, and
  # an ACTIVE lease returns 1, which would abort the test body before the
  # assertion could run.
  local rc=0
  review_round_lease_expired "$dir" || rc=$?
  [ "$rc" -eq 1 ] || { echo "a fresh lease must read as active, got $rc" >&2; return 1; }

  printf 'expires_at 1\n' > "$dir/lease"
  rc=0
  review_round_lease_expired "$dir" || rc=$?
  [ "$rc" -eq 0 ] || { echo "an expiry in 1970 must read as expired, got $rc" >&2; return 1; }

  printf 'garbage\n' > "$dir/lease"
  rc=0
  review_round_lease_expired "$dir" || rc=$?
  [ "$rc" -eq 2 ] || { echo "an unparseable lease must be distinguishable, got $rc" >&2; return 1; }

  rm -f "$dir/lease"
  rc=0
  review_round_lease_expired "$dir" || rc=$?
  [ "$rc" -eq 2 ] || { echo "a missing lease must be distinguishable, got $rc" >&2; return 1; }
}

@test "the round dir uses no date -d, which BSD date does not support" {
  # The expiry is now + timeout + 300, computed with shell arithmetic on
  # `date +%s`. GNU's -d would work in CI and fail on macOS.
  run sh -c "grep -vE '^[[:space:]]*#' '$LIB' | grep -nE 'date[[:space:]]+-d[[:space:]]'"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# AC14b / AC14c — review_round_sweep: lease-based reclamation
#
# Age is never a reason to delete. A round legitimately running for an hour and
# one abandoned an hour ago look identical by mtime, so every row below fakes
# the mtimes far into the past and asserts the LEASE decided the outcome.
# ---------------------------------------------------------------------------

# age_dir <dir> — backdate a directory so any age-based rule would fire.
age_dir() {
  touch -t 200001010000 "$1"
}

# make_round <kind> <id> <timeout> — create a round and echo its path.
make_round() {
  review_round_dir_create "$1" "$2" "$3"
}

@test "review_round_sweep removes only the dir whose lease has expired" {
  source "$LIB"
  local expired active
  expired="$(make_round spec 0001 600)"
  active="$(make_round spec 0002 600)"
  printf 'payload-active\n' > "$active/payload.md"
  printf 'payload-expired\n' > "$expired/payload.md"

  # Expire one lease outright; both dirs are backdated, so an age rule would
  # take them both.
  printf 'expires_at 1\n' > "$expired/lease"
  age_dir "$expired"
  age_dir "$active"

  run review_round_sweep
  [ "$status" -eq 0 ]

  [ ! -d "$expired" ] || { echo "the expired round was not reclaimed" >&2; return 1; }
  [ -d "$active" ] || { echo "the OLD BUT ACTIVE round was deleted — age drove the decision" >&2; return 1; }
}

@test "the old-but-active round payload is intact after the sweep" {
  source "$LIB"
  local active
  active="$(make_round spec 0002 600)"
  printf 'payload-active\n' > "$active/payload.md"
  age_dir "$active"

  review_round_sweep

  # Not just the directory: the bytes a reviewer is still reading.
  [ -f "$active/payload.md" ]
  grep -qxF 'payload-active' "$active/payload.md"
}

@test "a dir with a missing lease is removed" {
  source "$LIB"
  local d
  d="$(make_round spec 0003 600)"
  rm -f "$d/lease"

  review_round_sweep
  [ ! -d "$d" ]
}

@test "a dir with an unparseable lease is removed" {
  source "$LIB"
  local d
  d="$(make_round spec 0004 600)"
  printf 'this is not a lease\n' > "$d/lease"

  review_round_sweep
  [ ! -d "$d" ]
}

@test "review_round_sweep takes no age or max-age argument" {
  source "$LIB"
  command -v review_round_sweep >/dev/null 2>&1 || {
    echo "review_round_sweep is not defined; this row would pass vacuously" >&2
    return 1
  }
  local d
  d="$(make_round spec 0005 600)"
  age_dir "$d"

  # Passing one is a usage error, not a silently ignored argument: an ignored
  # --max-age would read as "age sweeping is supported" at every call site.
  run review_round_sweep --max-age 3600
  [ "$status" -ne 0 ]
  run review_round_sweep 3600
  [ "$status" -ne 0 ]

  # And the active round is still there — the rejected call deleted nothing.
  [ -d "$d" ]
}

@test "no age or max-age option exists anywhere in the lib" {
  # The companion static check. Comment lines excluded so the lib may explain
  # why age sweeping is refused; the next row proves the filter still bites.
  run sh -c "cat '$LIB' | grep -vE '^[[:space:]]*#' | grep -nE 'max[-_]age|--age'"
  [ "$status" -ne 0 ]
}

@test "the age-option guard bites on an executable line" {
  local probe="$TEST_DIR/probe.sh"
  printf '%s\n' '# a comment mentioning max-age must not trip it' > "$probe"
  run sh -c "cat '$probe' | grep -vE '^[[:space:]]*#' | grep -nE 'max[-_]age|--age'"
  [ "$status" -ne 0 ]

  printf '%s\n' 'f() { sweep --max-age 60; }' >> "$probe"
  run sh -c "cat '$probe' | grep -vE '^[[:space:]]*#' | grep -nE 'max[-_]age|--age'"
  [ "$status" -eq 0 ]
}

@test "a fresh .building dir survives a concurrent sweep" {
  source "$LIB"
  # A creator part-way through. Its expiry is in the future, so the sweep must
  # leave it alone — otherwise every round creation races the sweeper.
  local now expiry build
  now="$(date +%s)"
  expiry=$((now + 900))
  mkdir -p "$ROUNDS"
  build="$ROUNDS/.building-$expiry-99999-1"
  mkdir -m 0700 "$build"

  review_round_sweep
  [ -d "$build" ] || { echo "a fresh .building dir was reclaimed mid-creation" >&2; return 1; }
}

@test "a .building dir whose encoded expiry has passed is reclaimed" {
  source "$LIB"
  local build
  mkdir -p "$ROUNDS"
  build="$ROUNDS/.building-1-99999-2"
  mkdir -m 0700 "$build"

  review_round_sweep
  [ ! -d "$build" ] || { echo "an abandoned .building dir was never reclaimed" >&2; return 1; }
}

@test "the sweep reads the expiry off the name and never recomputes it" {
  source "$LIB"
  # Two abandoned builders with DIFFERENT encoded expiries, judged on their
  # own thresholds. A sweep that read one config value, or recomputed from
  # now+timeout, could not tell these apart.
  local now future past
  now="$(date +%s)"
  mkdir -p "$ROUNDS"
  future="$ROUNDS/.building-$((now + 900))-99999-3"
  past="$ROUNDS/.building-$((now - 900))-99999-4"
  mkdir -m 0700 "$future" "$past"
  # Both backdated: only the NAME may decide.
  age_dir "$future"
  age_dir "$past"

  review_round_sweep
  [ -d "$future" ] || { echo "the not-yet-expired builder was reclaimed" >&2; return 1; }
  [ ! -d "$past" ] || { echo "the expired builder was not reclaimed" >&2; return 1; }
}

@test "a published round dir is never matched by the .building rule" {
  source "$LIB"
  # A published round whose lease is active must survive even though an
  # abandoned builder with a long-past expiry sits beside it.
  local published build
  published="$(make_round spec 0006 600)"
  mkdir -p "$ROUNDS"
  build="$ROUNDS/.building-1-99999-5"
  mkdir -m 0700 "$build"
  age_dir "$published"

  review_round_sweep
  [ -d "$published" ] || { echo "a published round was taken by the .building rule" >&2; return 1; }
  [ ! -d "$build" ]
}

@test "a created round survives a sweep looped against a creator looped" {
  source "$LIB"
  command -v review_round_sweep >/dev/null 2>&1 || {
    echo "review_round_sweep is not defined; this row would pass vacuously" >&2
    return 1
  }
  # AC14c, the publish race. Without the build-then-rename ordering, a sweep
  # running concurrently with a creator would see a dir under its FINAL name
  # with no lease yet and reclaim it.
  local sweeper_pid i dir
  bash -c "cd '$REPO'; source '$LIB'; set +e; for i in \$(seq 1 60); do review_round_sweep >/dev/null 2>&1; done" &
  sweeper_pid=$!

  local created=0 survived=0
  for i in 1 2 3 4 5 6 7 8 9 10; do
    dir="$(review_round_dir_create spec "007$i" 600)"
    created=$((created + 1))
    [ -d "$dir" ] && survived=$((survived + 1))
    [ -f "$dir/lease" ] || {
      echo "a published round had no lease: $dir" >&2
      kill "$sweeper_pid" 2>/dev/null || true
      return 1
    }
  done

  wait "$sweeper_pid" 2>/dev/null || true
  [ "$survived" -eq "$created" ] || {
    echo "only $survived of $created rounds survived the concurrent sweep" >&2
    return 1
  }
}
