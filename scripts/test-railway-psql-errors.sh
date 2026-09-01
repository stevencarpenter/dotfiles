#!/usr/bin/env bash
# Piped psql must stop on SQL errors and return useful stderr to callers.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"${repo_root}/scripts/assert-railway-psql-errors.py" "$repo_root"

echo "Railway psql errors remain visible and nonzero"
