#!/usr/bin/env bats
# Spec 0049 T15/T16 (AC10 conditions 2/3/4) — the no-GNU-userland assertion.
#
# Condition 3 ("no GNU userland on PATH ahead of BSD") is the load-bearing one:
# a macOS bats job made green by `brew install coreutils` would have passed
# against all three bugs this spec fixes, because the GNU tools would behave as
# the code wrongly assumed. Condition 2 (Bash 5) already gets a runtime
# assertion for the same "silently the wrong thing" reason, so condition 3 gets
# one too rather than living as prose in a workflow file (review item 1).
#
# WHY THE LIVE ASSERTION IS A CI STEP AND **not a bats test**: on Linux `tac`
# resolves and GNU `sed` is correct and expected, so a live assertion running
# here would invert and fail the Linux `hooks` job. The logic therefore lives in
# `scripts/assert-no-gnu-userland.sh`, invoked as a workflow step in the
# `hooks-macos` job only. This bats file tests that SCRIPT against synthetic
# PATHs (via $SPECCRAFT_PROBE_PATH), which is platform-independent, and pins the
# ci.yml contract by inspection.

setup() {
  PLUGIN_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  SCRIPT="$PLUGIN_DIR/scripts/assert-no-gnu-userland.sh"
  CI="$PLUGIN_DIR/.github/workflows/ci.yml"
  FIX="$(mktemp -d)"
  export PLUGIN_DIR SCRIPT CI FIX
}
teardown() { rm -rf "$FIX"; }

# A synthetic BSD-like userland: the required tools present, none of them GNU,
# and no `tac`/`gsed` at all. `--version` is REJECTED by these stubs, which is
# how BSD tools behave and what the behavioral probe keys on.
make_bsd_path() {
  local d="$FIX/bsd"; mkdir -p "$d"
  local t
  # awk is included because the AC8 reversal depends on it, so the script
  # treats it as required.
  for t in sed stat date readlink base64 grep awk; do
    cat > "$d/$t" <<'EOS'
#!/usr/bin/env bash
for a in "$@"; do
  case "$a" in
    --version) echo "illegal option -- -" >&2; exit 1 ;;
  esac
done
exit 0
EOS
    chmod +x "$d/$t"
  done
  printf '%s\n' "$d"
}

# A GNU stub: accepts --version and says so.
make_gnu_tool() {
  local dir="$1" name="$2"
  mkdir -p "$dir"
  cat > "$dir/$name" <<EOS
#!/usr/bin/env bash
for a in "\$@"; do
  case "\$a" in
    --version) echo "$name (GNU coreutils) 9.4"; exit 0 ;;
  esac
done
exit 0
EOS
  chmod +x "$dir/$name"
}

