#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOKEN_AUDITOR_DIR="${REPO_ROOT}/token_auditor"
WORKDIR="$(mktemp -d)"
trap 'rm -rf "${WORKDIR}"' EXIT

if ! command -v uv >/dev/null 2>&1; then
  echo "Error: uv is required but was not found in PATH." >&2
  exit 1
fi

cd "${TOKEN_AUDITOR_DIR}"

uv sync --locked --group dev

uv run ruff check .
uv run ruff format --check .
uv run ty check .

uv run token-auditor --help >/dev/null
uv run codax --help >/dev/null
uv run python -c "import token_auditor.main; import token_auditor.core.codex" >/dev/null

uv run pytest -v

# Build and verify wheel install behavior in a clean environment outside repo cwd.
uv build
WHEEL_PATH="$(ls -1 dist/token_auditor-*.whl | tail -n 1)"
WHEEL_VENV="${WORKDIR}/wheel-venv"
python3 -m venv "${WHEEL_VENV}"
"${WHEEL_VENV}/bin/pip" install --quiet "${WHEEL_PATH}"
(
  cd "${WORKDIR}"
  "${WHEEL_VENV}/bin/token-auditor" --help >/dev/null
  "${WHEEL_VENV}/bin/codax" --help >/dev/null
  "${WHEEL_VENV}/bin/python" -c "import token_auditor.main; import token_auditor.core.codex" >/dev/null
)

# Report startup latency parity (report-only to avoid CI flakiness).
export EDITABLE_CMD="uv run token-auditor --help"
export WHEEL_CMD="${WHEEL_VENV}/bin/token-auditor --help"
export WHEEL_WORKDIR="${WORKDIR}"
python3 - <<'PY'
import os
import shlex
import statistics
import subprocess
import time

def median_runtime(command: str, runs: int, cwd: str | None = None) -> float:
    samples: list[float] = []
    args = shlex.split(command)
    for _ in range(runs):
        start = time.perf_counter()
        subprocess.run(args, cwd=cwd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        samples.append(time.perf_counter() - start)
    return statistics.median(samples)

editable = median_runtime(os.environ["EDITABLE_CMD"], runs=3)
wheel = median_runtime(os.environ["WHEEL_CMD"], runs=3, cwd=os.environ["WHEEL_WORKDIR"])
ratio = (wheel / editable) if editable else 0.0
print(f"[latency] editable median: {editable:.4f}s")
print(f"[latency] wheel median: {wheel:.4f}s")
print(f"[latency] wheel/editable ratio: {ratio:.2f}x")
PY
