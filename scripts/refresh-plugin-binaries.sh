# scripts/dev/refresh-plugin-binaries.sh
#!/usr/bin/env bash
set -euo pipefail
repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
shopt -s nullglob
for dir in "$HOME/.claude/plugins/cache/dcstolf-tools/speccraft/"*/bin; do
  for b in speccraft-state speccraft-guard speccraft-drift; do
    (cd "$repo/tools" && go build -o "$dir/$b" "./cmd/$b")
  done
  echo "refreshed $dir -> $("$dir/speccraft-guard" --version)"
done