@test "assert-no-gnu-userland PASSES a synthetic BSD-only PATH" {
  bsd="$(make_bsd_path)"
  SPECCRAFT_PROBE_PATH="$bsd" run bash "$SCRIPT"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

@test "assert-no-gnu-userland FLAGS a gnubin-shadowed sed" {
  bsd="$(make_bsd_path)"
  gnubin="$FIX/opt/homebrew/opt/gnu-sed/libexec/gnubin"
  make_gnu_tool "$gnubin" sed
  SPECCRAFT_PROBE_PATH="$gnubin:$bsd" run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'sed'
}

@test "assert-no-gnu-userland FLAGS a coreutils/libexec-shadowed stat" {
  bsd="$(make_bsd_path)"
  cu="$FIX/opt/homebrew/opt/coreutils/libexec/gnubin"
  make_gnu_tool "$cu" stat
  SPECCRAFT_PROBE_PATH="$cu:$bsd" run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'stat'
}

@test "assert-no-gnu-userland FLAGS a resolvable gsed" {
  bsd="$(make_bsd_path)"
  make_gnu_tool "$FIX/extra" gsed
  SPECCRAFT_PROBE_PATH="$FIX/extra:$bsd" run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'gsed'
}

@test "assert-no-gnu-userland FLAGS a resolvable tac" {
  bsd="$(make_bsd_path)"
  make_gnu_tool "$FIX/extra" tac
  SPECCRAFT_PROBE_PATH="$FIX/extra:$bsd" run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'tac'
}

# Review item 2 (codex): the path check alone misses a GNU binary reached
# through an unusual symlink — one NOT under */gnubin/* or */coreutils/libexec/*.
# The behavioral `--version` probe catches it, because GNU tools accept
# --version and BSD tools reject it.
@test "assert-no-gnu-userland FLAGS a GNU sed reached through an unusual symlink" {
  bsd="$(make_bsd_path)"
  make_gnu_tool "$FIX/somewhere/odd" sed
  SPECCRAFT_PROBE_PATH="$FIX/somewhere/odd:$bsd" run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  # Case-SENSITIVE 'GNU': the script's own path contains the lowercase string
  # "no-gnu-userland", so a case-insensitive match would pass vacuously on
  # bash's "no such file" error before the script even exists.
  echo "$output" | grep -q 'GNU'
}

@test "assert-no-gnu-userland asserts the running interpreter is Bash 5+" {
  grep -q 'BASH_VERSINFO' "$SCRIPT"
  # And it must actually reject an older major when told one.
  SPECCRAFT_PROBE_PATH="$(make_bsd_path)" SPECCRAFT_FAKE_BASH_MAJOR=3 run bash "$SCRIPT"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'bash'
}

@test "ci.yml: hooks-macos runs the full suite on macos-14 through Homebrew Bash 5" {
  grep -q 'hooks-macos' "$CI"
  grep -q 'macos-14' "$CI"
  grep -q 'bats-core' "$CI"
  grep -q 'assert-no-gnu-userland.sh' "$CI"
}

@test "ci.yml: hooks-macos installs NO GNU userland and prepends no gnubin" {
  run grep -nE 'brew install .*(coreutils|gnu-sed|gsed|findutils|gawk)' "$CI"
  [ "$status" -ne 0 ] || { echo "GNU userland install would mask the defects this job exists to catch:"; echo "$output"; false; }
  run grep -n 'gnubin' "$CI"
  [ "$status" -ne 0 ] || { echo "gnubin must never be prepended:"; echo "$output"; false; }
}

# Pinned mechanically (review item 1): the live assertion must NOT be a bats
# test, or the Linux `hooks` job would run it — where `tac` resolves and GNU sed
# is expected — and it would invert. It is a workflow step, ahead of bats.
@test "the live no-GNU assertion is a ci.yml step, not a bats test" {
  # No bats file may INVOKE the script without a synthetic probe PATH. Target
  # invocation lines specifically (`bash "$SCRIPT"`) rather than any mention of
  # the name — @test titles and `grep -q ... "$SCRIPT"` reads legitimately name
  # it, and matching those would make this assertion permanently false.
  # Scoped to THIS file: `$SCRIPT` is a per-file variable and other suites
  # (verify-linux-pins.bats) legitimately invoke their own script by that name.
  # Scanning all of tests/hooks would flag those and make this permanently red.
  run bash -c "grep -n 'bash \"\\\$SCRIPT\"' '$BATS_TEST_FILENAME' | grep -vE '^[0-9]+:[[:space:]]*#' | grep -v 'SPECCRAFT_PROBE_PATH'"
  [ "$status" -ne 0 ] || { echo "the assertion must only run under a synthetic PATH in bats:"; echo "$output"; false; }
  # And the workflow must invoke it BEFORE the bats step.
  a="$(grep -n 'assert-no-gnu-userland.sh' "$CI" | head -1 | cut -d: -f1)"
  b="$(awk '/hooks-macos/{f=1} f && /bats tests\/hooks/{print NR; exit}' "$CI")"
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" -lt "$b" ]
}
