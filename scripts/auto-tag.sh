#!/usr/bin/env bash
# scripts/auto-tag.sh — version-diff logic for the auto-tag-on-bump CI
# job (spec 0021, AC5).
#
# Usage: auto-tag.sh should_tag
#
# `should_tag` reads the plugin version and the existing tag list and
# decides whether a release tag must be created:
#   - prints "v<version>" to stdout and exits 0 when no matching tag
#     exists (a bumped version that is not yet tagged);
#   - exits 1 with no output when the tag already exists.
#
# Inputs are overridable so the decision logic is unit-testable in
# isolation from git and the actual push:
#   - SPECCRAFT_PLUGIN_JSON — path to plugin.json (default: the plugin's
#     own .claude-plugin/plugin.json)
#   - SPECCRAFT_TAGS        — newline-separated existing tags (default:
#     `git tag -l`)
#
# The actual `git tag` + `git push` (using the RELEASE_TAG_PAT credential,
# NEVER the default GITHUB_TOKEN — GitHub suppresses workflow re-triggers
# for tags pushed by the built-in token) lives in the CI workflow step,
# not here.
set -euo pipefail

PLUGIN_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PLUGIN_JSON="${SPECCRAFT_PLUGIN_JSON:-$PLUGIN_DIR/.claude-plugin/plugin.json}"

should_tag() {
  local version tag tags
  version="$(jq -r '.version' "$PLUGIN_JSON")"
  tag="v$version"
  tags="${SPECCRAFT_TAGS:-$(git tag -l)}"

  if printf '%s\n' "$tags" | grep -qx -- "$tag"; then
    return 1
  fi
  echo "$tag"
  return 0
}

main() {
  local cmd="${1:-}"
  case "$cmd" in
    should_tag) should_tag ;;
    *) echo "usage: auto-tag.sh should_tag" >&2; exit 2 ;;
  esac
}

main "$@"
