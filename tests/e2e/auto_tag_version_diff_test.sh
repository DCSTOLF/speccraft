#!/usr/bin/env bash
# tests/e2e/auto_tag_version_diff_test.sh — sibling fixture pinning the
# version-diff logic of scripts/auto-tag.sh (spec 0021, AC5).
#
# `auto-tag.sh should_tag` decides whether the version in plugin.json
# needs a new tag. The decision logic is the unit-assertable half of AC5
# ("a merged bump cannot remain untagged"); the actual git push / PAT
# usage lives in the CI workflow and is observed operationally, not here.
#
# For testability the inputs are injected via env:
#   - SPECCRAFT_PLUGIN_JSON — path to the plugin.json to read the version
#   - SPECCRAFT_TAGS        — newline-separated existing tag list (stands
#                             in for `git tag -l`)
# `should_tag` prints the tag to create (`vX.Y.Z`) and exits 0 when no
# matching tag exists; it exits non-zero with no output when the tag is
# already present.
#
#   - Scenario A: version 1.1.0, no matching tag → prints v1.1.0, exit 0.
#   - Scenario B: version 1.1.0, tag v1.1.0 present → exit != 0, no output.
#   - Scenario C: prerelease 1.2.0-rc1, no matching tag → prints
#     v1.2.0-rc1, exit 0 (prerelease tags are allowed per spec).
#
# Exit codes: 0 success, 2 on any assertion failure (via lib.sh fail()).
set -euo pipefail

LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
source "$LIB_DIR/lib.sh"

note() { echo "  $*"; }

echo "==> auto_tag_version_diff_test (spec 0021)"

REPO_ROOT="$(cd "$LIB_DIR/../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/auto-tag.sh"

TMP="$(mktemp -d -t auto-tag-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT

# write_plugin_json <path> <version>
write_plugin_json() {
  printf '{\n  "version": "%s"\n}\n' "$2" > "$1"
}

# run_should_tag <version> <tags> — invoke `auto-tag.sh should_tag` with
# injected version + tag list, capturing stdout into ST_OUT and the exit
# code into ST_RC.
run_should_tag() {
  local version="$1" tags="$2" pj="$TMP/plugin.json"
  write_plugin_json "$pj" "$version"
  set +e
  ST_OUT="$(SPECCRAFT_PLUGIN_JSON="$pj" SPECCRAFT_TAGS="$tags" \
    bash "$SCRIPT" should_tag 2>/dev/null)"
  ST_RC=$?
  set -e
}

# ---------------------------------------------------------------------------
# Scenario A — version not yet tagged → emit the tag, exit 0.
# ---------------------------------------------------------------------------
note "scenario A: untagged version 1.1.0 → prints v1.1.0 (exit 0)"
run_should_tag "1.1.0" "v1.0.0
v0.9.0"
if [ "$ST_RC" -ne 0 ]; then
  fail "scenario A: expected exit 0 for an untagged version, got $ST_RC (out: '$ST_OUT')"
fi
if [ "$ST_OUT" != "v1.1.0" ]; then
  fail "scenario A: expected stdout 'v1.1.0', got '$ST_OUT'"
fi
note "scenario A: ok"

# ---------------------------------------------------------------------------
# Scenario B — version already tagged → no-op (non-zero, no output).
# ---------------------------------------------------------------------------
note "scenario B: already-tagged version 1.1.0 → no-op (exit != 0, no output)"
run_should_tag "1.1.0" "v1.0.0
v1.1.0
v1.2.0"
if [ "$ST_RC" -eq 0 ]; then
  fail "scenario B: expected non-zero exit when the tag already exists, got 0 (out: '$ST_OUT')"
fi
if [ -n "$ST_OUT" ]; then
  fail "scenario B: expected no stdout when the tag exists, got '$ST_OUT'"
fi
note "scenario B: ok"

# ---------------------------------------------------------------------------
# Scenario C — prerelease version, untagged → emit the prerelease tag.
# ---------------------------------------------------------------------------
note "scenario C: untagged prerelease 1.2.0-rc1 → prints v1.2.0-rc1 (exit 0)"
run_should_tag "1.2.0-rc1" "v1.1.0"
if [ "$ST_RC" -ne 0 ]; then
  fail "scenario C: expected exit 0 for an untagged prerelease, got $ST_RC (out: '$ST_OUT')"
fi
if [ "$ST_OUT" != "v1.2.0-rc1" ]; then
  fail "scenario C: expected stdout 'v1.2.0-rc1', got '$ST_OUT'"
fi
note "scenario C: ok"

echo "PASS: auto_tag_version_diff_test.sh"
