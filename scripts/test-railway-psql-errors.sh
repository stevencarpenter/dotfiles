#!/usr/bin/env bash
# Piped psql must stop on SQL errors and return useful stderr to callers.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

python3 - "$repo_root" <<'PY'
import sys
from pathlib import Path

repo_root = Path(sys.argv[1])
sys.path.insert(0, str(repo_root / "skills/personal/use-railway/scripts"))

import dal  # noqa: E402

captured = {}


def failing_ssh(service, command, timeout):
    captured["service"] = service
    captured["command"] = command
    captured["timeout"] = timeout
    return 3, "", "ERROR: extension is unavailable\n"


dal.run_ssh_query = failing_ssh
code, output = dal.run_psql_query("postgres", "CREATE EXTENSION missing")

assert "-v ON_ERROR_STOP=1" in captured["command"], captured["command"]
assert "2>/dev/null" not in captured["command"], captured["command"]
assert code == 3, code
assert output == "ERROR: extension is unavailable\n", repr(output)
PY

echo "Railway psql errors remain visible and nonzero"
