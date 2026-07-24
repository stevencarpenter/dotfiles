#!/usr/bin/env bash
# Install the personal agent registry and validate its generated Claude agents.
set -euo pipefail

uv_bin="${UV_BIN:-uv}"
project="${1:-$HOME/.local/share/agent-registry}"

if [ ! -f "$project/pyproject.toml" ]; then
  echo "error: agent registry is missing at $project; run scripts/sync-side-channels.sh first" >&2
  exit 1
fi

if ! command -v "$uv_bin" >/dev/null 2>&1; then
  echo "error: uv is required to install the agent registry" >&2
  exit 1
fi

echo "==> Installing agents from $project"
"$uv_bin" run --directory "$project" python -m agent_registry.cli install

# Refresh the SessionStart routing cache atomically after a successful install.
routing_script="$project/tools/routing/generate_context.py"
routing_cache="$HOME/.cache/agent-routing/context.md"
if [ -f "$routing_script" ]; then
  mkdir -p "$(dirname "$routing_cache")"
  routing_tmp="${routing_cache}.tmp.$$"
  trap 'rm -f "$routing_tmp"' EXIT
  "$uv_bin" run --directory "$project" python "$routing_script" >"$routing_tmp"
  mv "$routing_tmp" "$routing_cache"
  trap - EXIT
fi

# A built-in-only tools allowlist silently strips configured MCP and skill
# access. Treat that as a failed sync instead of leaving a degraded install.
"$uv_bin" run --directory "$project" python - "$HOME/.claude/agents" <<'PYEOF'
from pathlib import Path
import sys

root = Path(sys.argv[1])
builtins = {
    "Read",
    "Write",
    "Edit",
    "MultiEdit",
    "NotebookEdit",
    "Bash",
    "Glob",
    "Grep",
    "LS",
}
violations = []
for path in sorted(root.glob("*.md")) if root.is_dir() else []:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as exc:
        violations.append(f"{path.name}: cannot read: {exc}")
        continue
    if not text.startswith("---\n"):
        continue
    frontmatter = text[4:].split("\n---\n", 1)[0]
    for line_number, line in enumerate(frontmatter.splitlines(), start=2):
        if not line.startswith("tools:"):
            continue
        tools = [part.strip() for part in line.split(":", 1)[1].split(",")]
        tools = [tool for tool in tools if tool]
        if tools and all(tool in builtins for tool in tools):
            violations.append(f"{path.name}:{line_number}: {line}")

if violations:
    print(
        "error: Claude agents contain built-in-only tools allowlists:",
        file=sys.stderr,
    )
    print("\n".join(violations), file=sys.stderr)
    raise SystemExit(1)
PYEOF
