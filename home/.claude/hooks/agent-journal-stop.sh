#!/usr/bin/env bash
set -euo pipefail

config="${HOME}/.config/agent-journal/config.toml"
project="${HOME}/projects/agent-journal"

[[ -f "$config" && -f "$project/pyproject.toml" ]] || exit 0
command -v uv >/dev/null 2>&1 || exit 0

uv run --project "$project" agent-journal ingest --quiet >/dev/null 2>&1 || exit 0
uv run --project "$project" agent-journal digest --quiet >/dev/null 2>&1 || exit 0
