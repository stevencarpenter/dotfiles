#!/usr/bin/env bash
# Assert the lefthook config still covers everything .pre-commit-config.yaml did.
#
# Why: the pre-commit -> lefthook port (2026-08-29) re-expressed 14 checks as
# shell jobs. Two failure modes are silent. A job whose glob matches nothing
# never runs and reports success, and a check dropped in the port leaves no
# trace at all. This pins the job list and proves the config parses.
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

# Every check carried over from the retired pre-commit config, plus the two
# local ones. A rename here is a deliberate act, not a drive-by edit.
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

# The commit-msg hook is what strips AI attribution trailers; losing it would
# be invisible until a bad trailer reached a public commit.
if ! printf '%s' "${dump}" | rg -Fq "scripts/strip-claude-trailer.sh"; then
  echo "FAIL: commit-msg job does not run scripts/strip-claude-trailer.sh" >&2
  failures=$((failures + 1))
fi

# A rewriting job handed a binary corrupts it, so the text filter must stay in
# the trailing-whitespace pipeline (verified during the port on a PNG).
if ! printf '%s' "${dump}" | rg -Fq "scripts/hook-text-files.py"; then
  echo "FAIL: trailing-whitespace job lost its scripts/hook-text-files.py filter" >&2
  failures=$((failures + 1))
fi

# Prove the file-scoped jobs actually match files rather than silently
# no-opping: run the whole group over every tracked file.
# stderr is kept: without it the failure message names no job, and the whole
# point of this check is to learn WHICH glob stopped matching.
if ! lefthook run pre-commit --all-files --force --no-auto-install --no-stage-fixed >/dev/null; then
  echo "FAIL: 'lefthook run pre-commit --all-files' did not pass on a clean tree" >&2
  failures=$((failures + 1))
fi

if [[ "${failures}" -gt 0 ]]; then
  echo "test-lefthook-hooks: ${failures} failure(s)" >&2
  exit 1
fi
echo "test-lefthook-hooks: OK (${#required_jobs[@]} jobs, commit-msg trailer strip, text filter)"
