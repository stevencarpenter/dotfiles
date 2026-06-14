#!/usr/bin/env bash
# Regression test for ca()'s target-drift safety gate.
#
# ca() ends in `chezmoi apply --force`, which suppresses chezmoi's own per-file
# overwrite prompt. The ONLY remaining guard against silently clobbering
# target-side edits is ca()'s upfront drift check. A naive
# `chezmoi status | _ca_has_target_drift` pipe hides a `chezmoi status` failure:
# the `if` reads the pipeline exit as a drift boolean, and _ca_has_target_drift
# reports "no drift" on empty input regardless of WHY the input was empty — so a
# failed status probe would fall through to a forced apply. (pipefail does not
# help: in a boolean-predicate pipe, non-zero is non-zero either way.) This test
# pins the capture-then-check fix: a status failure must ABORT before apply,
# while a clean status must still reach apply.
#
# The harness is bash (so the CI `bash -n` sweep passes); the zsh function under
# test runs in a `zsh -df` subshell with `chezmoi` stubbed.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
lib="${repo_root}/dot_config/zsh/lib/chezmoi-apply.zsh"

if ! command -v zsh >/dev/null 2>&1; then
  echo "ca() drift-gate test requires zsh (the function under test is zsh)" >&2
  exit 1
fi

# Run ca() with a stubbed chezmoi whose `status` exits with the given code.
# `diff` always succeeds (empty), `apply` prints a sentinel so we can detect
# whether the gate let execution reach the forced apply.
run_case() {
  local status_rc="$1"
  zsh -df <<ZEOF
emulate -R zsh
chezmoi() {
  case "\$1" in
    diff) return 0 ;;
    status) return ${status_rc} ;;
    apply) print -r -- "APPLIED"; return 0 ;;
    *) return 0 ;;
  esac
}
source "${lib}"
ca 2>&1
ZEOF
}

# Scenario A: `chezmoi status` fails — ca() must abort before the forced apply.
out_fail="$(run_case 1 || true)"
if [[ "${out_fail}" == *"APPLIED"* ]]; then
  {
    echo "FAIL: a 'chezmoi status' failure fell through to 'chezmoi apply --force'"
    printf '%s\n' "${out_fail}"
  } >&2
  exit 1
fi

# Scenario B: `chezmoi status` succeeds with no drift — ca() must still apply.
out_ok="$(run_case 0)"
if [[ "${out_ok}" != *"APPLIED"* ]]; then
  {
    echo "FAIL: a clean status did not reach 'chezmoi apply'"
    printf '%s\n' "${out_ok}"
  } >&2
  exit 1
fi

echo "ca() drift gate aborts on status failure and applies on clean status"
