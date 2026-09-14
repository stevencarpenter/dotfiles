#!/usr/bin/env bash
# Validate lefthook configuration and the required job list.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${repo_root}"

if ! command -v lefthook >/dev/null 2>&1; then
  echo "FAIL: lefthook is not on PATH (declared in modules/home/packages.nix)" >&2
  exit 1
fi

[[ -f lefthook.yml ]] || { echo "FAIL: lefthook.yml is missing" >&2; exit 1; }
[[ ! -f .pre-commit-config.yaml ]] || {
  echo "FAIL: .pre-commit-config.yaml is back; lefthook.yml is the source of truth" >&2
  exit 1
}

lefthook validate >/dev/null || { echo "FAIL: lefthook validate rejected lefthook.yml" >&2; exit 1; }

# Required checks from the pre-commit migration and local additions.
required_jobs=(
  check-yaml
  check-toml
  check-json
  check-added-large-files
  check-case-conflict
  check-ast
  check-symlinks
  detect-private-key
  forbid-new-submodules
  name-tests-test
  trailing-whitespace
  detect-aws-credentials
  gitleaks
  op-secret-policy
)

failures=0
dump="$(lefthook dump)"
for job in "${required_jobs[@]}"; do
  if ! printf '%s' "${dump}" | rg -Fq "name: ${job}"; then
    echo "FAIL: pre-commit job '${job}' is missing from lefthook.yml" >&2
    failures=$((failures + 1))
  fi
done

# Preserve the commit-msg hook that strips prohibited attribution trailers.
if ! printf '%s' "${dump}" | rg -Fq "scripts/strip-claude-trailer.sh"; then
  echo "FAIL: commit-msg job does not run scripts/strip-claude-trailer.sh" >&2
  failures=$((failures + 1))
fi

# Filter out binary files before trailing-whitespace rewrites to prevent corruption.
if ! printf '%s' "${dump}" | rg -Fq "scripts/hook-text-files.py"; then
  echo "FAIL: trailing-whitespace job lost its scripts/hook-text-files.py filter" >&2
  failures=$((failures + 1))
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "test-lefthook-hooks: ${failures} failure(s)" >&2
  exit 1
fi
echo "test-lefthook-hooks: OK (${#required_jobs[@]} jobs, commit-msg trailer strip, text filter)"
