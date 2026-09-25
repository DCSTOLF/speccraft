#!/usr/bin/env bash
# Spec 0049 AC10 conditions 2/3/4 — assert the macOS CI job really is running
# on BSD userland under Bash 5.
#
# WHY THIS EXISTS. The `hooks-macos` job's whole value is that GNU-only shell
# constructs fail there. Install GNU coreutils or gnu-sed onto PATH and the job
# still goes green — while testing nothing, because the GNU tools then behave
# exactly as the buggy code wrongly assumed. All three defects spec 0049 fixes
# would have passed such a job. A prose rule in a workflow file is enforced by
# nothing, so this is a runtime assertion, matching how condition 2 (Bash 5) is
# pinned.
#
# WHY IT IS NOT A BATS TEST. On Linux `tac` resolves and GNU sed is correct and
# expected, so running this live in the bats suite would invert and fail the
# Linux `hooks` job. It is invoked as a workflow step in `hooks-macos` only.
# `tests/hooks/no-gnu-userland.bats` exercises this logic against synthetic
# PATHs through $SPECCRAFT_PROBE_PATH, which is platform-independent.
#
# TWO INDEPENDENT CHECKS per tool, because either alone has a gap:
#   1. PATH SHAPE — reject a resolution under */gnubin/* or */coreutils/libexec/*,
#      the Homebrew layouts that shadow BSD tools.
#   2. BEHAVIOURAL PROBE — reject a tool that accepts `--version` and reports
#      GNU. This catches a GNU binary reached through an unusual symlink that
#      the path check cannot see, which the path check alone would miss.

set -uo pipefail

# The PATH to inspect. Injectable so the bats suite can exercise synthetic
# userlands on any platform; defaults to the real PATH in CI.
probe_path="${SPECCRAFT_PROBE_PATH:-$PATH}"

# Bash major version. Injectable only so the rejection path is testable.
bash_major="${SPECCRAFT_FAKE_BASH_MAJOR:-${BASH_VERSINFO[0]}}"

fail=0
note() { printf '%s\n' "$*" >&2; }

# --- condition 2: Bash 5+ -----------------------------------------------------
# macOS ships Bash 3.2; this repo requires 5+. A job silently running 3.2 would
# pass for the wrong reason, so assert rather than assume.
if [ "$bash_major" -lt 5 ]; then
  note "FAIL: running under bash major ${bash_major}; this suite requires bash 5+."
  note "      macOS ships 3.2 — install bash via Homebrew and invoke the suite through it."
  fail=1
fi

# --- condition 3: no GNU userland ahead of BSD --------------------------------

# Tools whose BSD variants the suite depends on.
required_tools="sed stat date readlink base64 grep awk"

# Tools that must not resolve AT ALL: GNU-only commands, and the `g`-prefixed
# aliases Homebrew installs.
forbidden_tools="tac gsed gstat gdate greadlink gbase64 ggrep gawk"

for t in $required_tools; do
  resolved="$(PATH="$probe_path" command -v "$t" 2>/dev/null || true)"
  if [ -z "$resolved" ]; then
    note "FAIL: required tool '$t' does not resolve on the probe PATH."
    fail=1
    continue
  fi
  case "$resolved" in
    */gnubin/*|*/coreutils/libexec/*)
      note "FAIL: '$t' resolves to a GNU shim: $resolved"
      note "      Remove the coreutils/gnu-sed gnubin prepend — a GNU userland makes this job"
      note "      pass while testing nothing."
      fail=1
      continue
      ;;
  esac
  # Behavioural probe: GNU tools accept --version; BSD tools reject it.
  #
  # Invoke the RESOLVED path, not the bare name: `PATH=x cmd` does not reliably
  # affect the lookup of `cmd` itself in bash (the assignment applies to the
  # command's environment; resolution may already have happened). Using
  # "$resolved" is deterministic and is what we actually want to interrogate.
  if ver="$("$resolved" --version 2>/dev/null)" \
     && printf '%s' "$ver" | grep -q 'GNU'; then
    note "FAIL: '$t' at $resolved is a GNU build (accepted --version and reported GNU)."
    note "      This is the case a path check alone misses — e.g. reached via an unusual symlink."
    fail=1
  fi
done

for t in $forbidden_tools; do
  resolved="$(PATH="$probe_path" command -v "$t" 2>/dev/null || true)"
  if [ -n "$resolved" ]; then
    note "FAIL: GNU-only tool '$t' resolves at $resolved; it must be absent on this runner."
    note "      Its presence means a GNU userland was installed, which defeats this job."
    fail=1
  fi
done

if [ "$fail" -ne 0 ]; then
  note ""
  note "This runner is not the BSD/Bash-5 environment the macOS job requires."
  note "See spec 0049 AC10 for why a GNU-greened job is worse than no job."
  exit 1
fi

printf 'ok: BSD userland, bash %s — no GNU shims on PATH\n' "$bash_major"
