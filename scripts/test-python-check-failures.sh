#!/usr/bin/env bash
# Verify Python recipes stop at the first failing project command.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'rm -rf "$fixture"' EXIT
mkdir -p "$fixture/bin" "$fixture/versions"
cp "$repo_root/versions/token-auditor" "$fixture/versions/token-auditor"
cat >"$fixture/bin/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$TEST_COMMAND_LOG"
case "$*" in
  *mcp_sync*) exit 42 ;;
esac
EOF
chmod +x "$fixture/bin/uv"

for recipe in lint test fmt py-check; do
  log="$fixture/$recipe.log"
  rc=0
  PATH="$fixture/bin:$PATH" TEST_COMMAND_LOG="$log" \
    just --justfile "$repo_root/Justfile" --working-directory "$fixture" "$recipe" \
    >"$fixture/$recipe.out" 2>&1 || rc=$?
  if [ "$rc" -eq 0 ] || [ "$(wc -l <"$log" | tr -d ' ')" -ne 1 ]; then
    echo "FAIL: $recipe did not stop at the first project failure" >&2
    cat "$fixture/$recipe.out" >&2
    exit 1
  fi
done
echo "Python recipes propagate the first project failure"
